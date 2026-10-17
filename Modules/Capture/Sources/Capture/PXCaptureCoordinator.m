#import "PXCaptureCoordinator.h"
#import "PXCaptureTask.h"
#import "PXCaptureProvider.h"
#import "PXLongShotSession.h"
#import "../Common/PXConstants.h"
#import "../Common/PXLog.h"
#import "../Common/PXPhotoShortcut.h"
#import "../Common/PXPreferences.h"
#import "../Common/PXShellXBridge.h"
#import "../Output/PXOutputPipeline.h"
#import "../Output/PXLongImageComposer.h"
#import "../Output/PXTemporaryFileStore.h"
#import "../Overlay/PXCaptureWindow.h"
#import "../Overlay/PXSelectionView.h"
#import "../Overlay/PXResultBubble.h"
#import "../Overlay/PXFloatingSnap.h"
#import "../Editor/PXEditorViewController.h"

static const CGFloat PXFramesToWaitBeforeCapture = 2.0;
/// 与 PXSelectionView 的选区下限一致；恢复上次选区时钳制用。
static const CGFloat PXSelectionMinimumSize = 44.0;
// 自发自收抑制（主线程读写）：工具栏外调 SHELLX 的官方触发名与本方 SHELLX/Snapper3
// 兼容别名同名，Darwin 中心会把自发通知也投递回本进程，外调前按名武装一次，
// 回环到达时吞掉，否则画板会双开（PixPin 一块、SHELLX 一块）。
static NSString *_Nullable pxDarwinSelfPostArmedName = nil;

@interface PXCaptureCoordinator () <PXSelectionViewDelegate, PXResultBubbleDelegate,
                                    PXFloatingSnapDelegate,
                                    PXLongShotSessionDelegate,
                                    PXEditorViewControllerDelegate>
@property (nonatomic, strong) NSLock *taskLock;
@property (nonatomic, strong, nullable) PXCaptureTask *activeTask;      // taskLock 保护
@property (nonatomic, strong) PXCaptureProvider *provider;
@property (nonatomic, strong) PXOutputPipeline *pipeline;
// 以下引用只在主线程读写
@property (nonatomic, strong, nullable) PXCaptureWindow *captureWindow;
@property (nonatomic, strong, nullable) PXSelectionView *selectionView;
@property (nonatomic, copy, nullable) NSString *selectionCaptureRequestID; // 实时区域在途抓屏，主线程
@property (nonatomic, strong, nullable) PXResultBubble *resultBubble;
@property (nonatomic, strong, nullable) PXLongShotSession *longShotSession;   // 三模式长截图会话（主线程）
@property (nonatomic, strong) NSMutableArray<PXFloatingSnap *> *floatingSnaps; // 主线程，多图独立保留
@property (nonatomic, strong, nullable) PXFloatingSnap *editingFloatingSnap;
@property (nonatomic, strong, nullable) PXCaptureWindow *editorWindow;
@property (nonatomic, strong, nullable) PXEditorViewController *editorController;
@property (nonatomic, strong, nullable) UIImage *preEditImage;   // 进入编辑器前的结果图（取消编辑时恢复）
@end

static PXCaptureCoordinator *_sharedCoordinator = nil;

@implementation PXCaptureCoordinator

+ (instancetype)sharedCoordinator {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedCoordinator = [[PXCaptureCoordinator alloc] init];
    });
    return _sharedCoordinator;
}

- (instancetype)init {
    if (self = [super init]) {
        _taskLock = [[NSLock alloc] init];
        _provider = [[PXCaptureProvider alloc] init];
        _pipeline = [[PXOutputPipeline alloc] init];
        _floatingSnaps = [[NSMutableArray alloc] init];

        // 选区期间设备旋转会使基础快照与屏幕几何错位；直接取消任务保证正确性。
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pxOrientationDidChange:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)start {
    // tmp 清扫是纯磁盘 IO：不在 %ctor（主线程）同步执行。
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [PXTemporaryFileStore sweepAllTaskDirectories];
    });
    [PXPreferences config];
    PXLogInfo(@"coordinator started (capture method %@)", [PXCaptureProvider resolvedCaptureMethod]);
}

#pragma mark - 请求入口

- (void)handleDarwinNotificationName:(NSString *)name {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self handleDarwinNotificationName:name]; });
        return;
    }
    if (pxDarwinSelfPostArmedName && [name isEqualToString:pxDarwinSelfPostArmedName]) {
        PXLogInfo(@"darwin notification self-post suppressed: %@", name);
        pxDarwinSelfPostArmedName = nil;
        return;
    }
    if ([name isEqualToString:(__bridge NSString *)PXDarwinPreferencesReload]) {
        [PXPreferences reload];
        return;
    }
    if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureCancel] ||
        [name isEqualToString:(__bridge NSString *)PXDarwinSnapperCloseAll] ||
        [name isEqualToString:(__bridge NSString *)PXDarwinSnapperCloseCrop] ||
        [name isEqualToString:(__bridge NSString *)PXDarwinShellXClose]) {
        [self cancelActiveTask];
        return;
    }

    PXCaptureMode mode = -1;
    if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureFull]) mode = PXCaptureModeFull;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureArea]) mode = PXCaptureModeArea;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureFreeze]) mode = PXCaptureModeFreeze;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureInstant]) mode = PXCaptureModeInstant;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureMarkup]) mode = PXCaptureModeMarkup;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureLong]) mode = PXCaptureModeLong;
    // 启动入口（裸 pixpin://）：默认区域截图，与显式 capture/full 区分。
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinActivate]) mode = PXCaptureModeArea;
    // Snapper3 兼容别名：force.open 是 Snapper3 的框选流程，对应区域截图。
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinSnapperForceOpen]) mode = PXCaptureModeArea;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinSnapperForceInstantOpen]) mode = PXCaptureModeInstant;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinSnapperForceFreezeOpen]) mode = PXCaptureModeFreeze;
    // SHELLX 兼容别名：open/open.instant/open.freeze 与其框选/即时/冻结流程对应。
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinShellXOpen]) mode = PXCaptureModeArea;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinShellXOpenInstant]) mode = PXCaptureModeInstant;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinShellXOpenFreeze]) mode = PXCaptureModeFreeze;

    if (mode >= PXCaptureModeFull && mode <= PXCaptureModeLong) {
        [self requestCapture:mode];
    }
}

