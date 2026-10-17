#import "MTCaptureCoordinator.h"
#import "MTCaptureTask.h"
#import "MTCaptureProvider.h"
#import "MTLongShotSession.h"
#import "../Common/MTConstants.h"
#import "../Common/MTCaptureLog.h"
#import "../Common/MTPhotoShortcut.h"
#import "../Common/MTCapturePreferences.h"
#import "../Common/MTShellXBridge.h"
#import "../Output/MTOutputPipeline.h"
#import "../Output/MTLongImageComposer.h"
#import "../Output/MTTemporaryFileStore.h"
#import "../Overlay/MTCaptureWindow.h"
#import "../Overlay/MTSelectionView.h"
#import "../Overlay/MTResultBubble.h"
#import "../Overlay/MTFloatingSnap.h"
#import "../Editor/MTEditorViewController.h"

static const CGFloat MTFramesToWaitBeforeCapture = 2.0;
/// 与 MTSelectionView 的选区下限一致；恢复上次选区时钳制用。
static const CGFloat MTSelectionMinimumSize = 44.0;
// 自发自收抑制（主线程读写）：工具栏外调 SHELLX 的官方触发名与本方 SHELLX/Snapper3
// 兼容别名同名，Darwin 中心会把自发通知也投递回本进程，外调前按名武装一次，
// 回环到达时吞掉，否则画板会双开（MetisCapture 一块、SHELLX 一块）。
static NSString *_Nullable mtDarwinSelfPostArmedName = nil;

@interface MTCaptureCoordinator () <MTSelectionViewDelegate, MTResultBubbleDelegate,
                                    MTFloatingSnapDelegate,
                                    MTLongShotSessionDelegate,
                                    MTEditorViewControllerDelegate>
@property (nonatomic, strong) NSLock *taskLock;
@property (nonatomic, strong, nullable) MTCaptureTask *activeTask;      // taskLock 保护
@property (nonatomic, strong) MTCaptureProvider *provider;
@property (nonatomic, strong) MTOutputPipeline *pipeline;
// 以下引用只在主线程读写
@property (nonatomic, strong, nullable) MTCaptureWindow *captureWindow;
@property (nonatomic, strong, nullable) MTSelectionView *selectionView;
@property (nonatomic, copy, nullable) NSString *selectionCaptureRequestID; // 实时区域在途抓屏，主线程
@property (nonatomic, strong, nullable) MTResultBubble *resultBubble;
@property (nonatomic, strong, nullable) MTLongShotSession *longShotSession;   // 三模式长截图会话（主线程）
@property (nonatomic, strong) NSMutableArray<MTFloatingSnap *> *floatingSnaps; // 主线程，多图独立保留
@property (nonatomic, strong, nullable) MTFloatingSnap *editingFloatingSnap;
@property (nonatomic, strong, nullable) MTCaptureWindow *editorWindow;
@property (nonatomic, strong, nullable) MTEditorViewController *editorController;
@property (nonatomic, strong, nullable) UIImage *preEditImage;   // 进入编辑器前的结果图（取消编辑时恢复）
@end

static MTCaptureCoordinator *_sharedCoordinator = nil;

@implementation MTCaptureCoordinator

+ (instancetype)sharedCoordinator {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedCoordinator = [[MTCaptureCoordinator alloc] init];
    });
    return _sharedCoordinator;
}

- (instancetype)init {
    if (self = [super init]) {
        _taskLock = [[NSLock alloc] init];
        _provider = [[MTCaptureProvider alloc] init];
        _pipeline = [[MTOutputPipeline alloc] init];
        _floatingSnaps = [[NSMutableArray alloc] init];

        // 选区期间设备旋转会使基础快照与屏幕几何错位；直接取消任务保证正确性。
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(mtOrientationDidChange:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)start {
    // tmp 清扫是纯磁盘 IO：不在 %ctor（主线程）同步执行。
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [MTTemporaryFileStore sweepAllTaskDirectories];
    });
    [MTCapturePreferences config];
    MTCaptureLogInfo(@"coordinator started (capture method %@)", [MTCaptureProvider resolvedCaptureMethod]);
}

#pragma mark - 请求入口

- (void)handleDarwinNotificationName:(NSString *)name {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self handleDarwinNotificationName:name]; });
        return;
    }
    if (mtDarwinSelfPostArmedName && [name isEqualToString:mtDarwinSelfPostArmedName]) {
        MTCaptureLogInfo(@"darwin notification self-post suppressed: %@", name);
        mtDarwinSelfPostArmedName = nil;
        return;
    }
    if ([name isEqualToString:(__bridge NSString *)MTDarwinPreferencesReload]) {
        [MTCapturePreferences reload];
        return;
    }
    if ([name isEqualToString:(__bridge NSString *)MTDarwinCaptureCancel] ||
        [name isEqualToString:(__bridge NSString *)MTDarwinSnapperCloseAll] ||
        [name isEqualToString:(__bridge NSString *)MTDarwinSnapperCloseCrop] ||
        [name isEqualToString:(__bridge NSString *)MTDarwinShellXClose]) {
        [self cancelActiveTask];
        return;
    }

    MTCaptureMode mode = -1;
    if ([name isEqualToString:(__bridge NSString *)MTDarwinCaptureFull]) mode = MTCaptureModeFull;
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinCaptureArea]) mode = MTCaptureModeArea;
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinCaptureFreeze]) mode = MTCaptureModeFreeze;
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinCaptureInstant]) mode = MTCaptureModeInstant;
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinCaptureMarkup]) mode = MTCaptureModeMarkup;
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinCaptureLong]) mode = MTCaptureModeLong;
    // 启动入口通知：默认区域截图，与显式 capture/full 区分。
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinActivate]) mode = MTCaptureModeArea;
    // Snapper3 兼容别名：force.open 是 Snapper3 的框选流程，对应区域截图。
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinSnapperForceOpen]) mode = MTCaptureModeArea;
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinSnapperForceInstantOpen]) mode = MTCaptureModeInstant;
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinSnapperForceFreezeOpen]) mode = MTCaptureModeFreeze;
    // SHELLX 兼容别名：open/open.instant/open.freeze 与其框选/即时/冻结流程对应。
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinShellXOpen]) mode = MTCaptureModeArea;
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinShellXOpenInstant]) mode = MTCaptureModeInstant;
    else if ([name isEqualToString:(__bridge NSString *)MTDarwinShellXOpenFreeze]) mode = MTCaptureModeFreeze;

    if (mode >= MTCaptureModeFull && mode <= MTCaptureModeLong) {
        [self requestCapture:mode];
    }
}

