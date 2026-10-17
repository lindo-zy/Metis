#import "MTLongShotSession.h"
#import "MTCaptureTask.h"
#import "MTCaptureProvider.h"
#import "MTLongShotScroller.h"
#import "MTLongShotTarget.h"
#import "MTLongShotFrameStore.h"
#import "../Common/MTCaptureLog.h"
#import "../Output/MTTemporaryFileStore.h"
#import "../Overlay/MTCaptureWindow.h"
#import "../Overlay/MTLongShotHUD.h"
#import <QuartzCore/QuartzCore.h>
#import <stdatomic.h>

// 一个阶段只有一个在途操作。running 表示用户是否要求继续，finishRequested 优先于 running。
typedef NS_ENUM(NSInteger, MTLongShotPhase) {
    MTLongShotPhaseReady, MTLongShotPhaseCapturing, MTLongShotPhaseProcessing,
    MTLongShotPhaseScrolling, MTLongShotPhaseSettling, MTLongShotPhaseExporting, MTLongShotPhaseFinished
};
static dispatch_queue_t MTLongShotImageQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.lindo.metis.capture.longshot.frames", DISPATCH_QUEUE_SERIAL); });
    return queue;
}
@interface MTLongShotSession () <MTLongShotHUDDelegate>
@property (nonatomic, strong) MTCaptureTask *task;
@property (nonatomic, copy) NSString *taskID;
@property (nonatomic, weak) id<MTLongShotSessionDelegate> delegate;
@property (nonatomic, copy) NSString *target;
@property (nonatomic, strong) MTCaptureProvider *provider;
@property (nonatomic, strong) MTLongShotScroller *scroller;
@property (nonatomic, strong) MTLongShotCancellation *cancellation;
@property (nonatomic, strong) MTLongShotFrameStore *store;
@property (nonatomic, strong) MTCaptureWindow *window;
@property (nonatomic, strong) MTLongShotHUD *hud;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) id memoryObserver;
@property (nonatomic) MTLongShotMode mode;
@property (nonatomic) MTLongShotPhase phase;
@property (nonatomic) CGRect displayRect;
@property (nonatomic) MTLongShotScrollPlan plan;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSInteger count;
@property (nonatomic) NSInteger duplicates;
@property (nonatomic) NSInteger uncertain;
@property (nonatomic) BOOL running;
@property (nonatomic) BOOL finishRequested;
@property (nonatomic) BOOL terminalPause;
@property (nonatomic) BOOL memoryStopped;
@property (nonatomic) BOOL previewDisabled;
@property (nonatomic) CFTimeInterval nextSample;
- (void)mtCancel;
@end
static __weak MTLongShotSession *MTLockSession;
static atomic_uint_fast64_t MTLockGeneration;
static CFStringRef MTLockName = CFSTR("com.apple.springboard.lockstate");
static void MTLockCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                           const void *object, CFDictionaryRef userInfo) {
    uint_fast64_t generation = atomic_load(&MTLockGeneration);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == atomic_load(&MTLockGeneration)) [MTLockSession mtCancel];
    });
}
// 会话收尾后的进程内存回收观测：0/5/30/60 秒各记一行 footprint/available（仅 syslog）。
// dispatch_after 只捕获 taskID 字符串与代数，不持有会话，观测自身不延长任务生命周期。
static void MTLongShotLogEndMemory(NSString *taskID, NSUInteger generation, NSInteger seconds) {
    MTCaptureLogInfo(@"long shot end memory (task %@ gen=%lu t=%lds footprint=%llu available=%llu)",
              taskID, (unsigned long)generation, (long)seconds,
              (unsigned long long)MTLongShotProcessFootprintBytes(),
              (unsigned long long)MTLongShotAvailableMemoryBytes());
}