- (void)requestCapture:(PXCaptureMode)mode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self requestCapture:mode]; });
        return;
    }

    PXConfig *config = PXPreferences.config;
    if (!config.enabled) {
        PXLogInfo(@"PixPin disabled, request ignored (%@)", PXStringFromCaptureMode(mode));
        return;
    }

    PXCaptureTask *task = [self pxAcquireTaskForMode:mode config:config];
    if (!task) {
        PXLogWarn(@"request ignored: another task is busy (%@)", PXStringFromCaptureMode(mode));
        return;
    }

    PXLogInfo(@"capture request accepted (mode %@, task %@)", PXStringFromCaptureMode(mode), task.taskID);
    [self pxRunCaptureForTask:task];
}

- (void)cancelActiveTask {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self cancelActiveTask]; });
        return;
    }

    [self pxCancelCurrentTaskClosingFloatingSnaps:YES];
}

- (void)pxCancelCurrentTaskClosingFloatingSnaps:(BOOL)closeFloating {
    PXCaptureTask *task = [self pxCurrentTask];
    if (closeFloating) {
        for (PXFloatingSnap *snap in [self.floatingSnaps copy]) [snap dismissWithCompletion:nil];
        self.editingFloatingSnap = nil;
    }
    if (!task) return;

    if (![task transitionToState:PXCaptureStateCancelling]) {
        PXLogWarn(@"cancel ignored for state %@", PXStringFromCaptureState(task.state));
        return;
    }
    [self pxTeardownLongShotSession];
    [self pxDestroyCaptureWindow];
    [self pxDestroyEditorWindow];
    self.editingFloatingSnap = nil;
    [self pxRestoreFloatingSnaps];
    self.preEditImage = nil;   // 取消后不再持有整图引用（最长可驻留到下次编辑会话）
    [task transitionToState:PXCaptureStateCancelled];
    [PXTemporaryFileStore removeTaskDirectory:task.taskID];
    [self pxClearSlotIfCurrent:task];
    PXLogInfo(@"task cancelled");
}

#pragma mark - 捕获流程

- (void)pxRunCaptureForTask:(PXCaptureTask *)task {
    if (task.mode == PXCaptureModeArea) {
        [self pxHideOwnOverlays];
        [self pxPresentSelectionForTask:task];
        return;  // 透明覆盖真实画面，打开时不建立会过期的底图。
    }
    if (![task transitionToState:PXCaptureStateCapturing]) {
        [self pxFailTask:task code:@"state" message:@"任务状态异常"];
        return;
    }

    // 抓屏前隐藏自有覆盖层，并等待两帧，确保合成器不再包含 PixPin 窗口。
    [self pxHideOwnOverlays];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PXFramesToWaitBeforeCapture / 60.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (![self pxIsTaskCurrent:task]) return;
        [self.provider captureWithCompletion:^(UIImage *image, BOOL isPartial, NSString *captureMethod, NSError *error) {
            if (![self pxIsTaskCurrent:task] || task.state != PXCaptureStateCapturing) {
                return;   // 已取消/已被新任务取代
            }
            if (!image) {
                [self pxFailTask:task code:@"capture" message:(error.localizedDescription ?: @"屏幕抓取失败")];
                return;
            }
            task.baseImage = image;
            task.isPartialCapture = isPartial;
            if (isPartial) {
                PXLogWarn(@"capture fell back to partial snapshot path");
            }
            if (![task transitionToState:PXCaptureStateCaptured]) return;

            if (task.mode == PXCaptureModeMarkup) {
                if (isPartial) {
                    [self pxFailTask:task code:@"partial-capture" message:@"当前抓取接口无法取得完整屏幕，不能开始全屏标记"];
                    return;
                }
                task.resultImage = image;
                if (![task transitionToState:PXCaptureStatePresenting]) return;
                [self pxPresentEditorForTask:task];
            } else if (task.mode == PXCaptureModeLong) {
                if (isPartial) {
                    [self pxFailTask:task code:@"partial-capture" message:@"无法取得完整屏幕，不能开始滚动截图"];
                    return;
                }
                if (![task transitionToState:PXCaptureStatePresenting]) return;
                [self pxStartLongShotForTask:task mode:task.configSnapshot.longShotOptions.mode
                                displayRect:task.capturedScreenBounds];
            } else if (task.mode == PXCaptureModeFull) {
                [self pxHandleFullscreenResult:task];
            } else {
                [self pxPresentSelectionForTask:task];
            }
        }];
    });
}

- (void)pxHandleFullscreenResult:(PXCaptureTask *)task {
    task.resultImage = task.baseImage;
    if (![task transitionToState:PXCaptureStatePresenting]) return;
    PXOutputAction action = task.configSnapshot.defaultResultAction;
    [self pxExecuteOutput:action forTask:task presentingWindow:nil];
}