- (void)requestCapture:(MTCaptureMode)mode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self requestCapture:mode]; });
        return;
    }

    MTConfig *config = MTCapturePreferences.config;
    if (!config.enabled) {
        MTCaptureLogInfo(@"MetisCapture disabled, request ignored (%@)", MTStringFromCaptureMode(mode));
        return;
    }

    MTCaptureTask *task = [self mtAcquireTaskForMode:mode config:config];
    if (!task) {
        MTCaptureLogWarn(@"request ignored: another task is busy (%@)", MTStringFromCaptureMode(mode));
        return;
    }

    MTCaptureLogInfo(@"capture request accepted (mode %@, task %@)", MTStringFromCaptureMode(mode), task.taskID);
    [self mtRunCaptureForTask:task];
}

- (void)cancelActiveTask {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self cancelActiveTask]; });
        return;
    }

    [self mtCancelCurrentTaskClosingFloatingSnaps:YES];
}

- (void)mtCancelCurrentTaskClosingFloatingSnaps:(BOOL)closeFloating {
    MTCaptureTask *task = [self mtCurrentTask];
    if (closeFloating) {
        for (MTFloatingSnap *snap in [self.floatingSnaps copy]) [snap dismissWithCompletion:nil];
        self.editingFloatingSnap = nil;
    }
    if (!task) return;

    if (![task transitionToState:MTCaptureStateCancelling]) {
        MTCaptureLogWarn(@"cancel ignored for state %@", MTStringFromCaptureState(task.state));
        return;
    }
    [self mtTeardownLongShotSession];
    [self mtDestroyCaptureWindow];
    [self mtDestroyEditorWindow];
    self.editingFloatingSnap = nil;
    [self mtRestoreFloatingSnaps];
    self.preEditImage = nil;   // 取消后不再持有整图引用（最长可驻留到下次编辑会话）
    [task transitionToState:MTCaptureStateCancelled];
    [MTTemporaryFileStore removeTaskDirectory:task.taskID];
    [self mtClearSlotIfCurrent:task];
    MTCaptureLogInfo(@"task cancelled");
}

#pragma mark - 捕获流程

- (void)mtRunCaptureForTask:(MTCaptureTask *)task {
    if (task.mode == MTCaptureModeArea) {
        [self mtHideOwnOverlays];
        [self mtPresentSelectionForTask:task];
        return;  // 透明覆盖真实画面，打开时不建立会过期的底图。
    }
    if (![task transitionToState:MTCaptureStateCapturing]) {
        [self mtFailTask:task code:@"state" message:@"任务状态异常"];
        return;
    }

    // 抓屏前隐藏自有覆盖层，并等待两帧，确保合成器不再包含 MetisCapture 窗口。
    [self mtHideOwnOverlays];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MTFramesToWaitBeforeCapture / 60.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (![self mtIsTaskCurrent:task]) return;
        [self.provider captureWithCompletion:^(UIImage *image, BOOL isPartial, NSString *captureMethod, NSError *error) {
            if (![self mtIsTaskCurrent:task] || task.state != MTCaptureStateCapturing) {
                return;   // 已取消/已被新任务取代
            }
            if (!image) {
                [self mtFailTask:task code:@"capture" message:(error.localizedDescription ?: @"屏幕抓取失败")];
                return;
            }
            task.baseImage = image;
            task.isPartialCapture = isPartial;
            if (isPartial) {
                MTCaptureLogWarn(@"capture fell back to partial snapshot path");
            }
            if (![task transitionToState:MTCaptureStateCaptured]) return;

            if (task.mode == MTCaptureModeMarkup) {
                if (isPartial) {
                    [self mtFailTask:task code:@"partial-capture" message:@"当前抓取接口无法取得完整屏幕，不能开始全屏标记"];
                    return;
                }
                task.resultImage = image;
                if (![task transitionToState:MTCaptureStatePresenting]) return;
                [self mtPresentEditorForTask:task];
            } else if (task.mode == MTCaptureModeLong) {
                if (isPartial) {
                    [self mtFailTask:task code:@"partial-capture" message:@"无法取得完整屏幕，不能开始滚动截图"];
                    return;
                }
                if (![task transitionToState:MTCaptureStatePresenting]) return;
                [self mtStartLongShotForTask:task mode:task.configSnapshot.longShotOptions.mode
                                displayRect:task.capturedScreenBounds];
            } else if (task.mode == MTCaptureModeFull) {
                [self mtHandleFullscreenResult:task];
            } else {
                [self mtPresentSelectionForTask:task];
            }
        }];
    });
}

- (void)mtHandleFullscreenResult:(MTCaptureTask *)task {
    task.resultImage = task.baseImage;
    if (![task transitionToState:MTCaptureStatePresenting]) return;
    MTOutputAction action = task.configSnapshot.defaultResultAction;
    [self mtExecuteOutput:action forTask:task presentingWindow:nil];
}

- (void)mtPresentSelectionForTask:(MTCaptureTask *)task {
    if (![task transitionToState:MTCaptureStatePresenting]) return;

    [self mtDestroyCaptureWindow];
    MTCaptureWindow *window = [MTCaptureWindow mtCaptureWindow];
    MTSelectionView *view = [[MTSelectionView alloc] initWithFrame:window.bounds
                                                         baseImage:task.baseImage
                                                              mode:task.mode
                                                          delegate:self];
    [self mtApplyRememberedSelectionRect:view task:task bounds:window.bounds];
    [window hostContentView:view];
    self.captureWindow = window;
    self.selectionView = view;
    // 选区窗口按约定成为 key（同编辑器路径）。跨进程触摸抢占另靠实时取景的低透明度底色：
    // key 不足以从 App 手里截触摸（v2.2.1 实测 App 内仍穿透），全透明区域会被窗口服务器跳过。
    [window showAnimated:(task.mode != MTCaptureModeInstant) becomeKey:YES];
    MTCaptureLogInfo(@"selection presented (mode %@, task %@)", MTStringFromCaptureMode(task.mode), task.taskID);
}

