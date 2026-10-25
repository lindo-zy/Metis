#import "MTShellXRecordingSession.h"
#import "MTShellXSupport.h"
#import "../Capture/MTCaptureTask.h"
#import "../Capture/MTCaptureProvider.h"
#import "../Capture/MTLongShotTarget.h"
#import "../Common/MTCaptureLog.h"
#import "../Common/MTLongShotControl.h"
#import "../Common/MTGeometry.h"
#import "../Output/MTTemporaryFileStore.h"
#import "../Overlay/MTCaptureWindow.h"
#import "../Overlay/MTLongShotHUD.h"
#import <stdatomic.h>
#import <math.h>

// 三档采集间隔与自动收尾阈值均为 SHELLX 3.1.1 实测常量：
// 初始 1.0s；活跃 0.12s；连续 4 帧未变 0.5s；静止 2s 空闲 10s + 6s 倒计时；
// 反向或无法确认重叠时保留已截内容并暂停；切片质量 0.92。
static const NSTimeInterval MTShellXTimerInitial = 1.0;
static const NSTimeInterval MTShellXTimerActive = 0.12;
static const NSTimeInterval MTShellXTimerMedium = 0.5;
static const NSTimeInterval MTShellXTimerIdle = 10.0;
static const NSTimeInterval MTShellXIdleAutoFinish = 2.0;
static const NSTimeInterval MTShellXIdleCountdown = 6.0;
static const NSInteger MTShellXMediumSameHashThreshold = 4;

static dispatch_queue_t MTShellXFrameQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.lindo.metis.capture.shellx.frames", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

@interface MTShellXRecordingSession () <MTLongShotHUDDelegate>
@property (nonatomic, strong) MTCaptureTask *task;
@property (nonatomic, copy) NSString *taskID;
@property (nonatomic, weak) id<MTLongShotSessionDelegate> delegate;
@property (nonatomic, strong) MTCaptureProvider *provider;
@property (nonatomic, strong) MTLongShotCancellation *cancellation;
@property (nonatomic, strong) MTCaptureWindow *window;
@property (nonatomic, strong) MTLongShotHUD *hud;
@property (nonatomic, strong) NSTimer *captureTimer;
@property (nonatomic, strong) NSTimer *tickTimer;
@property (nonatomic, strong) id memoryObserver;
@property (nonatomic) CGRect displayRect;
@property (nonatomic) BOOL recording;
@property (nonatomic) BOOL busy;              // 一帧在途（processLock 语义）
@property (nonatomic) BOOL finishRequested;
@property (nonatomic) BOOL memoryStopped;
@property (nonatomic) BOOL idleMode;
@property (nonatomic) BOOL exporting;
@property (nonatomic, assign, getter=isFinished) BOOL finished;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSInteger consecutiveSameHash;
@property (nonatomic) NSTimeInterval lastChangeTimestamp;
@property (nonatomic, strong, nullable) NSData *lastHash;
@property (nonatomic, strong, nullable) UIImage *lastFrame;      // 已裁剪帧
@property (nonatomic, strong) NSData *lastSignature;
@property (nonatomic) NSInteger sigRows, sigBytesPerRow, captureFailures;
@property (nonatomic) CGFloat baseScale;
@property (nonatomic) NSMutableArray<NSString *> *slicePaths;    // objc_sync 保护
@property (nonatomic) CGFloat totalStitchedHeight;
@property (nonatomic, copy) NSString *sliceDirectory;
@property (nonatomic, copy) NSString *target;
- (void)mtCancel;
@end

// 锁屏取消：与会话级代数防串扰，模式与 MTLongShotSession 一致。
static __weak MTShellXRecordingSession *MTShellXRecLockSession;
static atomic_uint_fast64_t MTShellXRecLockGeneration;
static void MTShellXRecLockCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                    const void *object, CFDictionaryRef userInfo) {
    uint_fast64_t generation = atomic_load(&MTShellXRecLockGeneration);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == atomic_load(&MTShellXRecLockGeneration)) [MTShellXRecLockSession mtCancel];
    });
}

@implementation MTShellXRecordingSession