- (void)pxPresentSelectionForTask:(PXCaptureTask *)task {
    if (![task transitionToState:PXCaptureStatePresenting]) return;

    [self pxDestroyCaptureWindow];
    PXCaptureWindow *window = [PXCaptureWindow pxCaptureWindow];
    PXSelectionView *view = [[PXSelectionView alloc] initWithFrame:window.bounds
                                                         baseImage:task.baseImage
                                                              mode:task.mode
                                                          delegate:self];
    [self pxApplyRememberedSelectionRect:view task:task bounds:window.bounds];
    [window hostContentView:view];
    self.captureWindow = window;
    self.selectionView = view;
    // 选区窗口按约定成为 key（同编辑器路径）。跨进程触摸抢占另靠实时取景的低透明度底色：
    // key 不足以从 App 手里截触摸（v2.2.1 实测 App 内仍穿透），全透明区域会被窗口服务器跳过。
    [window showAnimated:(task.mode != PXCaptureModeInstant) becomeKey:YES];
    PXLogInfo(@"selection presented (mode %@, task %@)", PXStringFromCaptureMode(task.mode), task.taskID);
}

#pragma mark - 选区回调

- (void)selectionView:(PXSelectionView *)view
   didConfirmDisplayRect:(CGRect)displayRect
                 action:(PXOutputAction)action {
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
    if (!task || view != self.selectionView || !view.userInteractionEnabled) return;
    [self pxPersistSelectionRect:displayRect config:task.configSnapshot];
    [self pxCropAndOutput:task displayRect:displayRect overrideAction:action];
}

- (void)selectionViewDidCancel:(PXSelectionView *)view {
    // “记住上次选区”口径是上一次调整的结果：取消同样按当前选区落盘（开关关闭时内部清空）。
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
    if (task) {
        [self pxPersistSelectionRect:view.selectionRect config:task.configSnapshot];
    }
    [self pxCancelCurrentTaskClosingFloatingSnaps:NO];
}

- (void)selectionViewDidRequestFreeze:(PXSelectionView *)view {
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
    if (!task || task.mode != PXCaptureModeArea || task.areaFrameFrozen ||
        view != self.selectionView || !view.userInteractionEnabled) return;
    [self pxPrepareSelectionSourceForTask:task
             keepWindowHiddenAfterCapture:NO
                               completion:^(BOOL ready, NSError *error) {
        if (ready) {
            task.areaFrameFrozen = YES;
            [view applyFrozenImage:task.baseImage];
            PXLogInfo(@"selection freeze applied (task %@)", task.taskID);
        } else {
            [view showFreezeFailure];
            PXLogWarn(@"selection freeze failed (task %@ error=%ld)", task.taskID, (long)error.code);
        }
        view.userInteractionEnabled = YES;
    }];
}

- (void)selectionViewDidRequestFullscreenMarkup:(PXSelectionView *)view {
    // 无视当前框选：按取消口径收掉选区窗口（含“记住上次选区”落盘），
    // 再走全屏标记任务的常规入口重抓屏；悬浮图与「取消」同口径保留。
    [self selectionViewDidCancel:view];
    PXLogInfo(@"selection toolbar requested fullscreen markup");
    [self requestCapture:PXCaptureModeMarkup];
}

- (void)selectionView:(PXSelectionView *)view didRequestCustomURL:(NSURL *)url {
    // 自定义 URL 按钮：选区会话到此结束（不产出图片），再交给系统 URL 分发层。
    // openURL 的完成回调线程不确定，只记日志；打开失败时目标 App 未注册该 scheme。
    [self selectionViewDidCancel:view];
    PXLogInfo(@"selection toolbar custom url opened: %@", url.absoluteString);
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        PXLogInfo(@"custom url opened: %@ success=%d", url.absoluteString, success);
    }];
}

- (void)selectionViewDidRequestEditor:(PXSelectionView *)view displayRect:(CGRect)displayRect {
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
    if (!task || view != self.selectionView || !view.userInteractionEnabled) return;
    [self pxPersistSelectionRect:displayRect config:task.configSnapshot];
    [self pxCropInBackground:task displayRect:displayRect completion:^(UIImage *cropped) {
        if (![self pxIsTaskCurrent:task]) return;
        if (!cropped) {
            [self pxFailTask:task code:@"crop" message:@"选区裁剪失败"];
            return;
        }
        task.resultImage = cropped;
        [self pxDestroyCaptureWindow];
        [self pxPresentEditorForTask:task];
    }];
}

- (void)selectionViewDidRequestFloat:(PXSelectionView *)view displayRect:(CGRect)displayRect {
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
    if (!task || view != self.selectionView || !view.userInteractionEnabled) return;
    if (!view.window) return;
    CGRect screenRect = [view convertRect:displayRect toCoordinateSpace:view.window.screen.coordinateSpace];
    [self pxPersistSelectionRect:displayRect config:task.configSnapshot];
    [self pxCropInBackground:task displayRect:displayRect completion:^(UIImage *cropped) {
        if (![self pxIsTaskCurrent:task] || task.state != PXCaptureStatePresenting) return;
        if (!cropped) {
            [self pxFailTask:task code:@"crop" message:@"选区裁剪失败"];
            return;
        }
        task.resultImage = cropped;
        [self pxDestroyCaptureWindow];
        [self pxPresentFloatingSnapForTask:task screenRect:screenRect];
    }];
}

#pragma mark - 三模式长截图会话