#pragma mark - 选区回调

- (void)selectionView:(MTSelectionView *)view
   didConfirmDisplayRect:(CGRect)displayRect
                 action:(MTOutputAction)action {
    MTCaptureTask *task = [self mtCurrentTaskIfState:MTCaptureStatePresenting];
    if (!task || view != self.selectionView || !view.userInteractionEnabled) return;
    [self mtPersistSelectionRect:displayRect config:task.configSnapshot];
    [self mtCropAndOutput:task displayRect:displayRect overrideAction:action];
}

- (void)selectionViewDidCancel:(MTSelectionView *)view {
    // “记住上次选区”口径是上一次调整的结果：取消同样按当前选区落盘（开关关闭时内部清空）。
    MTCaptureTask *task = [self mtCurrentTaskIfState:MTCaptureStatePresenting];
    if (task) {
        [self mtPersistSelectionRect:view.selectionRect config:task.configSnapshot];
    }
    [self mtCancelCurrentTaskClosingFloatingSnaps:NO];
}

- (void)selectionViewDidRequestFreeze:(MTSelectionView *)view {
    MTCaptureTask *task = [self mtCurrentTaskIfState:MTCaptureStatePresenting];
    if (!task || task.mode != MTCaptureModeArea || task.areaFrameFrozen ||
        view != self.selectionView || !view.userInteractionEnabled) return;
    [self mtPrepareSelectionSourceForTask:task
             keepWindowHiddenAfterCapture:NO
                               completion:^(BOOL ready, NSError *error) {
        if (ready) {
            task.areaFrameFrozen = YES;
            [view applyFrozenImage:task.baseImage];
            MTCaptureLogInfo(@"selection freeze applied (task %@)", task.taskID);
        } else {
            [view showFreezeFailure];
            MTCaptureLogWarn(@"selection freeze failed (task %@ error=%ld)", task.taskID, (long)error.code);
        }
        view.userInteractionEnabled = YES;
    }];
}

- (void)selectionViewDidRequestFullscreenMarkup:(MTSelectionView *)view {
    // 无视当前框选：按取消口径收掉选区窗口（含“记住上次选区”落盘），
    // 再走全屏标记任务的常规入口重抓屏；悬浮图与「取消」同口径保留。
    [self selectionViewDidCancel:view];
    MTCaptureLogInfo(@"selection toolbar requested fullscreen markup");
    [self requestCapture:MTCaptureModeMarkup];
}

- (void)selectionView:(MTSelectionView *)view didRequestCustomURL:(NSURL *)url {
    // 自定义 URL 按钮：选区会话到此结束（不产出图片），再交给系统 URL 分发层。
    // openURL 的完成回调线程不确定，只记日志；打开失败时目标 App 未注册该 scheme。
    [self selectionViewDidCancel:view];
    MTCaptureLogInfo(@"selection toolbar custom url opened: %@", url.absoluteString);
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        MTCaptureLogInfo(@"custom url opened: %@ success=%d", url.absoluteString, success);
    }];
}

- (void)selectionViewDidRequestEditor:(MTSelectionView *)view displayRect:(CGRect)displayRect {
    MTCaptureTask *task = [self mtCurrentTaskIfState:MTCaptureStatePresenting];
    if (!task || view != self.selectionView || !view.userInteractionEnabled) return;
    [self mtPersistSelectionRect:displayRect config:task.configSnapshot];
    [self mtCropInBackground:task displayRect:displayRect completion:^(UIImage *cropped) {
        if (![self mtIsTaskCurrent:task]) return;
        if (!cropped) {
            [self mtFailTask:task code:@"crop" message:@"选区裁剪失败"];
            return;
        }
        task.resultImage = cropped;
        [self mtDestroyCaptureWindow];
        [self mtPresentEditorForTask:task];
    }];
}

- (void)selectionViewDidRequestFloat:(MTSelectionView *)view displayRect:(CGRect)displayRect {
    MTCaptureTask *task = [self mtCurrentTaskIfState:MTCaptureStatePresenting];
    if (!task || view != self.selectionView || !view.userInteractionEnabled) return;
    if (!view.window) return;
    CGRect screenRect = [view convertRect:displayRect toCoordinateSpace:view.window.screen.coordinateSpace];
    [self mtPersistSelectionRect:displayRect config:task.configSnapshot];
    [self mtCropInBackground:task displayRect:displayRect completion:^(UIImage *cropped) {
        if (![self mtIsTaskCurrent:task] || task.state != MTCaptureStatePresenting) return;
        if (!cropped) {
            [self mtFailTask:task code:@"crop" message:@"选区裁剪失败"];
            return;
        }
        task.resultImage = cropped;
        [self mtDestroyCaptureWindow];
        [self mtPresentFloatingSnapForTask:task screenRect:screenRect];
    }];
}

#pragma mark - 三模式长截图会话

- (void)mtStartLongShotForTask:(MTCaptureTask *)task mode:(MTLongShotMode)mode displayRect:(CGRect)displayRect {
    if (![self mtIsTaskCurrent:task] || task.state != MTCaptureStatePresenting) return;
    [self mtTeardownLongShotSession];
    [self mtDestroyCaptureWindow];
    self.longShotSession = [MTLongShotSession startWithTask:task
                                                     mode:mode
                                                 displayRect:displayRect
                                                   delegate:self];
    if (!self.longShotSession) {
        [self mtFailTask:task code:@"longshot" message:@"长截图会话创建失败"];
    }
}

// 选区工具栏与外部入口采用同一模式配置；选区同时限定采集裁片与短滑视口。
- (void)selectionViewDidRequestLong:(MTSelectionView *)view displayRect:(CGRect)displayRect {
    MTCaptureTask *task = [self mtCurrentTaskIfState:MTCaptureStatePresenting];
    if (!task || task.areaFrameFrozen || view != self.selectionView || !view.userInteractionEnabled) return;
    [self mtPersistSelectionRect:displayRect config:task.configSnapshot];
    [self mtStartLongShotForTask:task mode:task.configSnapshot.longShotOptions.mode displayRect:displayRect];
}