static void MTLongShotScheduleEndMemoryLogs(NSString *taskID, NSUInteger generation) {
    static const NSInteger MTEndMemoryDelays[] = {0, 5, 30, 60};
    for (NSUInteger i = 0; i < sizeof(MTEndMemoryDelays) / sizeof(MTEndMemoryDelays[0]); i++) {
        NSInteger delay = MTEndMemoryDelays[i];
        NSString *capturedTaskID = [taskID copy];
        if (delay == 0) {
            MTLongShotLogEndMemory(capturedTaskID, generation, delay);
            continue;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            MTLongShotLogEndMemory(capturedTaskID, generation, delay);
        });
    }
}
@implementation MTLongShotSession
+ (instancetype)startWithTask:(MTCaptureTask *)task mode:(MTLongShotMode)mode
                  displayRect:(CGRect)displayRect delegate:(id<MTLongShotSessionDelegate>)delegate {
    NSParameterAssert(NSThread.isMainThread);
    MTLongShotSession *s = [self new];
    s.task = task; s.taskID = task.taskID; s.delegate = delegate; s.mode = mode;
    s.displayRect = displayRect; s.phase = MTLongShotPhaseReady;
    s.target = MTLongShotFrontmostIdentifier(UIApplication.sharedApplication);
    s.provider = [MTCaptureProvider new]; s.provider.detachesCapturedImage = YES;
    s.provider.keepsExcludedWindowsVisible = YES;
    s.cancellation = [MTLongShotCancellation new];
    // 打开框选时的画面可能已过时；只有用户点截取时才建立第一帧。
    task.baseImage = nil;
    s.window = [MTCaptureWindow mtCaptureWindow];
    UIEdgeInsets safe = s.window.windowScene.keyWindow.safeAreaInsets;
    CGRect screen = task.capturedScreenBounds;
    CGFloat width = MTLongShotHUDPreviewWidthPt + 24;
    CGFloat height = MIN(278, screen.size.height - safe.top - safe.bottom - 20);
    s.window.frame = CGRectMake(CGRectGetMaxX(screen) - safe.right - width - 12,
                                CGRectGetMinY(screen) + safe.top + 10, width, height);
    s.window.windowLevel = UIWindowLevelStatusBar;
    s.window.passesTouchesOutsideHostedContent = YES;
    s.hud = [[MTLongShotHUD alloc] initWithFrame:s.window.bounds]; s.hud.delegate = s;
    [s.window hostContentView:s.hud];
    s.window.rootViewController.view.frame = s.window.bounds; s.hud.frame = s.window.bounds;
    [s.hud setModeTitle:mode == MTLongShotModeAutomatic ? @"自动拼接" :
                        mode == MTLongShotModeSmart ? @"智能拼接" : @"采样拼接"];
    [s.window showAnimated:NO becomeKey:NO];
    [s mtShowReady:@"点「截取」开始"];
    atomic_fetch_add(&MTLockGeneration, 1); MTLockSession = s;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MTLockCallback,
                                    MTLockName, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    __weak MTLongShotSession *weak = s;
    s.memoryObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weak mtMemoryWarning]; }];
    s.timer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) { [weak mtTick]; }];
    [NSRunLoop.mainRunLoop addTimer:s.timer forMode:NSRunLoopCommonModes];
    MTCaptureLogInfo(@"long shot ready (task %@ mode=%ld rect=%@)", s.taskID, (long)mode, NSStringFromCGRect(displayRect));
    return s;
}
- (BOOL)isFinished { return self.phase == MTLongShotPhaseFinished; }
- (BOOL)mtLive {
    return !self.isFinished && !self.cancellation.cancelled && self.task.currentState == MTCaptureStatePresenting &&
           [self.taskID isEqual:self.task.taskID];
}
- (BOOL)mtTargetCurrent {
    return MTLongShotTargetIsCurrent(UIApplication.sharedApplication, MTLongShotLockManager(), self.target);
}
- (void)mtSetPhase:(MTLongShotPhase)phase {
    self.phase = phase;
    BOOL active = self.running && self.mode != MTLongShotModeSmart;
    BOOL enabled = !self.finishRequested && !self.terminalPause && !self.memoryStopped &&
                   (phase == MTLongShotPhaseReady || active);
    NSString *title = active ? @"暂停" : (self.count && self.mode != MTLongShotModeSmart ? @"继续" : @"截取");
    [self.hud setCaptureTitle:title enabled:enabled];
    [self.hud setFinishing:self.finishRequested || phase == MTLongShotPhaseExporting];
}
- (void)mtShowReady:(NSString *)message {
    [self mtSetPhase:MTLongShotPhaseReady]; self.hud.statusText = message;
}
- (void)mtTick {
    if (![self mtLive] || self.phase == MTLongShotPhaseExporting) return;
    if (![self mtTargetCurrent]) {
        if (!self.terminalPause) [self mtStop:@"前台 App 已变化\n点完成保存" terminal:YES];
        return;
    }
    if (self.running && self.mode == MTLongShotModeAutomatic && self.hud.isPreviewInteracting) {
        self.running = NO;
        [self mtSetPhase:self.phase]; self.hud.statusText = @"预览时暂停\n点继续恢复";
    }
    if (self.running && self.phase == MTLongShotPhaseReady && self.mode == MTLongShotModeSampling &&
        CACurrentMediaTime() >= self.nextSample && !self.hud.isPreviewInteracting) [self mtCapture];
}
- (void)longShotHUDDidTapCapture:(UIView *)hud {
    if (![self mtLive] || self.finishRequested || self.terminalPause || self.memoryStopped) return;
    if (self.running && self.mode != MTLongShotModeSmart) {
        self.running = NO;
        // 在途帧完成后停；不强行取消写盘或中途抬指导致漏段。
        [self mtSetPhase:self.phase]; self.hud.statusText = @"已暂停\n点继续或完成";
        return;
    }
    if (self.phase != MTLongShotPhaseReady) return;
    if (![self mtTargetCurrent]) { [self mtStop:@"请返回原 App\n点完成保存" terminal:YES]; return; }
    if (self.mode != MTLongShotModeSampling && !self.scroller) {
        self.scroller = [MTLongShotScroller new];
        if (self.scroller.availabilityError || !MTLongShotBuildScrollPlan(self.displayRect,
                self.task.capturedScreenBounds, self.window.frame, &_plan)) {
            [self mtStop:self.scroller.availabilityError ?: @"选区无法短滑\n请扩大正文区域" terminal:YES]; return;
        }
    }
    self.running = YES; self.duplicates = self.uncertain = 0;
    [self mtCapture];
}
- (void)mtStop:(NSString *)message terminal:(BOOL)terminal {
    if (![self mtLive] || self.phase == MTLongShotPhaseExporting) return;
    self.running = NO; self.terminalPause |= terminal;
    [self mtSetPhase:self.phase]; self.hud.statusText = message;
    MTCaptureLogWarn(@"long shot paused (task %@ phase=%ld count=%ld terminal=%d): %@",
              self.taskID, (long)self.phase, (long)self.count, terminal, message);
    if (self.finishRequested && self.phase == MTLongShotPhaseReady) [self mtExport];
}
- (BOOL)mtHasMemory {
    size_t available = MTLongShotAvailableMemoryBytes();
    return !available || available >= MTLongShotMemoryFloorBytes();
}
- (void)mtMemoryWarning {
    if (![self mtLive]) return;
    self.previewDisabled = YES; [self.hud setPreviewImage:nil usedPixelHeight:0];
    MTLongShotFrameStore *store = self.store;
    dispatch_async(MTLongShotImageQueue(), ^{ [store discardPreview]; });
    if (self.phase == MTLongShotPhaseExporting) return;
    // 不在资源不足时重抓末帧；已有内容由正在执行的操作释放后导出。
    // 可见浮窗不能回退到普通整屏抓取；内存警告时停止新快照，收尾已有帧。
    [self mtFinishForMemory];
}
- (void)mtFinishForMemory {
    self.memoryStopped = YES; self.finishRequested = YES; self.running = NO;
    [self mtSetPhase:self.phase]; self.hud.statusText = @"内存紧张\n保存已截内容";
    if (self.phase == MTLongShotPhaseReady) [self mtExport];
}
- (void)mtCapture {
    if (![self mtLive] || self.phase != MTLongShotPhaseReady) return;
    if (self.memoryStopped || self.terminalPause) { if (self.finishRequested) [self mtExport]; return; }
    if (![self mtTargetCurrent]) { [self mtStop:@"前台 App 已变化\n点完成保存" terminal:YES]; return; }
    if (![self mtHasMemory]) { [self mtFinishForMemory]; return; }
    if (!self.store) {
        NSString *directory = [self.task ensureTemporaryDirectory];
        if (!directory.length) { [self mtFail:@"临时目录创建失败"]; return; }
        self.store = [[MTLongShotFrameStore alloc] initWithDirectory:directory options:self.task.configSnapshot.longShotOptions
                                                    cancellation:self.cancellation scale:self.task.capturedScreenScale];
    }
    [self mtSetPhase:MTLongShotPhaseCapturing]; self.hud.statusText = @"正在截取当前段";
    NSUInteger token = ++self.generation;
    __weak MTLongShotSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MTLongShotSession *s = weak;
        if (![s mtLive] || s.generation != token || s.phase != MTLongShotPhaseCapturing) return;
        s.generation++; // 迟到的抓屏结果不可恢复会话，更不能启动第二次抓屏。
        [s mtSetPhase:MTLongShotPhaseReady];
        [s mtStop:@"抓屏超时\n点完成保存" terminal:YES];
    });
    @try {
        [self.provider captureExcludingWindows:@[self.window] completion:^(UIImage *image, BOOL partial, NSString *method, NSError *error) {
            MTLongShotSession *s = weak;
            if (![s mtLive] || s.generation != token || s.phase != MTLongShotPhaseCapturing) return;
            if (!image || partial || ![s mtTargetCurrent]) {
                [s mtSetPhase:MTLongShotPhaseReady];
                [s mtStop:(!image || partial) ? (error.localizedDescription ?: @"抓屏失败\n点完成保存") :
                          @"前台 App 已变化\n点完成保存" terminal:YES];
                return;
            }
            MTCaptureLogInfo(@"long shot capture (task %@ method=%@ generation=%lu)", s.taskID, method, (unsigned long)token);
            [s mtProcess:image token:token];
        }];
    } @catch (__unused NSException *exception) {
        [self mtSetPhase:MTLongShotPhaseReady]; [self mtStop:@"抓屏接口异常\n点完成保存" terminal:YES];
    }
}
- (void)mtProcess:(UIImage *)image token:(NSUInteger)token {
    [self mtSetPhase:MTLongShotPhaseProcessing];
    CGRect rect = MTConvertDisplayRectToPixel(self.displayRect, self.task.capturedScreenBounds.size,
                        CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage)));
    MTLongShotFrameStore *store = self.store;
    __weak MTLongShotSession *weak = self;
    dispatch_async(MTLongShotImageQueue(), ^{
        __block MTLongShotFrameResult *result;
        __block NSError *error;
        @autoreleasepool { result = [store consumeImage:image pixelRect:rect error:&error]; }
        // 下一块作为释放屏障，当前块持有的抓屏对象先离开队列，才采样余量/进入下一步。
        dispatch_async(MTLongShotImageQueue(), ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                MTLongShotSession *s = weak;
                if (![s mtLive] || s.generation != token) return;
                [s mtSetPhase:MTLongShotPhaseReady];
                if (!result) { [s mtStop:error.localizedDescription ?: @"帧处理失败" terminal:YES]; return; }
                s.count = result.count;
                [s.hud setSliceCount:s.count];
                if (result.previewUnavailable) {
                    s.previewDisabled = YES; [s.hud setPreviewImage:nil usedPixelHeight:0];
                }
                if (result.preview && !s.previewDisabled) [s.hud setPreviewImage:result.preview
                                           usedPixelHeight:CGImageGetHeight(result.preview.CGImage)];
                MTCaptureLogInfo(@"long shot frame (task %@ mode=%ld kind=%ld count=%ld shift=%ld fixed=%ld/%ld footprint=%llu available=%llu)",
                    s.taskID, (long)s.mode, (long)result.match.kind, (long)s.count, (long)result.match.shiftRows,
                    (long)result.match.fixedTopRows, (long)result.match.fixedBottomRows,
                    (unsigned long long)MTLongShotProcessFootprintBytes(), (unsigned long long)MTLongShotAvailableMemoryBytes());
                [s mtAcceptResult:result];
            });
        });
    });
}
- (void)mtAcceptResult:(MTLongShotFrameResult *)result {
    MTLongShotMatchKind kind = result.match.kind;
    if (self.finishRequested || self.count >= self.task.configSnapshot.longShotOptions.maxSlices) {
        if (self.finishRequested && !self.memoryStopped &&
            (kind == MTLongShotMatchUncertain || kind == MTLongShotMatchReverse)) {
            // 不能把末段丢失伪装成完整成功。用户再次点完成才输出已可靠拼接的部分。
            self.finishRequested = NO;
            [self mtStop:@"末段未拼上\n再点完成存已截" terminal:YES];
            return;
        }
        [self mtExport]; return;
    }
    if (![self mtHasMemory]) { [self mtFinishForMemory]; return; }
    if (self.terminalPause || !self.running) {
        [self mtShowReady:self.terminalPause ? @"采集已停止\n点完成保存" : @"已暂停\n点继续或完成"]; return;
    }
    if (kind == MTLongShotMatchUncertain) {
        self.uncertain++;
        // 自动/智能只允许原地静置重采一次，绝不再前滚或盲目反向回滚。
        if (self.uncertain < 2 && self.mode != MTLongShotModeSampling) { [self mtSettleThenCapture:YES]; return; }
        if (self.mode == MTLongShotModeSampling && self.uncertain < 3) {
            self.nextSample = CACurrentMediaTime() + self.task.configSnapshot.longShotOptions.idleInterval; return;
        }
        [self mtStop:@"未找到可靠重叠\n稍回滑后点截取" terminal:NO]; return;
    }
    self.uncertain = 0;
    if (kind == MTLongShotMatchReverse) {
        [self mtStop:@"画面发生回退\n恢复位置后继续" terminal:NO]; return;
    }
    self.duplicates = kind == MTLongShotMatchDuplicate ? self.duplicates + 1 : 0;
    if (self.mode == MTLongShotModeAutomatic && self.duplicates >= 2) {
        // 至少已有一次可靠推进，再经过两次完整短滑/静置仍无新增内容才自动保存。
        // 从一开始就不滚的页面仍提示检查，不能假报到底。
        if (self.count > 1) {
            MTCaptureLogInfo(@"long shot auto finish (task %@ reason=no-progress count=%ld duplicates=%ld)",
                      self.taskID, (long)self.count, (long)self.duplicates);
            [self mtExport];
        } else [self mtStop:@"页面未滚动\n点完成或继续" terminal:NO];
        return;
    }
    if (self.mode == MTLongShotModeSampling) {
        self.nextSample = CACurrentMediaTime() + (self.duplicates ? self.task.configSnapshot.longShotOptions.idleInterval :
                                                                 self.task.configSnapshot.longShotOptions.sampleInterval);
        self.hud.statusText = @"请缓慢上滑页面\n点完成结束"; return;
    }
    [self mtScroll];
}
- (void)mtScroll {
    if (![self mtLive] || !self.running || self.phase != MTLongShotPhaseReady || self.finishRequested) return;
    if (![self mtTargetCurrent]) { [self mtStop:@"前台 App 已变化\n点完成保存" terminal:YES]; return; }
    [self mtSetPhase:MTLongShotPhaseScrolling]; self.hud.statusText = @"短滑到下一段";
    NSUInteger token = self.generation;
    __weak MTLongShotSession *weak = self;
    [self.scroller scrollWithPlan:self.plan duration:self.task.configSnapshot.longShotOptions.scrollDuration completion:^(BOOL completed) {
        MTLongShotSession *s = weak;
        if (![s mtLive] || s.generation != token) return;
        [s mtSetPhase:MTLongShotPhaseReady];
        if (s.memoryStopped || s.terminalPause) { if (s.finishRequested) [s mtExport]; return; }
        if (!completed) { [s mtStop:@"短滑失败\n点完成保存" terminal:YES]; return; }
        [s mtSettleThenCapture:s.mode == MTLongShotModeAutomatic || s.finishRequested];
    }];
}
- (void)mtSettleThenCapture:(BOOL)capture {
    [self mtSetPhase:MTLongShotPhaseSettling]; self.hud.statusText = @"等待画面稳定";
    NSUInteger token = self.generation;
    __weak MTLongShotSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.task.configSnapshot.longShotOptions.settleDuration * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        MTLongShotSession *s = weak;
        if (![s mtLive] || s.generation != token) return;
        [s mtSetPhase:MTLongShotPhaseReady];
        if (s.memoryStopped || s.terminalPause) { if (s.finishRequested) [s mtExport]; return; }
        if (s.finishRequested || (capture && s.running)) { [s mtCapture]; return; }
        s.running = NO;
        [s mtShowReady:s.mode == MTLongShotModeSmart ? @"点截取下一段\n或点完成收尾" : @"已暂停\n点继续或完成"];
    });
}
- (void)longShotHUDDidTapFinish:(UIView *)hud {
    if (![self mtLive] || self.finishRequested) return;
    self.finishRequested = YES; self.running = NO; [self mtSetPhase:self.phase];
    self.hud.statusText = @"收齐当前段后保存";
    if (self.phase == MTLongShotPhaseReady) {
        if (self.terminalPause || self.memoryStopped)
            [self mtExport];
        else [self mtCapture];
    }
    // processing 自行收尾；scrolling/settling 在手势完整结束后收一次尾帧。
}
- (void)mtExport {
    if (![self mtLive] || self.phase != MTLongShotPhaseReady) return;
    if (!self.count) { [self mtFail:@"没有可保存的截图内容"]; return; }
    self.finishRequested = YES; self.running = NO;
    [self mtSetPhase:MTLongShotPhaseExporting]; self.hud.statusText = @"正在拼接长图";
    [self.timer invalidate]; self.timer = nil;
    [self.hud setPreviewImage:nil usedPixelHeight:0];
    NSURL *url = [NSURL fileURLWithPath:[[self.task existingTemporaryDirectory] stringByAppendingPathComponent:@"longshot.jpg"]];
    MTLongShotFrameStore *store = self.store;
    __weak MTLongShotSession *weak = self;
    dispatch_async(MTLongShotImageQueue(), ^{
        @autoreleasepool {
            NSError *error; CGSize size = CGSizeZero;
            UIImage *image = [store exportToURL:url pixelSize:&size progress:^(NSInteger done, NSInteger total) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    MTLongShotSession *s = weak;
                    if ([s mtLive] && s.phase == MTLongShotPhaseExporting)
                        s.hud.statusText = done >= total ? @"正在编码长图" : @"正在拼接长图";
                });
            } error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                MTLongShotSession *s = weak;
                if (![s mtLive]) return;
                if (!image) { [s mtFail:error.localizedDescription ?: @"长图导出失败"]; return; }
                MTCaptureLogInfo(@"long shot exported (task %@ count=%ld size=%@)", s.taskID, (long)s.count, NSStringFromCGSize(size));
                id<MTLongShotSessionDelegate> delegate = s.delegate;
                [s mtTeardown:NO]; [delegate longShotSessionDidFinish:s resultImage:image];
            });
        }
    });
}
- (void)longShotHUDDidTapCancel:(UIView *)hud { [self mtCancel]; }
- (void)mtCancel {
    if (self.isFinished) return;
    id<MTLongShotSessionDelegate> delegate = self.delegate;
    [self mtTeardown:YES]; [delegate longShotSessionDidCancel:self];
}
- (void)mtFail:(NSString *)message {
    if (self.isFinished) return;
    MTCaptureLogWarn(@"long shot failed (task %@): %@", self.taskID, message);
    id<MTLongShotSessionDelegate> delegate = self.delegate;
    [self mtTeardown:YES]; [delegate longShotSessionDidFail:self message:message];
}
- (void)teardownForExternalCancel {
    if (NSThread.isMainThread) [self mtTeardown:YES];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self mtTeardown:YES]; });
}
- (void)mtTeardown:(BOOL)remove {
    if (self.isFinished) return;
    // 在自增前取值：gen 仍与最后一次采集的 generation 日志对应。
    NSString *endTaskID = self.taskID;
    NSUInteger endGeneration = self.generation;
    self.phase = MTLongShotPhaseFinished; self.generation++; self.cancellation.cancelled = YES;
    [self.scroller cancel]; self.scroller = nil;
    [self.timer invalidate]; self.timer = nil;
    if (self.memoryObserver) [NSNotificationCenter.defaultCenter removeObserver:self.memoryObserver];
    self.memoryObserver = nil;
    if (MTLockSession == self) {
        atomic_fetch_add(&MTLockGeneration, 1); MTLockSession = nil;
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MTLockName, NULL);
    }
    [self.provider endVisibleWindowExclusion];
    self.hud.delegate = nil; [self.window hideAndDestroyWithCompletion:nil];
    self.window = nil; self.hud = nil; self.store = nil; self.task = nil; self.delegate = nil;
    if (remove) {
        NSString *taskID = self.taskID;
        dispatch_async(MTLongShotImageQueue(), ^{ [MTTemporaryFileStore removeTaskDirectory:taskID]; });
    }
    // t=0 在资源释放后采样，5/30/60 秒观察进程回收趋势。
    MTLongShotScheduleEndMemoryLogs(endTaskID, endGeneration);
}
@end