- (void)pxStartLongShotForTask:(PXCaptureTask *)task mode:(PXLongShotMode)mode displayRect:(CGRect)displayRect {
    if (![self pxIsTaskCurrent:task] || task.state != PXCaptureStatePresenting) return;
    [self pxTeardownLongShotSession];
    [self pxDestroyCaptureWindow];
    self.longShotSession = [PXLongShotSession startWithTask:task
                                                     mode:mode
                                                 displayRect:displayRect
                                                   delegate:self];
    if (!self.longShotSession) {
        [self pxFailTask:task code:@"longshot" message:@"长截图会话创建失败"];
    }
}

// 选区工具栏与外部入口采用同一模式配置；选区同时限定采集裁片与短滑视口。
- (void)selectionViewDidRequestLong:(PXSelectionView *)view displayRect:(CGRect)displayRect {
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
    if (!task || task.areaFrameFrozen || view != self.selectionView || !view.userInteractionEnabled) return;
    [self pxPersistSelectionRect:displayRect config:task.configSnapshot];
    [self pxStartLongShotForTask:task mode:task.configSnapshot.longShotOptions.mode displayRect:displayRect];
}

/// 外部取消/失败路径的会话清理：会话自毁不回调，任务状态由调用方推进。
- (void)pxTeardownLongShotSession {
    if (!self.longShotSession) return;
    [self.longShotSession teardownForExternalCancel];
    self.longShotSession = nil;
}

- (void)longShotSessionDidFinish:(PXLongShotSession *)session resultImage:(UIImage *)image {
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
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
    PXOutputAction action = task.configSnapshot.defaultResultAction;
    // 巨型长图写入剪贴板会在 SpringBoard 内触发 PNG 编码尖峰，降级为保存（诊断优先）。
    if (pixelHeight > (CGFloat)PXLongShotCopyMaxPixelHeight &&
        (action == PXOutputActionCopy || action == PXOutputActionSaveAndCopy)) {
        PXLogWarn(@"long shot %.0f px exceeds copy limit, downgraded to save (task %@)",
                  pixelHeight, task.taskID);
        action = PXOutputActionSave;
    }
    [self pxExecuteOutput:action forTask:task presentingWindow:nil];
}

- (void)longShotSessionDidCancel:(PXLongShotSession *)session {
    if (self.longShotSession == session) self.longShotSession = nil;
    [self pxCancelCurrentTaskClosingFloatingSnaps:NO];
}

- (void)longShotSessionDidFail:(PXLongShotSession *)session message:(NSString *)message {
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
    if (self.longShotSession == session) self.longShotSession = nil;
    if (!task) return;
    [self pxFailTask:task code:@"longshot" message:(message ?: @"长图拼接失败")];
}

- (void)selectionViewDidRequestShellXAction:(PXSelectionView *)view action:(PXShellXAction)action {
    // SHELLX 收到信号后会重抓屏或弹全屏界面：先把本方选区窗口收掉，避免截进本方画板。
    // 悬浮图是用户主动常驻的内容，与「取消」同口径保留；关闭动作不涉及重抓屏，本方会话不动。
    if (action != PXShellXActionClose) {
        [self pxCancelCurrentTaskClosingFloatingSnaps:NO];
    }
    // 武装自发自收抑制：区域/即时/冻结/关闭的官方触发名与本方 SHELLX 兼容别名同名
    // （Darwin 中心把自发通知也投递回本进程），外调前按名武装一次，回环到达时吞掉，
    // 否则画板双开（PixPin 一块、SHELLX 一块）。记录/最近一张/整屏（AssistiveScreenshot
    // 通知）本方均未监听，无回环；套壳等 URL 类动作不经过通知中心，也无回环。
    switch (action) {
        case PXShellXActionArea:
        case PXShellXActionInstant:
        case PXShellXActionFreeze:
        case PXShellXActionClose:
            pxDarwinSelfPostArmedName = [PXShellXBridge notificationNameForAction:action];
            break;
        case PXShellXActionHistory:
        case PXShellXActionOpenLast:
        case PXShellXActionAssistive:
        case PXShellXActionLongShot:
        case PXShellXActionFullShot:
        case PXShellXActionMark:
        case PXShellXActionEdit:
        case PXShellXActionAI2:
        case PXShellXActionTranslate:
        case PXShellXActionScan:
            break;
    }
    [PXShellXBridge notifyAction:action];
}

#pragma mark - 选区记忆（AreaRememberLastRect，默认关）

/// 开关关闭时清掉历史矩形，避免下次打开开关先弹出一个陈旧选区。
- (void)pxPersistSelectionRect:(CGRect)rect config:(PXConfig *)config {
    id value = config.areaRememberLastRect ? (id)NSStringFromCGRect(rect) : (id)nil;
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeyAreaLastSelectionRect,
                             (__bridge CFTypeRef)value,
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

/// 上次选区只作初值：按当前窗口钳制，跨旋转/跨分辨率不合法时保持空选区（等用户手动框选）。
- (void)pxApplyRememberedSelectionRect:(PXSelectionView *)view
                                  task:(PXCaptureTask *)task
                                bounds:(CGRect)bounds {
    if (!task.configSnapshot.areaRememberLastRect) return;
    NSString *csv = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)PXKeyAreaLastSelectionRect,
        (__bridge CFStringRef)PXPreferencesDomain));
    if (csv.length == 0) return;
    CGRect saved = CGRectFromString(csv);
    if (CGRectIsEmpty(saved)) return;
    CGRect clamped = PXClampSelectionRect(saved, bounds.size, PXSelectionMinimumSize);
    if (CGRectIsEmpty(clamped)) return;
    [view applyDefaultSelectionRect:clamped];
}