/// 外部取消/失败路径的会话清理：会话自毁不回调，任务状态由调用方推进。
- (void)mtTeardownLongShotSession {
    if (!self.longShotSession) return;
    [self.longShotSession teardownForExternalCancel];
    self.longShotSession = nil;
}

- (void)longShotSessionDidFinish:(MTLongShotSession *)session resultImage:(UIImage *)image {
    MTCaptureTask *task = [self mtCurrentTaskIfState:MTCaptureStatePresenting];
    if (self.longShotSession == session) self.longShotSession = nil;
    if (!task || !image) return;

    task.resultImage = image;
    // 拼接产物在任务临时目录：登记路径供气泡缩略图降采样（此刻目录尚未清理）。
    NSString *stitchedPath = [[[task ensureTemporaryDirectory]
        stringByAppendingPathComponent:@"longshot.jpg"] copy];
    if ([[NSFileManager defaultManager] fileExistsAtPath:stitchedPath]) {
        task.resultFilePath = stitchedPath;
    }
    CGFloat pixelHeight = image.size.height * image.scale;
    MTOutputAction action = task.configSnapshot.defaultResultAction;
    // 巨型长图写入剪贴板会在 SpringBoard 内触发 PNG 编码尖峰，降级为保存（诊断优先）。
    if (pixelHeight > (CGFloat)MTLongShotCopyMaxPixelHeight &&
        (action == MTOutputActionCopy || action == MTOutputActionSaveAndCopy)) {
        MTCaptureLogWarn(@"long shot %.0f px exceeds copy limit, downgraded to save (task %@)",
                  pixelHeight, task.taskID);
        action = MTOutputActionSave;
    }
    [self mtExecuteOutput:action forTask:task presentingWindow:nil];
}

- (void)longShotSessionDidCancel:(MTLongShotSession *)session {
    if (self.longShotSession == session) self.longShotSession = nil;
    [self mtCancelCurrentTaskClosingFloatingSnaps:NO];
}

- (void)longShotSessionDidFail:(MTLongShotSession *)session message:(NSString *)message {
    MTCaptureTask *task = [self mtCurrentTaskIfState:MTCaptureStatePresenting];
    if (self.longShotSession == session) self.longShotSession = nil;
    if (!task) return;
    [self mtFailTask:task code:@"longshot" message:(message ?: @"长图拼接失败")];
}

- (void)selectionViewDidRequestShellXAction:(MTSelectionView *)view action:(MTShellXAction)action {
    // SHELLX 收到信号后会重抓屏或弹全屏界面：先把本方选区窗口收掉，避免截进本方画板。
    // 悬浮图是用户主动常驻的内容，与「取消」同口径保留；关闭动作不涉及重抓屏，本方会话不动。
    if (action != MTShellXActionClose) {
        [self mtCancelCurrentTaskClosingFloatingSnaps:NO];
    }
    // 武装自发自收抑制：区域/即时/冻结/关闭的官方触发名与本方 SHELLX 兼容别名同名
    // （Darwin 中心把自发通知也投递回本进程），外调前按名武装一次，回环到达时吞掉，
    // 否则画板双开（MetisCapture 一块、SHELLX 一块）。记录/最近一张/整屏（AssistiveScreenshot
    // 通知）本方均未监听，无回环；套壳等 URL 类动作不经过通知中心，也无回环。
    switch (action) {
        case MTShellXActionArea:
        case MTShellXActionInstant:
        case MTShellXActionFreeze:
        case MTShellXActionClose:
            mtDarwinSelfPostArmedName = [MTShellXBridge notificationNameForAction:action];
            break;
        case MTShellXActionHistory:
        case MTShellXActionOpenLast:
        case MTShellXActionAssistive:
        case MTShellXActionLongShot:
        case MTShellXActionFullShot:
        case MTShellXActionMark:
        case MTShellXActionEdit:
        case MTShellXActionAI2:
        case MTShellXActionTranslate:
        case MTShellXActionScan:
            break;
    }
    [MTShellXBridge notifyAction:action];
}

#pragma mark - 选区记忆（AreaRememberLastRect，默认关）

/// 开关关闭时清掉历史矩形，避免下次打开开关先弹出一个陈旧选区。
- (void)mtPersistSelectionRect:(CGRect)rect config:(MTConfig *)config {
    id value = config.areaRememberLastRect ? (id)NSStringFromCGRect(rect) : (id)nil;
    CFPreferencesSetAppValue((__bridge CFStringRef)MTKeyAreaLastSelectionRect,
                             (__bridge CFTypeRef)value,
                             (__bridge CFStringRef)MTCapturePreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)MTCapturePreferencesDomain);
}

/// 上次选区只作初值：按当前窗口钳制，跨旋转/跨分辨率不合法时保持空选区（等用户手动框选）。
- (void)mtApplyRememberedSelectionRect:(MTSelectionView *)view
                                  task:(MTCaptureTask *)task
                                bounds:(CGRect)bounds {
    if (!task.configSnapshot.areaRememberLastRect) return;
    NSString *csv = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)MTKeyAreaLastSelectionRect,
        (__bridge CFStringRef)MTCapturePreferencesDomain));
    if (csv.length == 0) return;
    CGRect saved = CGRectFromString(csv);
    if (CGRectIsEmpty(saved)) return;
    CGRect clamped = MTClampSelectionRect(saved, bounds.size, MTSelectionMinimumSize);
    if (CGRectIsEmpty(clamped)) return;
    [view applyDefaultSelectionRect:clamped];
}

- (void)mtCropAndOutput:(MTCaptureTask *)task
             displayRect:(CGRect)displayRect
          overrideAction:(MTOutputAction)overrideAction {
    [self mtCropInBackground:task displayRect:displayRect completion:^(UIImage *cropped) {
        if (![self mtIsTaskCurrent:task]) return;
        if (!cropped) {
            [self mtFailTask:task code:@"crop" message:@"选区裁剪失败"];
            return;
        }
        task.resultImage = cropped;
        [self mtDestroyCaptureWindow];
        MTOutputAction action = (overrideAction == MTOutputActionPreviewOnly)
            ? task.configSnapshot.defaultResultAction
            : overrideAction;
        [self mtExecuteOutput:action forTask:task presentingWindow:nil];
    }];
}

#pragma mark - 裁剪