+ (instancetype)startWithTask:(MTCaptureTask *)task
                  displayRect:(CGRect)displayRect
                     delegate:(id<MTLongShotSessionDelegate>)delegate {
    NSParameterAssert(NSThread.isMainThread);
    MTShellXRecordingSession *s = [self new];
    s.task = task; s.taskID = task.taskID; s.delegate = delegate;
    s.displayRect = displayRect;
    s.target = MTLongShotFrontmostIdentifier(UIApplication.sharedApplication);
    s.provider = [MTCaptureProvider new];
    s.provider.detachesCapturedImage = YES;
    s.provider.keepsExcludedWindowsVisible = YES;
    s.cancellation = [MTLongShotCancellation new];
    task.baseImage = nil;
    s.slicePaths = [NSMutableArray array];
    s.lastChangeTimestamp = [NSDate date].timeIntervalSince1970;
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
    [s.hud setModeTitle:@"SHELLX 录制式"];
    [s.window showAnimated:NO becomeKey:NO];
    [s.hud setCaptureTitle:@"开始录制" enabled:YES];
    [s.hud setStatusText:@"滚动页面，点「停止录制」保存"];
    atomic_fetch_add(&MTShellXRecLockGeneration, 1); MTShellXRecLockSession = s;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MTShellXRecLockCallback,
                                    CFSTR("com.apple.springboard.lockstate"), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    __weak MTShellXRecordingSession *weak = s;
    s.memoryObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weak mtMemoryWarning]; }];
    s.tickTimer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) { [weak mtTick]; }];
    [NSRunLoop.mainRunLoop addTimer:s.tickTimer forMode:NSRunLoopCommonModes];
    MTCaptureLogInfo(@"shellx recording ready (task %@ rect=%@)", s.taskID, NSStringFromCGRect(displayRect));
    return s;
}

- (BOOL)isFinished { return _finished; }

- (BOOL)mtLive {
    return !self.finished && !self.cancellation.cancelled &&
           self.task.currentState == MTCaptureStatePresenting &&
           [self.taskID isEqual:self.task.taskID];
}

- (BOOL)mtTargetCurrent {
    return MTLongShotTargetIsCurrent(UIApplication.sharedApplication, MTLongShotLockManager(), self.target);
}

- (BOOL)mtHasMemory {
    size_t available = MTLongShotAvailableMemoryBytes();
    return !available || available >= MTLongShotMemoryFloorBytes();
}

#pragma mark - 状态机

- (void)mtScheduleCaptureTimer:(NSTimeInterval)interval {
    [self.captureTimer invalidate];
    self.captureTimer = nil;
    if (interval <= 0) return;
    __weak MTShellXRecordingSession *weak = self;
    self.captureTimer = [NSTimer timerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
        [weak mtCaptureFrame];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.captureTimer forMode:NSRunLoopCommonModes];
}

- (void)mtSwitchToActive {
    if (self.idleMode) { self.idleMode = NO; [self.hud setStatusText:@"继续录制"]; }
    if (fabs(self.captureTimer.timeInterval - MTShellXTimerActive) < 0.001) return;
    [self mtScheduleCaptureTimer:MTShellXTimerActive];
}

- (void)mtSwitchToMedium {
    if (fabs(self.captureTimer.timeInterval - MTShellXTimerMedium) < 0.001) return;
    [self mtScheduleCaptureTimer:MTShellXTimerMedium];
}

- (void)mtSwitchToIdle {
    if (self.idleMode) return;
    self.idleMode = YES;
    [self mtScheduleCaptureTimer:MTShellXTimerIdle];
    MTCaptureLogInfo(@"shellx recording idle (task %@)", self.taskID);
}

#pragma mark - 生命周期钩子

- (void)mtTick {
    if (![self mtLive] || self.exporting) return;
    if (![self mtTargetCurrent]) {
        if (self.recording) [self mtStopRecordingForFinish:@"前台 App 已变化\n点完成保存"];
        return;
    }
    if (self.idleMode && self.recording && !self.finishRequested) {
        // SHELLX：空闲倒计时 6s 归零自动保存；触摸预览立即恢复活跃档。
        NSTimeInterval elapsed = [NSDate date].timeIntervalSince1970 - self.lastChangeTimestamp;
        NSTimeInterval remaining = MTShellXIdleCountdown - elapsed;
        if (self.hud.isPreviewInteracting) {
            self.lastChangeTimestamp = [NSDate date].timeIntervalSince1970;
            [self mtSwitchToActive];
            return;
        }
        if (remaining <= 0) {
            MTCaptureLogInfo(@"shellx recording idle countdown finished (task %@)", self.taskID);
            [self mtRequestFinish];
        } else {
            self.hud.statusText = [NSString stringWithFormat:@"已静止\n%.0f 秒后自动保存", ceil(remaining)];
        }
    }
}