- (void)pxCropAndOutput:(PXCaptureTask *)task
             displayRect:(CGRect)displayRect
          overrideAction:(PXOutputAction)overrideAction {
    [self pxCropInBackground:task displayRect:displayRect completion:^(UIImage *cropped) {
        if (![self pxIsTaskCurrent:task]) return;
        if (!cropped) {
            [self pxFailTask:task code:@"crop" message:@"选区裁剪失败"];
            return;
        }
        task.resultImage = cropped;
        [self pxDestroyCaptureWindow];
        PXOutputAction action = (overrideAction == PXOutputActionPreviewOnly)
            ? task.configSnapshot.defaultResultAction
            : overrideAction;
        [self pxExecuteOutput:action forTask:task presentingWindow:nil];
    }];
}

#pragma mark - 裁剪

/// 区域输出与手动冻结共用：排除选框窗口抓取当时画面，冻结后复用不可变底图。
/// keepWindowHiddenAfterCapture 为 YES（输出路径）时抓屏后窗口保持隐藏直到销毁，
/// 避免「恢复显示→归一化+裁剪期间暗罩重现→再销毁」的闪烁；NO（冻结路径）维持原行为。
- (void)pxPrepareSelectionSourceForTask:(PXCaptureTask *)task
           keepWindowHiddenAfterCapture:(BOOL)keepWindowHiddenAfterCapture
                             completion:(void (^)(BOOL ready, NSError *error))completion {
    NSParameterAssert(NSThread.isMainThread);
    PXSelectionView *view = self.selectionView;
    PXCaptureWindow *window = self.captureWindow;
    if (![self pxIsTaskCurrent:task] || task.state != PXCaptureStatePresenting ||
        !view || !view.userInteractionEnabled || !window || view.window != window ||
        self.selectionCaptureRequestID) return;
    view.userInteractionEnabled = NO;
    if (task.mode != PXCaptureModeArea || task.areaFrameFrozen) {
        completion(task.baseImage != nil, nil);
        return;
    }

    NSString *requestID = NSUUID.UUID.UUIDString;
    self.selectionCaptureRequestID = requestID;
    PXCaptureProvider *provider = [PXCaptureProvider new];
    provider.detachesCapturedImage = YES;  // 冻结图必须拥有独立位图，不能随源表面变化。
    provider.keepsExcludedWindowsHiddenAfterCapture = keepWindowHiddenAfterCapture;
    PXLogInfo(@"selection live capture began (task %@ request %@)", task.taskID, requestID);
    [provider captureExcludingWindows:@[window] completion:^(UIImage *image, BOOL isPartial,
                                                            NSString *captureMethod, NSError *error) {
        // 输出路径抓屏后窗口保持隐藏，不检查 window.hidden；窗口销毁路径已由
        // selectionCaptureRequestID 置空兜底，销毁或隐藏本身不构成放弃条件。
        if (![self.selectionCaptureRequestID isEqualToString:requestID] ||
            ![self pxIsTaskCurrent:task] || task.state != PXCaptureStatePresenting ||
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
            NSError *failure = error ?: [NSError errorWithDomain:PXCaptureErrorDomain
                code:geometryMatches ? PXCaptureErrorCaptureFailed : PXCaptureErrorUnexpectedGeometry
                userInfo:@{NSLocalizedDescriptionKey: geometryMatches
                    ? @"当前抓取接口无法取得完整屏幕" : @"屏幕尺寸已变化，请重新框选"}];
            PXLogWarn(@"selection live capture failed (task %@ partial=%d geometry=%d method=%@)",
                      task.taskID, isPartial, geometryMatches, captureMethod);
            completion(NO, failure);
            return;
        }
        task.baseImage = image;
        task.isPartialCapture = NO;
        PXLogInfo(@"selection live capture ready (task %@ method=%@)", task.taskID, captureMethod);
        completion(YES, nil);
    }];
}

- (void)pxCropInBackground:(PXCaptureTask *)task
                displayRect:(CGRect)displayRect
                 completion:(void (^)(UIImage *))completion {
    PXSelectionView *view = self.selectionView;
    [self pxPrepareSelectionSourceForTask:task
             keepWindowHiddenAfterCapture:YES
                               completion:^(BOOL ready, NSError *error) {
        if (!ready) { completion(nil); return; }
        // 实时抓屏已复查几何；冻结路径始终使用同一任务的固定几何和底图。
        UIImage *baseImage = task.baseImage;
        CGSize pixelSize = CGSizeMake(baseImage.size.width * baseImage.scale,
                                      baseImage.size.height * baseImage.scale);
        CGRect pixelRect = PXConvertDisplayRectToPixel(displayRect, task.capturedScreenBounds.size, pixelSize);
        if (CGRectIsEmpty(pixelRect)) { completion(nil); return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            UIImage *cropped = [self pxCropImage:baseImage pixelRect:pixelRect];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![self pxIsTaskCurrent:task] || task.state != PXCaptureStatePresenting ||
                    self.selectionView != view) return;
                completion(cropped);
            });
        });
    }];
}

- (UIImage *)pxCropImage:(UIImage *)image pixelRect:(CGRect)pixelRect {
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

- (void)pxExecuteOutput:(PXOutputAction)action
                 forTask:(PXCaptureTask *)task
        presentingWindow:(UIWindow *)presentingWindow {
    if (![task transitionToState:PXCaptureStateExporting]) {
        PXLogWarn(@"cannot output in state %@", PXStringFromCaptureState(task.state));
        return;
    }
    PXLogInfo(@"output requested (action %@, task %@)", PXStringFromOutputAction(action), task.taskID);
    [self.pipeline performAction:action
                          forTask:task
                presentingWindow:presentingWindow
                      completion:^(BOOL ok, NSString *message) {
        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self pxReportCompletion:task ok:ok message:message]; });
            return;
        }
        [self pxReportCompletion:task ok:ok message:message];
    }];
}