/// 区域输出与手动冻结共用：排除选框窗口抓取当时画面，冻结后复用不可变底图。
/// keepWindowHiddenAfterCapture 为 YES（输出路径）时抓屏后窗口保持隐藏直到销毁，
/// 避免「恢复显示→归一化+裁剪期间暗罩重现→再销毁」的闪烁；NO（冻结路径）维持原行为。
- (void)mtPrepareSelectionSourceForTask:(MTCaptureTask *)task
           keepWindowHiddenAfterCapture:(BOOL)keepWindowHiddenAfterCapture
                             completion:(void (^)(BOOL ready, NSError *error))completion {
    NSParameterAssert(NSThread.isMainThread);
    MTSelectionView *view = self.selectionView;
    MTCaptureWindow *window = self.captureWindow;
    if (![self mtIsTaskCurrent:task] || task.state != MTCaptureStatePresenting ||
        !view || !view.userInteractionEnabled || !window || view.window != window ||
        self.selectionCaptureRequestID) return;
    view.userInteractionEnabled = NO;
    if (task.mode != MTCaptureModeArea || task.areaFrameFrozen) {
        completion(task.baseImage != nil, nil);
        return;
    }

    NSString *requestID = NSUUID.UUID.UUIDString;
    self.selectionCaptureRequestID = requestID;
    MTCaptureProvider *provider = [MTCaptureProvider new];
    provider.detachesCapturedImage = YES;  // 冻结图必须拥有独立位图，不能随源表面变化。
    provider.keepsExcludedWindowsHiddenAfterCapture = keepWindowHiddenAfterCapture;
    MTCaptureLogInfo(@"selection live capture began (task %@ request %@)", task.taskID, requestID);
    [provider captureExcludingWindows:@[window] completion:^(UIImage *image, BOOL isPartial,
                                                            NSString *captureMethod, NSError *error) {
        // 输出路径抓屏后窗口保持隐藏，不检查 window.hidden；窗口销毁路径已由
        // selectionCaptureRequestID 置空兜底，销毁或隐藏本身不构成放弃条件。
        if (![self.selectionCaptureRequestID isEqualToString:requestID] ||
            ![self mtIsTaskCurrent:task] || task.state != MTCaptureStatePresenting ||
            self.selectionView != view || self.captureWindow != window ||
            view.window != window) return;
        self.selectionCaptureRequestID = nil;
        // 抓屏隐藏窗口期间 key 可能被摘走；冻结路径窗口仍留在屏上，须补回，否则冻结后选区失触。
        [window reassertKeyIfNeeded];
        BOOL geometryMatches = CGRectEqualToRect(UIScreen.mainScreen.bounds, task.capturedScreenBounds) &&
                               UIScreen.mainScreen.scale == task.capturedScreenScale &&
                               CGSizeEqualToSize(view.bounds.size, task.capturedScreenBounds.size) &&
                               (!image || (CGSizeEqualToSize(image.size, task.capturedScreenBounds.size) &&
                                           image.scale == task.capturedScreenScale));
        if (!image || isPartial || !geometryMatches) {
            NSError *failure = error ?: [NSError errorWithDomain:MTCaptureErrorDomain
                code:geometryMatches ? MTCaptureErrorCaptureFailed : MTCaptureErrorUnexpectedGeometry
                userInfo:@{NSLocalizedDescriptionKey: geometryMatches
                    ? @"当前抓取接口无法取得完整屏幕" : @"屏幕尺寸已变化，请重新框选"}];
            MTCaptureLogWarn(@"selection live capture failed (task %@ partial=%d geometry=%d method=%@)",
                      task.taskID, isPartial, geometryMatches, captureMethod);
            completion(NO, failure);
            return;
        }
        task.baseImage = image;
        task.isPartialCapture = NO;
        MTCaptureLogInfo(@"selection live capture ready (task %@ method=%@)", task.taskID, captureMethod);
        completion(YES, nil);
    }];
}

- (void)mtCropInBackground:(MTCaptureTask *)task
                displayRect:(CGRect)displayRect
                 completion:(void (^)(UIImage *))completion {
    MTSelectionView *view = self.selectionView;
    [self mtPrepareSelectionSourceForTask:task
             keepWindowHiddenAfterCapture:YES
                               completion:^(BOOL ready, NSError *error) {
        if (!ready) { completion(nil); return; }
        // 实时抓屏已复查几何；冻结路径始终使用同一任务的固定几何和底图。
        UIImage *baseImage = task.baseImage;
        CGSize pixelSize = CGSizeMake(baseImage.size.width * baseImage.scale,
                                      baseImage.size.height * baseImage.scale);
        CGRect pixelRect = MTConvertDisplayRectToPixel(displayRect, task.capturedScreenBounds.size, pixelSize);
        if (CGRectIsEmpty(pixelRect)) { completion(nil); return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            UIImage *cropped = [self mtCropImage:baseImage pixelRect:pixelRect];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![self mtIsTaskCurrent:task] || task.state != MTCaptureStatePresenting ||
                    self.selectionView != view) return;
                completion(cropped);
            });
        });
    }];
}

- (UIImage *)mtCropImage:(UIImage *)image pixelRect:(CGRect)pixelRect {
    CGImageRef cg = image.CGImage;
    if (!cg) return nil;
    // 必须立即解码成独立位图：抓屏结果是 IOSurface 载体图像，ImageInRect 只产生引用
    // 原表面的惰性子图。SpringBoard 渲染管线展示这种子图在 iOS 17 真机上只绘出顶部
    // 一条、其余全黑（CPU 解码路径如 JPEG 保存不受影响，同图对比已证实）。本方法
    // 只在后台队列调用，解码成本不占主线程。
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 (NSUInteger)pixelRect.size.width,
                                                 (NSUInteger)pixelRect.size.height,
                                                 8, 0,
                                                 CGImageGetColorSpace(cg),
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (!context) return nil;
    CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, pixelRect.size.width, pixelRect.size.height));
    CGContextClipToRect(context, CGRectMake(0, 0, pixelRect.size.width, pixelRect.size.height));
    // pixelRect 是顶部原点（ImageInRect 约定），CG 上下文是底部原点：
    // ty = h - H + origin.y 把源像素行 origin.y 对齐到输出首行，防止裁出垂直错位区域。
    CGContextTranslateCTM(context,
                          -pixelRect.origin.x,
                          pixelRect.size.height - CGImageGetHeight(cg) + pixelRect.origin.y);
    CGContextDrawImage(context,
                       CGRectMake(0, 0, CGImageGetWidth(cg), CGImageGetHeight(cg)), cg);
    CGImageRef cropped = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!cropped) return nil;
    UIImage *result = [UIImage imageWithCGImage:cropped scale:image.scale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    return result;
}