- (void)mtMemoryWarning {
    if (![self mtLive] || !self.recording || self.finishRequested) return;
    self.memoryStopped = YES;
    [self.hud setPreviewImage:nil usedPixelHeight:0];
    [self mtRequestFinish];
    MTCaptureLogWarn(@"shellx recording memory stop (task %@ slices=%lu)",
              self.taskID, (unsigned long)self.slicePaths.count);
}

#pragma mark - HUD

- (void)longShotHUDDidTapCapture:(UIView *)hud {
    if (![self mtLive] || self.finishRequested || self.exporting) return;
    if (self.recording) {
        [self mtRequestFinish];
        return;
    }
    if (![self mtTargetCurrent]) { [self mtStopRecordingForFinish:@"请返回原 App\n点完成保存"]; return; }
    if (!self.memoryStopped && ![self mtHasMemory]) {
        self.memoryStopped = YES; [self mtRequestFinish]; return;
    }
    self.recording = YES;
    self.consecutiveSameHash = 0;
    self.lastChangeTimestamp = [NSDate date].timeIntervalSince1970;
    [self.hud setCaptureTitle:@"停止录制" enabled:YES];
    [self.hud setStatusText:@"正在录制，请滚动页面"];
    [self mtScheduleCaptureTimer:MTShellXTimerInitial];
    [self mtCaptureFrame];
    MTCaptureLogInfo(@"shellx recording started (task %@)", self.taskID);
}

- (void)longShotHUDDidTapFinish:(UIView *)hud {
    if (![self mtLive] || self.exporting) return;
    [self mtRequestFinish];
}

- (void)longShotHUDDidTapCancel:(UIView *)hud { [self mtCancel]; }

- (void)mtStopRecordingForFinish:(NSString *)message {
    self.recording = NO;
    [self mtScheduleCaptureTimer:0];
    [self.hud setCaptureTitle:@"开始录制" enabled:NO];
    self.hud.statusText = message;
    MTCaptureLogWarn(@"shellx recording paused (task %@ slices=%lu): %@",
              self.taskID, (unsigned long)self.slicePaths.count, message);
    if (self.finishRequested && !self.busy) [self mtExport];
}

- (void)mtRequestFinish {
    if (![self mtLive] || self.finishRequested || self.exporting) return;
    self.finishRequested = YES;
    self.recording = NO;
    [self mtScheduleCaptureTimer:0];
    [self.hud setCaptureTitle:@"停止中" enabled:NO];
    [self.hud setFinishing:YES];
    if (!self.busy) [self mtExport];
    // busy 时由在途帧收尾；exporting 由其自身保证只进一次。
}

#pragma mark - 采集

- (void)mtCaptureFrame {
    if (![self mtLive] || !self.recording || self.busy || self.finishRequested || self.exporting) return;
    if (![self mtTargetCurrent]) return;               // tick 会给出终端提示
    if (![self mtHasMemory]) { self.memoryStopped = YES; [self mtRequestFinish]; return; }
    NSInteger sliceCount = [self mtSliceCount];
    if (sliceCount >= self.task.configSnapshot.longShotOptions.maxSlices) {
        MTCaptureLogInfo(@"shellx recording slice cap (task %@ count=%ld)", self.taskID, (long)sliceCount);
        [self mtRequestFinish];
        return;
    }
    self.busy = YES;
    NSUInteger token = ++self.generation;
    __weak MTShellXRecordingSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MTShellXRecordingSession *s = weak;
        if (![s mtLive] || s.generation != token || !s.busy) return;
        s.generation++; s.busy = NO;
        MTCaptureLogWarn(@"shellx recording frame timed out (task %@)", s.taskID);
        if (s.finishRequested) [s mtExport]; else [s mtRequestFinish];
    });
    @try {
        [self.provider captureExcludingWindows:@[self.window] completion:^(UIImage *image, BOOL partial,
                                                                          NSString *method, NSError *error) {
            MTShellXRecordingSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            if (![s mtTargetCurrent]) {
                s.busy = NO;
                if (s.finishRequested) [s mtExport]; else [s mtRequestFinish]; return;
            }
            if (!image.CGImage || partial) {
                s.busy = NO; s.captureFailures++;
                s.hud.statusText = @"抓屏失败，将继续重试";
                MTCaptureLogWarn(@"shellx recording capture failed (task %@ method=%@ error=%@)",
                          s.taskID, method, error.localizedDescription);
                if (s.finishRequested) [s mtExport];
                else if (s.captureFailures >= 3) [s mtRequestFinish];
                return;                                  // 否则定时器下一轮重试
            }
            [s mtProcess:image token:token];
        }];
    } @catch (__unused NSException *exception) {
        self.busy = NO;
        MTCaptureLogWarn(@"shellx recording capture exception (task %@)", self.taskID);
        if (self.finishRequested) [self mtExport];
        else [self mtRequestFinish];
    }
}