- (void)pxReportCompletion:(PXCaptureTask *)task ok:(BOOL)ok message:(NSString *)message {
    if (![self pxIsTaskCurrent:task]) return;
    PXLogInfo(@"output completed (ok=%d, task %@): %@", ok, task.taskID, message ?: @"");

    if (ok) {
        [task transitionToState:PXCaptureStateFinished];
        if (task.configSnapshot.screenshotHaptic) {
            UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [haptic impactOccurred];
        }
    } else {
        // 输出失败：保留临时文件供诊断，失败原因在气泡中显示（重新截图重试）。
        [task transitionToState:PXCaptureStateFailed];
        [task unclaimOutputAction:PXOutputActionSave];
        [task unclaimOutputAction:PXOutputActionCopy];
        [task unclaimOutputAction:PXOutputActionShare];
        PXLogWarn(@"output failed, temp files kept for retry (task %@)", task.taskID);
    }

    if (task.configSnapshot.showResultBubble) {
        // 先同步弹出气泡（即时反馈，也消除“待弹泡窗口期被新截图截入”的竞态），
        // 缩略图后台渲染后回填（P1-4：大图解码不占主线程）。
        CGFloat screenScale = [UIScreen mainScreen].scale;
        UIImage *resultImage = task.resultImage;
        // 长图优先从落盘产物降采样（受限解码，不为 88pt 小图整幅解出 8MP 位图，
        // 两次长截图之间不给 SpringBoard 抬基线）；无落盘文件时回退内存解码。
        NSString *thumbnailPath = task.resultFilePath;
        self.resultBubble = [PXResultBubble presentWithImage:nil
                                                     message:(message ?: @"截图完成")
                                                        task:task
                                                   succeeded:ok
                                                    delegate:self];
        PXResultBubble *bubble = self.resultBubble;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                UIImage *thumbnail = thumbnailPath.length
                    ? [PXLongImageComposer thumbnailImageFromFile:thumbnailPath screenScale:screenScale
                                                     maxPixelSize:88.0 * MAX(2.0, screenScale)]
                    : nil;
                if (!thumbnail) thumbnail = [self pxThumbnailForImage:resultImage screenScale:screenScale];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [bubble updateThumbnailImage:thumbnail];
                });
                // 缩略图已独立于源文件，输出成功后再回收任务临时目录（失败路径保留）。
                if (ok) [PXTemporaryFileStore removeTaskDirectory:task.taskID];
            }
        });
    } else if (ok) {
        // 输出成功不再需要重试，任务临时目录立即回收（失败路径保留供诊断）。
        [PXTemporaryFileStore removeTaskDirectory:task.taskID];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:PXNotificationResultUpdated object:nil];
    [self pxClearSlotIfCurrent:task];
    // 悬浮窗随任务结束恢复展示（抓屏前被 pxHideOwnOverlays 暂时隐藏）。
    self.editingFloatingSnap = nil;
    [self pxRestoreFloatingSnaps];
}

#pragma mark - 悬浮窗

- (void)pxRestoreFloatingSnaps {
    for (PXFloatingSnap *snap in self.floatingSnaps) [snap restoreAfterCapture];
}

/// 窗口成功创建后才报告成功，保留其他悬浮图并释放当前任务槽。
- (void)pxPresentFloatingSnapForTask:(PXCaptureTask *)task screenRect:(CGRect)screenRect {
    if (![self pxIsTaskCurrent:task] || ![task transitionToState:PXCaptureStateExporting]) return;
    PXFloatingSnap *snap = [PXFloatingSnap presentWithImage:task.resultImage mode:task.mode
                                                 delegate:self screenRect:screenRect
                                                    shadow:task.configSnapshot.floatingSnapShadow];
    if (!snap) {
        [self pxFailTask:task code:@"floating-window" message:@"悬浮图片显示失败"];
        return;
    }
    [self.floatingSnaps addObject:snap];
    [task transitionToState:PXCaptureStateFinished];
    [PXTemporaryFileStore removeTaskDirectory:task.taskID];
    [self pxClearSlotIfCurrent:task];
    [self pxRestoreFloatingSnaps];
    if (task.configSnapshot.screenshotHaptic) {
        UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [haptic impactOccurred];
    }
    PXLogInfo(@"floating snap added (count %lu)", (unsigned long)self.floatingSnaps.count);
}

- (void)floatingSnapDidRequestEdit:(PXFloatingSnap *)snap {
    if (![self.floatingSnaps containsObject:snap]) return;
    UIImage *image = snap.image;
    PXCaptureMode mode = snap.captureMode;
    // 先占任务槽再隐藏当前图；取消编辑时原图恢复，其他悬浮不受影响。
    PXCaptureTask *task = [self pxAcquireTaskForMode:mode config:PXPreferences.config];
    if (!task) {
        PXLogWarn(@"float re-edit ignored: another task is busy");
        self.resultBubble = [PXResultBubble presentWithImage:nil
                                                     message:@"当前有任务进行中，请稍后重试"
                                                        task:nil
                                                   succeeded:NO
                                                    delegate:self];
        return;
    }
    task.isReedit = YES;
    self.editingFloatingSnap = snap;
    [snap hideForCapture];
    [self pxBeginEditorForAcquiredTask:task image:image];
}