#pragma mark - 输出与收尾

- (void)mtExecuteOutput:(MTOutputAction)action
                 forTask:(MTCaptureTask *)task
        presentingWindow:(UIWindow *)presentingWindow {
    if (![task transitionToState:MTCaptureStateExporting]) {
        MTCaptureLogWarn(@"cannot output in state %@", MTStringFromCaptureState(task.state));
        return;
    }
    MTCaptureLogInfo(@"output requested (action %@, task %@)", MTStringFromOutputAction(action), task.taskID);
    [self.pipeline performAction:action
                          forTask:task
                presentingWindow:presentingWindow
                      completion:^(BOOL ok, NSString *message) {
        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self mtReportCompletion:task ok:ok message:message]; });
            return;
        }
        [self mtReportCompletion:task ok:ok message:message];
    }];
}

- (void)mtReportCompletion:(MTCaptureTask *)task ok:(BOOL)ok message:(NSString *)message {
    if (![self mtIsTaskCurrent:task]) return;
    MTCaptureLogInfo(@"output completed (ok=%d, task %@): %@", ok, task.taskID, message ?: @"");

    if (ok) {
        [task transitionToState:MTCaptureStateFinished];
        if (task.configSnapshot.screenshotHaptic) {
            UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [haptic impactOccurred];
        }
    } else {
        // 输出失败：保留临时文件供诊断，失败原因在气泡中显示（重新截图重试）。
        [task transitionToState:MTCaptureStateFailed];
        [task unclaimOutputAction:MTOutputActionSave];
        [task unclaimOutputAction:MTOutputActionCopy];
        [task unclaimOutputAction:MTOutputActionShare];
        MTCaptureLogWarn(@"output failed, temp files kept for retry (task %@)", task.taskID);
    }

    if (task.configSnapshot.showResultBubble) {
        // 先同步弹出气泡（即时反馈，也消除“待弹泡窗口期被新截图截入”的竞态），
        // 缩略图后台渲染后回填（P1-4：大图解码不占主线程）。
        CGFloat screenScale = [UIScreen mainScreen].scale;
        UIImage *resultImage = task.resultImage;
        // 长图优先从落盘产物降采样（受限解码，不为 88pt 小图整幅解出 8MP 位图，
        // 两次长截图之间不给 SpringBoard 抬基线）；无落盘文件时回退内存解码。
        NSString *thumbnailPath = task.resultFilePath;
        self.resultBubble = [MTResultBubble presentWithImage:nil
                                                     message:(message ?: @"截图完成")
                                                        task:task
                                                   succeeded:ok
                                                    delegate:self];
        MTResultBubble *bubble = self.resultBubble;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                UIImage *thumbnail = thumbnailPath.length
                    ? [MTLongImageComposer thumbnailImageFromFile:thumbnailPath screenScale:screenScale
                                                     maxPixelSize:88.0 * MAX(2.0, screenScale)]
                    : nil;
                if (!thumbnail) thumbnail = [self mtThumbnailForImage:resultImage screenScale:screenScale];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [bubble updateThumbnailImage:thumbnail];
                });
                // 缩略图已独立于源文件，输出成功后再回收任务临时目录（失败路径保留）。
                if (ok) [MTTemporaryFileStore removeTaskDirectory:task.taskID];
            }
        });
    } else if (ok) {
        // 输出成功不再需要重试，任务临时目录立即回收（失败路径保留供诊断）。
        [MTTemporaryFileStore removeTaskDirectory:task.taskID];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:MTNotificationResultUpdated object:nil];
    [self mtClearSlotIfCurrent:task];
    // 悬浮窗随任务结束恢复展示（抓屏前被 mtHideOwnOverlays 暂时隐藏）。
    self.editingFloatingSnap = nil;
    [self mtRestoreFloatingSnaps];
}

#pragma mark - 悬浮窗

- (void)mtRestoreFloatingSnaps {
    for (MTFloatingSnap *snap in self.floatingSnaps) [snap restoreAfterCapture];
}

/// 窗口成功创建后才报告成功，保留其他悬浮图并释放当前任务槽。
- (void)mtPresentFloatingSnapForTask:(MTCaptureTask *)task screenRect:(CGRect)screenRect {
    if (![self mtIsTaskCurrent:task] || ![task transitionToState:MTCaptureStateExporting]) return;
    MTFloatingSnap *snap = [MTFloatingSnap presentWithImage:task.resultImage mode:task.mode
                                                 delegate:self screenRect:screenRect
                                                    shadow:task.configSnapshot.floatingSnapShadow];
    if (!snap) {
        [self mtFailTask:task code:@"floating-window" message:@"悬浮图片显示失败"];
        return;
    }
    [self.floatingSnaps addObject:snap];
    [task transitionToState:MTCaptureStateFinished];
    [MTTemporaryFileStore removeTaskDirectory:task.taskID];
    [self mtClearSlotIfCurrent:task];
    [self mtRestoreFloatingSnaps];
    if (task.configSnapshot.screenshotHaptic) {
        UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [haptic impactOccurred];
    }
    MTCaptureLogInfo(@"floating snap added (count %lu)", (unsigned long)self.floatingSnaps.count);
}

- (void)floatingSnapDidRequestEdit:(MTFloatingSnap *)snap {
    if (![self.floatingSnaps containsObject:snap]) return;
    UIImage *image = snap.image;
    MTCaptureMode mode = snap.captureMode;
    // 先占任务槽再隐藏当前图；取消编辑时原图恢复，其他悬浮不受影响。
    MTCaptureTask *task = [self mtAcquireTaskForMode:mode config:MTCapturePreferences.config];
    if (!task) {
        MTCaptureLogWarn(@"float re-edit ignored: another task is busy");
        self.resultBubble = [MTResultBubble presentWithImage:nil
                                                     message:@"当前有任务进行中，请稍后重试"
                                                        task:nil
                                                   succeeded:NO
                                                    delegate:self];
        return;
    }
    task.isReedit = YES;
    self.editingFloatingSnap = snap;
    [snap hideForCapture];
    [self mtBeginEditorForAcquiredTask:task image:image];
}