- (void)mtProcess:(UIImage *)image token:(NSUInteger)token {
    CGRect pixelRect = CGRectIntegral(MTConvertDisplayRectToPixel(self.displayRect, self.task.capturedScreenBounds.size,
        CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage))));
    if (!self.sliceDirectory) self.sliceDirectory = [self.task ensureTemporaryDirectory];
    if (!self.sliceDirectory.length) { self.busy = NO; [self mtFail:@"临时目录创建失败"]; return; }
    NSData *previousHash = self.lastHash, *previousSignature = self.lastSignature;
    NSInteger previousRows = self.sigRows, previousBPR = self.sigBytesPerRow;
    NSString *path = [self.sliceDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"slice_%ld.jpg", (long)[self mtSliceCount]]];
    MTLongShotCancellation *cancel = self.cancellation;
    __weak MTShellXRecordingSession *weak = self;
    dispatch_async(MTShellXFrameQueue(), ^{ @autoreleasepool {
        if (cancel.cancelled) return;
        CGImageRef cg = CGImageCreateWithImageInRect(image.CGImage, pixelRect);
        UIImage *frame = cg ? [UIImage imageWithCGImage:cg scale:image.scale orientation:UIImageOrientationUp] : nil;
        if (cg) CGImageRelease(cg);
        NSData *hash = frame ? MTShellXFastHash(frame) : nil;
        BOOL same = hash && [hash isEqualToData:previousHash];
        NSInteger rows = 0, w = 0, bpr = 0;
        NSData *signature = !same && frame ? MTShellXRowSignature(frame, &rows, &w, &bpr) : nil;
        NSInteger shift = previousSignature ? -1 : 0;
        if (!same && previousSignature && signature && previousRows == rows && previousBPR == bpr)
            shift = MTShellXMatchScroll(previousSignature.bytes, signature.bytes, bpr, rows, MAX(8, rows / 5), w);
        NSInteger h = frame.CGImage ? CGImageGetHeight(frame.CGImage) : 0;
        NSInteger cut = MIN(h - 4, (NSInteger)(h * 0.85));
        NSInteger added = previousSignature ? (NSInteger)llround((CGFloat)shift * h / MAX(rows, 1)) : cut;
        BOOL saved = !same && signature && added > 0 && added <= cut && !cancel.cancelled &&
            MTShellXWriteSlice(frame, cut - added, added, path);
        UIImage *thumb = saved ? MTShellXThumbnail(frame, 240) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            MTShellXRecordingSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            s.busy = NO; s.captureFailures = 0;
            if (same || (signature && shift == 0 && previousSignature)) { [s mtFrameUnchanged]; return; }
            if (!signature || (shift >= 0 && !saved)) { [s mtFail:@"帧处理或切片写盘失败"]; return; }
            if (shift < 0 || added > cut) {
                [s mtStopRecordingForFinish:@"画面重叠不足，点完成保存已截内容"];
                return; // 保留上一张成功拼接帧，不能把尾巴接到未对齐的帧上。
            }
            [s.slicePaths addObject:path]; s.totalStitchedHeight += added;
            s.lastFrame = frame; s.lastHash = hash; s.lastSignature = signature; s.sigRows = rows; s.sigBytesPerRow = bpr;
            s.lastChangeTimestamp = [NSDate date].timeIntervalSince1970;
            s.consecutiveSameHash = 0;
            [s.hud setSliceCount:[s mtSliceCount]];
            [s.hud setPreviewImage:thumb usedPixelHeight:CGImageGetHeight(thumb.CGImage)];
            if (s.finishRequested) [s mtExport];
            else if (s.recording) [s mtSwitchToActive];
        });
    }});
}

- (void)mtFrameUnchanged {
    self.busy = NO;
    self.consecutiveSameHash++;
    NSTimeInterval elapsed = [NSDate date].timeIntervalSince1970 - self.lastChangeTimestamp;
    if (self.recording && !self.finishRequested) {
        if (elapsed >= MTShellXIdleAutoFinish) [self mtSwitchToIdle];
        else if (self.consecutiveSameHash >= MTShellXMediumSameHashThreshold) [self mtSwitchToMedium];
    }
    if (self.finishRequested) [self mtExport];
}