- (void)floatingSnapDidRequestOutput:(PXFloatingSnap *)snap action:(PXOutputAction)action {
    if (![self.floatingSnaps containsObject:snap]) return;
    UIImage *image = snap.image;
    PXCaptureMode mode = snap.captureMode;
    PXConfig *config = PXPreferences.config;
    PXCaptureTask *task = [self pxAcquireTaskForMode:mode config:config];
    if (!task) {
        PXLogWarn(@"float output ignored: another task is busy");
        self.resultBubble = [PXResultBubble presentWithImage:nil
                                                     message:@"当前有任务进行中，请稍后重试"
                                                        task:nil
                                                   succeeded:NO
                                                    delegate:self];
        return;
    }
    task.baseImage = image;
    task.resultImage = image;
    [task transitionToState:PXCaptureStateCapturing];
    [task transitionToState:PXCaptureStateCaptured];
    [self pxExecuteOutput:action forTask:task presentingWindow:nil];
}

- (void)floatingSnapDidClose:(PXFloatingSnap *)snap {
    [self.floatingSnaps removeObjectIdenticalTo:snap];
    if (self.editingFloatingSnap == snap) self.editingFloatingSnap = nil;
    PXLogInfo(@"floating snap removed (count %lu)", (unsigned long)self.floatingSnaps.count);
}

#pragma mark - 编辑器

- (void)pxPresentEditorForTask:(PXCaptureTask *)task {
    if (!task.resultImage) {
        [self pxFailTask:task code:@"editor" message:@"没有可编辑的结果"];
        return;
    }
    if (![task transitionToState:PXCaptureStateEditing]) {
        PXLogWarn(@"cannot enter editing in state %@", PXStringFromCaptureState(task.state));
        return;
    }

    // 取消编辑时恢复到进入编辑器前的结果（不是 baseImage 整屏快照）。
    self.preEditImage = task.resultImage;

    CGSize px = CGSizeMake(task.resultImage.size.width * task.resultImage.scale,
                           task.resultImage.size.height * task.resultImage.scale);
    PXLogInfo(@"editor present (mode %@, image %.0fx%.0f px, task %@)",
              PXStringFromCaptureMode(task.mode), px.width, px.height, task.taskID);

    [self pxDestroyEditorWindow];
    PXEditorViewController *editor = [[PXEditorViewController alloc] initWithImage:task.resultImage delegate:self];
    editor.fullscreenMarkup = (task.mode == PXCaptureModeMarkup);
    editor.backdropImage = task.baseImage;
    PXCaptureWindow *window = [PXCaptureWindow pxCaptureWindow];
    window.rootViewController = editor;
    self.editorWindow = window;
    self.editorController = editor;
    [window showAnimated:NO];
    PXLogInfo(@"editor visible (mode %@, task %@)", PXStringFromCaptureMode(task.mode), task.taskID);
}

/// 气泡重编辑入口：以新任务进入编辑器。
- (void)openEditorWithImage:(UIImage *)image mode:(PXCaptureMode)mode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openEditorWithImage:image mode:mode]; });
        return;
    }
    PXConfig *config = PXPreferences.config;
    PXCaptureTask *task = [self pxAcquireTaskForMode:mode config:config];
    if (!task) {
        PXLogWarn(@"re-edit ignored: another task is busy");
        return;
    }
    task.isReedit = YES;
    [self pxBeginEditorForAcquiredTask:task image:image];
}

/// 任务槽已由调用方占好的编辑器进入路径。
- (void)pxBeginEditorForAcquiredTask:(PXCaptureTask *)task image:(UIImage *)image {
    task.baseImage = image;
    task.resultImage = image;
    [task transitionToState:PXCaptureStateCapturing];
    [task transitionToState:PXCaptureStateCaptured];
    [task transitionToState:PXCaptureStatePresenting];
    [self pxPresentEditorForTask:task];
}

- (void)editorController:(PXEditorViewController *)controller didFinishWithImage:(UIImage *)image action:(PXOutputAction)action {
    if (controller != self.editorController) return;
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStateEditing];
    [self pxDestroyEditorWindow];
    self.preEditImage = nil;
    if (!task) return;

    task.resultImage = image;
    [self.editingFloatingSnap updateImage:image];
    if (![task transitionToState:PXCaptureStatePresenting]) return;
    PXOutputAction output = (action == PXOutputActionPreviewOnly) ? task.configSnapshot.defaultResultAction : action;
    [self pxExecuteOutput:output forTask:task presentingWindow:nil];
}

- (void)editorControllerDidCancel:(PXEditorViewController *)controller {
    if (controller != self.editorController) return;
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStateEditing];
    [self pxDestroyEditorWindow];
    if (!task) return;

    // 取消编辑并恢复进入编辑器前的结果（原图未被破坏，DEVELOPMENT.md 5.6）。
    if (self.preEditImage) {
        task.resultImage = self.preEditImage;
    }
    self.preEditImage = nil;
    if (![task transitionToState:PXCaptureStatePresenting]) return;

    // 关闭/取消一律终止任务：不产出、不弹结果气泡。旧实现在此处对非重编辑
    // 任务补发 defaultResultAction，SaveAlsoCopy 默认开后变成「取消仍保存+复制」。
    [self pxCancelCurrentTaskClosingFloatingSnaps:NO];
}

- (void)pxDestroyEditorWindow {
    if (self.editorController) {
        // 先断开控制器内的手势引用环，再摘视图、清引用（顺序不可换）。
        [self.editorController prepareForDismissal];
        [self.editorController.view removeFromSuperview];
        self.editorController = nil;
    }
    if (self.editorWindow) {
        PXCaptureWindow *window = self.editorWindow;
        self.editorWindow = nil;
        [window hideAndDestroyWithCompletion:nil];
    }
}