- (void)floatingSnapDidRequestOutput:(MTFloatingSnap *)snap action:(MTOutputAction)action {
    if (![self.floatingSnaps containsObject:snap]) return;
    UIImage *image = snap.image;
    MTCaptureMode mode = snap.captureMode;
    MTConfig *config = MTCapturePreferences.config;
    MTCaptureTask *task = [self mtAcquireTaskForMode:mode config:config];
    if (!task) {
        MTCaptureLogWarn(@"float output ignored: another task is busy");
        self.resultBubble = [MTResultBubble presentWithImage:nil
                                                     message:@"当前有任务进行中，请稍后重试"
                                                        task:nil
                                                   succeeded:NO
                                                    delegate:self];
        return;
    }
    task.baseImage = image;
    task.resultImage = image;
    [task transitionToState:MTCaptureStateCapturing];
    [task transitionToState:MTCaptureStateCaptured];
    [self mtExecuteOutput:action forTask:task presentingWindow:nil];
}

- (void)floatingSnapDidClose:(MTFloatingSnap *)snap {
    [self.floatingSnaps removeObjectIdenticalTo:snap];
    if (self.editingFloatingSnap == snap) self.editingFloatingSnap = nil;
    MTCaptureLogInfo(@"floating snap removed (count %lu)", (unsigned long)self.floatingSnaps.count);
}

#pragma mark - 编辑器

- (void)mtPresentEditorForTask:(MTCaptureTask *)task {
    if (!task.resultImage) {
        [self mtFailTask:task code:@"editor" message:@"没有可编辑的结果"];
        return;
    }
    if (![task transitionToState:MTCaptureStateEditing]) {
        MTCaptureLogWarn(@"cannot enter editing in state %@", MTStringFromCaptureState(task.state));
        return;
    }

    // 取消编辑时恢复到进入编辑器前的结果（不是 baseImage 整屏快照）。
    self.preEditImage = task.resultImage;

    CGSize px = CGSizeMake(task.resultImage.size.width * task.resultImage.scale,
                           task.resultImage.size.height * task.resultImage.scale);
    MTCaptureLogInfo(@"editor present (mode %@, image %.0fx%.0f px, task %@)",
              MTStringFromCaptureMode(task.mode), px.width, px.height, task.taskID);

    [self mtDestroyEditorWindow];
    MTEditorViewController *editor = [[MTEditorViewController alloc] initWithImage:task.resultImage delegate:self];
    editor.fullscreenMarkup = (task.mode == MTCaptureModeMarkup);
    editor.backdropImage = task.baseImage;
    MTCaptureWindow *window = [MTCaptureWindow mtCaptureWindow];
    window.rootViewController = editor;
    self.editorWindow = window;
    self.editorController = editor;
    [window showAnimated:NO];
    MTCaptureLogInfo(@"editor visible (mode %@, task %@)", MTStringFromCaptureMode(task.mode), task.taskID);
}

/// 气泡重编辑入口：以新任务进入编辑器。
- (void)openEditorWithImage:(UIImage *)image mode:(MTCaptureMode)mode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openEditorWithImage:image mode:mode]; });
        return;
    }
    MTConfig *config = MTCapturePreferences.config;
    MTCaptureTask *task = [self mtAcquireTaskForMode:mode config:config];
    if (!task) {
        MTCaptureLogWarn(@"re-edit ignored: another task is busy");
        return;
    }
    task.isReedit = YES;
    [self mtBeginEditorForAcquiredTask:task image:image];
}

/// 任务槽已由调用方占好的编辑器进入路径。
- (void)mtBeginEditorForAcquiredTask:(MTCaptureTask *)task image:(UIImage *)image {
    task.baseImage = image;
    task.resultImage = image;
    [task transitionToState:MTCaptureStateCapturing];
    [task transitionToState:MTCaptureStateCaptured];
    [task transitionToState:MTCaptureStatePresenting];
    [self mtPresentEditorForTask:task];
}

- (void)editorController:(MTEditorViewController *)controller didFinishWithImage:(UIImage *)image action:(MTOutputAction)action {
    if (controller != self.editorController) return;
    MTCaptureTask *task = [self mtCurrentTaskIfState:MTCaptureStateEditing];
    [self mtDestroyEditorWindow];
    self.preEditImage = nil;
    if (!task) return;

    task.resultImage = image;
    [self.editingFloatingSnap updateImage:image];
    if (![task transitionToState:MTCaptureStatePresenting]) return;
    MTOutputAction output = (action == MTOutputActionPreviewOnly) ? task.configSnapshot.defaultResultAction : action;
    [self mtExecuteOutput:output forTask:task presentingWindow:nil];
}

- (void)editorControllerDidCancel:(MTEditorViewController *)controller {
    if (controller != self.editorController) return;
    MTCaptureTask *task = [self mtCurrentTaskIfState:MTCaptureStateEditing];
    [self mtDestroyEditorWindow];
    if (!task) return;

    // 取消编辑并恢复进入编辑器前的结果（原图未被破坏，DEVELOPMENT.md 5.6）。
    if (self.preEditImage) {
        task.resultImage = self.preEditImage;
    }
    self.preEditImage = nil;
    if (![task transitionToState:MTCaptureStatePresenting]) return;

    // 关闭/取消一律终止任务：不产出、不弹结果气泡。旧实现在此处对非重编辑
    // 任务补发 defaultResultAction，SaveAlsoCopy 默认开后变成「取消仍保存+复制」。
    [self mtCancelCurrentTaskClosingFloatingSnaps:NO];
}

- (void)mtDestroyEditorWindow {
    if (self.editorController) {
        // 先断开控制器内的手势引用环，再摘视图、清引用（顺序不可换）。
        [self.editorController prepareForDismissal];
        [self.editorController.view removeFromSuperview];
        self.editorController = nil;
    }
    if (self.editorWindow) {
        MTCaptureWindow *window = self.editorWindow;
        self.editorWindow = nil;
        [window hideAndDestroyWithCompletion:nil];
    }
}