- (NSInteger)mtSliceCount { return self.slicePaths.count; } // 主线程独占

#pragma mark - 导出

- (void)mtExport {
    if (![self mtLive] || self.exporting || self.busy) return;
    if (![self mtSliceCount]) { [self mtFail:@"没有可保存的截图内容"]; return; }
    self.exporting = YES; self.recording = NO;
    [self mtScheduleCaptureTimer:0];
    [self.hud setCaptureTitle:@"停止录制" enabled:NO]; [self.hud setFinishing:YES];
    [self.hud setPreviewImage:nil usedPixelHeight:0];
    self.hud.statusText = @"正在合并长图";
    NSArray<NSString *> *paths = [self.slicePaths copy];
    UIImage *last = self.lastFrame;
    NSString *directory = self.sliceDirectory;
    MTLongShotOptions *options = self.task.configSnapshot.longShotOptions;
    MTLongShotCancellation *cancel = self.cancellation;
    self.lastFrame = nil; self.lastHash = nil; self.lastSignature = nil;
    __weak MTShellXRecordingSession *weak = self;
    dispatch_async(MTShellXFrameQueue(), ^{ @autoreleasepool {
        if (cancel.cancelled) return;
        NSMutableArray<NSString *> *slices = [paths mutableCopy];
        NSInteger h = last.CGImage ? CGImageGetHeight(last.CGImage) : 0;
        NSInteger cut = MIN(h - 4, (NSInteger)(h * 0.85));
        NSString *tail = [directory stringByAppendingPathComponent:@"tail.jpg"];
        BOOL valid = last && MTShellXWriteSlice(last, cut, h - cut, tail);
        if (valid) [slices addObject:tail];
        CGSize size = CGSizeZero; NSError *error = nil;
        UIImage *result = valid ? MTShellXComposeSlices(slices, [directory stringByAppendingPathComponent:@"longshot.jpg"], options.maxCanvasHeight, options.outputQuality, cancel, &size, &error) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            MTShellXRecordingSession *s = weak;
            if (![s mtLive]) return;
            if (!result) { [s mtFail:error.localizedDescription ?: @"长图尾片写盘失败"]; return; }
            MTCaptureLogInfo(@"shellx recording exported (task %@ slices=%lu size=%@)", s.taskID, (unsigned long)slices.count, NSStringFromCGSize(size));
            id<MTLongShotSessionDelegate> delegate = s.delegate;
            [s mtTeardown:NO]; [delegate longShotSessionDidFinish:s resultImage:result];
        });
    }});
}

- (void)mtCancel {
    if (self.finished) return;
    id<MTLongShotSessionDelegate> delegate = self.delegate;
    [self mtTeardown:YES];
    [delegate longShotSessionDidCancel:self];
}

- (void)mtFail:(NSString *)message {
    if (self.finished) return;
    MTCaptureLogWarn(@"shellx recording failed (task %@): %@", self.taskID, message);
    id<MTLongShotSessionDelegate> delegate = self.delegate;
    [self mtTeardown:YES];
    [delegate longShotSessionDidFail:self message:message];
}

- (void)teardownForExternalCancel {
    if (NSThread.isMainThread) [self mtTeardown:YES];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self mtTeardown:YES]; });
}

- (void)mtTeardown:(BOOL)remove {
    if (self.finished) return;
    _finished = YES; self.generation++;
    self.recording = NO;
    self.cancellation.cancelled = YES;
    [self.captureTimer invalidate]; self.captureTimer = nil;
    [self.tickTimer invalidate]; self.tickTimer = nil;
    if (self.memoryObserver) [NSNotificationCenter.defaultCenter removeObserver:self.memoryObserver];
    self.memoryObserver = nil;
    if (MTShellXRecLockSession == self) {
        atomic_fetch_add(&MTShellXRecLockGeneration, 1); MTShellXRecLockSession = nil;
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                           CFSTR("com.apple.springboard.lockstate"), NULL);
    }
    self.lastSignature = nil; [self.slicePaths removeAllObjects];
    self.hud.delegate = nil;
    [self.window hideAndDestroyWithCompletion:nil];
    self.window = nil; self.hud = nil; self.lastFrame = nil; self.lastHash = nil;
    self.task = nil; self.delegate = nil;
    if (remove) {
        NSString *taskID = self.taskID;
        dispatch_async(MTShellXFrameQueue(), ^{ [MTTemporaryFileStore removeTaskDirectory:taskID]; });
    }
}

@end