#pragma mark - 气泡回调

/// 点气泡主体（气泡只有缩略图/文案区）：按本次输出动作分流。
/// 保存类（保存 / 保存并复制）→ 进相册最近照片；纯复制 → 关闭气泡；
/// 其余动作进编辑器；失败气泡不响应。
- (void)resultBubbleDidTapBody:(PXResultBubble *)bubble {
    PXCaptureTask *task = bubble.task;
    if (!task || [task currentState] != PXCaptureStateFinished) return;
    if ([task isOutputActionClaimed:PXOutputActionSave]) {
        // 保存并复制同时认领两个动作，按保存类处理。
        PXLogInfo(@"result bubble tap -> photos recents (task %@)", task.taskID);
        [PXPhotoShortcut openMostRecentPhoto];
        [bubble dismissWithCompletion:nil];
        return;
    }
    if ([task isOutputActionClaimed:PXOutputActionCopy]) {
        PXLogInfo(@"result bubble tap -> dismiss (copy action, task %@)", task.taskID);
        [bubble dismissWithCompletion:nil];
        return;
    }
    UIImage *image = task.resultImage ?: task.baseImage;
    if (!image) return;
    [bubble dismissWithCompletion:nil];
    [self openEditorWithImage:image mode:task.mode];
}

- (void)resultBubbleDidDismiss:(PXResultBubble *)bubble {
    // 只清理仍指向该气泡的引用，避免误清新气泡（交叠窗口极短但存在）。
    if (self.resultBubble == bubble) {
        self.resultBubble = nil;
    }
}

#pragma mark - 异常与辅助

- (void)pxOrientationDidChange:(NSNotification *)notification {
    // 选区期间旋转：基础快照与屏幕几何错位，直接取消。
    if (self.selectionView) {
        PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
        if (task && task.mode != PXCaptureModeFull) {
            PXLogWarn(@"orientation changed during selection, cancelling task");
            [self pxCancelCurrentTaskClosingFloatingSnaps:NO];
        }
        return;
    }
    // 长截图会话中旋转：采集屏幕坐标失效，同样直接取消。
    if (self.longShotSession) {
        PXLogWarn(@"orientation changed during long shot, cancelling task");
        [self pxCancelCurrentTaskClosingFloatingSnaps:NO];
    }
}

- (void)pxFailTask:(PXCaptureTask *)task code:(NSString *)code message:(NSString *)message {
    task.errorCode = code;
    task.errorMessage = message;
    [self pxTeardownLongShotSession];
    [self pxDestroyCaptureWindow];
    [task transitionToState:PXCaptureStateFailed];
    [PXTemporaryFileStore removeTaskDirectory:task.taskID];
    PXLogError(@"task failed [%@]: %@", code, message);
    // 失败气泡不受 ShowResultBubble 控制：失败原因必须可见（诊断优先）。
    self.resultBubble = [PXResultBubble presentWithImage:nil
                                                 message:message
                                                    task:nil
                                               succeeded:NO
                                                delegate:self];
    [self pxClearSlotIfCurrent:task];
    self.editingFloatingSnap = nil;
    [self pxRestoreFloatingSnaps];
}

- (void)pxHideOwnOverlays {
    if (self.resultBubble) {
        [self.resultBubble dismissWithCompletion:nil];
    }
    // 悬浮窗是新任务的抓屏对象之一：抓屏前隐藏，任务收尾再恢复。
    for (PXFloatingSnap *snap in self.floatingSnaps) [snap hideForCapture];
}

- (void)pxDestroyCaptureWindow {
    self.selectionCaptureRequestID = nil;
    if (self.selectionView) {
        [self.selectionView prepareForDismissal];
        self.selectionView = nil;
    }
    if (self.captureWindow) {
        PXCaptureWindow *window = self.captureWindow;
        self.captureWindow = nil;
        [window hideAndDestroyWithCompletion:nil];
    }
}

- (UIImage *)pxThumbnailForImage:(UIImage *)image screenScale:(CGFloat)screenScale {
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

- (PXCaptureTask *)pxAcquireTaskForMode:(PXCaptureMode)mode config:(PXConfig *)config {
    [self.taskLock lock];
    PXCaptureTask *task = nil;
    if (!self.activeTask || !PXCaptureStateIsBusy(self.activeTask.state)) {
        task = [[PXCaptureTask alloc] initWithMode:mode
                                             config:config
                                       screenBounds:[UIScreen mainScreen].bounds
                                        screenScale:[UIScreen mainScreen].scale];
        [task transitionToState:PXCaptureStatePreparing];
        self.activeTask = task;
    }
    [self.taskLock unlock];
    return task;
}

- (PXCaptureTask *)pxCurrentTask {
    [self.taskLock lock];
    PXCaptureTask *task = self.activeTask;
    [self.taskLock unlock];
    return task;
}

- (PXCaptureTask *)pxCurrentTaskIfState:(PXCaptureState)state {
    [self.taskLock lock];
    PXCaptureTask *task = self.activeTask;
    BOOL match = (task && task.state == state);
    [self.taskLock unlock];
    return match ? task : nil;
}

- (BOOL)pxIsTaskCurrent:(PXCaptureTask *)task {
    [self.taskLock lock];
    BOOL current = (self.activeTask == task);
    [self.taskLock unlock];
    return current;
}

- (void)pxClearSlotIfCurrent:(PXCaptureTask *)task {
    [self.taskLock lock];
    if (self.activeTask == task) {
        self.activeTask = nil;
    }
    [self.taskLock unlock];
}

@end