#pragma mark - 气泡回调

/// 点气泡主体（气泡只有缩略图/文案区）：按本次输出动作分流。
/// 保存类（保存 / 保存并复制）→ 进相册最近照片；纯复制 → 关闭气泡；
/// 其余动作进编辑器；失败气泡不响应。
- (void)resultBubbleDidTapBody:(MTResultBubble *)bubble {
    MTCaptureTask *task = bubble.task;
    if (!task || [task currentState] != MTCaptureStateFinished) return;
    if ([task isOutputActionClaimed:MTOutputActionSave]) {
        // 保存并复制同时认领两个动作，按保存类处理。
        MTCaptureLogInfo(@"result bubble tap -> photos recents (task %@)", task.taskID);
        [MTPhotoShortcut openMostRecentPhoto];
        [bubble dismissWithCompletion:nil];
        return;
    }
    if ([task isOutputActionClaimed:MTOutputActionCopy]) {
        MTCaptureLogInfo(@"result bubble tap -> dismiss (copy action, task %@)", task.taskID);
        [bubble dismissWithCompletion:nil];
        return;
    }
    UIImage *image = task.resultImage ?: task.baseImage;
    if (!image) return;
    [bubble dismissWithCompletion:nil];
    [self openEditorWithImage:image mode:task.mode];
}

- (void)resultBubbleDidDismiss:(MTResultBubble *)bubble {
    // 只清理仍指向该气泡的引用，避免误清新气泡（交叠窗口极短但存在）。
    if (self.resultBubble == bubble) {
        self.resultBubble = nil;
    }
}

#pragma mark - 异常与辅助

- (void)mtOrientationDidChange:(NSNotification *)notification {
    // 选区期间旋转：基础快照与屏幕几何错位，直接取消。
    if (self.selectionView) {
        MTCaptureTask *task = [self mtCurrentTaskIfState:MTCaptureStatePresenting];
        if (task && task.mode != MTCaptureModeFull) {
            MTCaptureLogWarn(@"orientation changed during selection, cancelling task");
            [self mtCancelCurrentTaskClosingFloatingSnaps:NO];
        }
        return;
    }
    // 长截图会话中旋转：采集屏幕坐标失效，同样直接取消。
    if (self.longShotSession) {
        MTCaptureLogWarn(@"orientation changed during long shot, cancelling task");
        [self mtCancelCurrentTaskClosingFloatingSnaps:NO];
    }
}

- (void)mtFailTask:(MTCaptureTask *)task code:(NSString *)code message:(NSString *)message {
    task.errorCode = code;
    task.errorMessage = message;
    [self mtTeardownLongShotSession];
    [self mtDestroyCaptureWindow];
    [task transitionToState:MTCaptureStateFailed];
    [MTTemporaryFileStore removeTaskDirectory:task.taskID];
    MTCaptureLogError(@"task failed [%@]: %@", code, message);
    // 失败气泡不受 ShowResultBubble 控制：失败原因必须可见（诊断优先）。
    self.resultBubble = [MTResultBubble presentWithImage:nil
                                                 message:message
                                                    task:nil
                                               succeeded:NO
                                                delegate:self];
    [self mtClearSlotIfCurrent:task];
    self.editingFloatingSnap = nil;
    [self mtRestoreFloatingSnaps];
}

- (void)mtHideOwnOverlays {
    if (self.resultBubble) {
        [self.resultBubble dismissWithCompletion:nil];
    }
    // 悬浮窗是新任务的抓屏对象之一：抓屏前隐藏，任务收尾再恢复。
    for (MTFloatingSnap *snap in self.floatingSnaps) [snap hideForCapture];
}

- (void)mtDestroyCaptureWindow {
    self.selectionCaptureRequestID = nil;
    if (self.selectionView) {
        [self.selectionView prepareForDismissal];
        self.selectionView = nil;
    }
    if (self.captureWindow) {
        MTCaptureWindow *window = self.captureWindow;
        self.captureWindow = nil;
        [window hideAndDestroyWithCompletion:nil];
    }
}

- (UIImage *)mtThumbnailForImage:(UIImage *)image screenScale:(CGFloat)screenScale {
    if (!image) return nil;
    CGSize target = CGSizeMake(88, 88);
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = screenScale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGFloat scale = MAX(target.width / image.size.width, target.height / image.size.height);
        CGSize drawSize = CGSizeMake(image.size.width * scale, image.size.height * scale);
        CGRect drawRect = CGRectMake((target.width - drawSize.width) / 2,
                                     (target.height - drawSize.height) / 2,
                                     drawSize.width, drawSize.height);
        [image drawInRect:drawRect];
    }];
}

#pragma mark - 任务槽（taskLock 只保护这些临界区）

- (MTCaptureTask *)mtAcquireTaskForMode:(MTCaptureMode)mode config:(MTConfig *)config {
    [self.taskLock lock];
    MTCaptureTask *task = nil;
    if (!self.activeTask || !MTCaptureStateIsBusy(self.activeTask.state)) {
        task = [[MTCaptureTask alloc] initWithMode:mode
                                             config:config
                                       screenBounds:[UIScreen mainScreen].bounds
                                        screenScale:[UIScreen mainScreen].scale];
        [task transitionToState:MTCaptureStatePreparing];
        self.activeTask = task;
    }
    [self.taskLock unlock];
    return task;
}

- (MTCaptureTask *)mtCurrentTask {
    [self.taskLock lock];
    MTCaptureTask *task = self.activeTask;
    [self.taskLock unlock];
    return task;
}

- (MTCaptureTask *)mtCurrentTaskIfState:(MTCaptureState)state {
    [self.taskLock lock];
    MTCaptureTask *task = self.activeTask;
    BOOL match = (task && task.state == state);
    [self.taskLock unlock];
    return match ? task : nil;
}

- (BOOL)mtIsTaskCurrent:(MTCaptureTask *)task {
    [self.taskLock lock];
    BOOL current = (self.activeTask == task);
    [self.taskLock unlock];
    return current;
}

- (void)mtClearSlotIfCurrent:(MTCaptureTask *)task {
    [self.taskLock lock];
    if (self.activeTask == task) {
        self.activeTask = nil;
    }
    [self.taskLock unlock];
}

@end
