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
// 回退 1 帧且超 1.5s 自动保存；切片质量 0.92。
static const NSTimeInterval MTShellXTimerInitial = 1.0;
static const NSTimeInterval MTShellXTimerActive = 0.12;
static const NSTimeInterval MTShellXTimerMedium = 0.5;
static const NSTimeInterval MTShellXTimerIdle = 10.0;
static const NSTimeInterval MTShellXIdleAutoFinish = 2.0;
static const NSTimeInterval MTShellXIdleCountdown = 6.0;
static const NSTimeInterval MTShellXReverseFinishDelay = 1.5;
static const NSInteger MTShellXMediumSameHashThreshold = 4;
static const double MTShellXSliceJPEGQuality = 0.92;

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
@property (nonatomic) NSInteger consecutiveReverseFrames;
@property (nonatomic) NSTimeInterval lastChangeTimestamp;
@property (nonatomic, strong, nullable) NSData *lastHash;
@property (nonatomic, strong, nullable) UIImage *lastFrame;      // 已裁剪帧
@property (nonatomic, nullable) uint8_t *lastStrip;      // 行 0 = 顶部（原始malloc指针，主线程独占释放）
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

- (BOOL)isFinished { return self.finished; }

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
    self.lastChangeTimestamp = [NSDate date].timeIntervalSince1970;
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
    self.consecutiveReverseFrames = 0;
    self.lastChangeTimestamp = [NSDate date].timeIntervalSince1970;
    [self.hud setCaptureTitle:@"停止录制" enabled:YES];
    [self.hud setStatusText:@"正在录制，请滚动页面"];
    [self mtScheduleCaptureTimer:MTShellXTimerInitial];
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
    if (self.finishRequested) [self mtExport];
}

- (void)mtRequestFinish {
    if (![self mtLive] || self.finishRequested || self.exporting) return;
    self.finishRequested = YES;
    self.recording = NO;
    [self mtScheduleCaptureTimer:0];
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
    @try {
        [self.provider captureExcludingWindows:@[self.window] completion:^(UIImage *image, BOOL partial,
                                                                          NSString *method, NSError *error) {
            MTShellXRecordingSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            s.busy = NO;
            if (!image || partial) {
                s.hud.statusText = @"抓屏失败，将继续重试";
                MTCaptureLogWarn(@"shellx recording capture failed (task %@ method=%@ error=%@)",
                          s.taskID, method, error.localizedDescription);
                if (s.finishRequested) [s mtExport];     // 抓屏失败时在途帧已终止，直接收尾
                return;                                  // 否则定时器下一轮重试
            }
            [s mtProcess:image token:token];
        }];
    } @catch (__unused NSException *exception) {
        self.busy = NO;
        MTCaptureLogWarn(@"shellx recording capture exception (task %@)", self.taskID);
    }
}

- (void)mtProcess:(UIImage *)image token:(NSUInteger)token {
    CGRect pixelRect = MTConvertDisplayRectToPixel(self.displayRect, self.task.capturedScreenBounds.size,
                            CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage)));
    pixelRect = CGRectIntegral(pixelRect);
    if (CGRectIsEmpty(pixelRect)) { self.busy = NO; return; }
    CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, pixelRect);
    if (!cropped) { self.busy = NO; return; }
    CGFloat scale = image.scale;
    UIImage *frame = [UIImage imageWithCGImage:cropped scale:scale orientation:image.imageOrientation];
    CGImageRelease(cropped);
    if (!self.directoryReady) {
        NSString *directory = [self.task ensureTemporaryDirectory];
        if (!directory.length) { self.busy = NO; [self mtFail:@"临时目录创建失败"]; return; }
        self.sliceDirectory = directory;
    }
    // 指纹在后台比较：主线程先取快照，避免后台读 nonatomic 属性与主线程写竞争。
    NSData *previousHash = self.lastHash;
    __weak MTShellXRecordingSession *weak = self;
    dispatch_async(MTShellXFrameQueue(), ^{
        @autoreleasepool {
            NSData *hash = MTShellXFastHash(frame);
            BOOL same = hash && [hash isEqualToData:previousHash];
            dispatch_async(dispatch_get_main_queue(), ^{
                MTShellXRecordingSession *s = weak;
                if (![s mtLive] || s.generation != token) return;
                if (same) { [s mtFrameUnchanged]; return; }
                s.lastHash = hash;
                s.lastChangeTimestamp = [NSDate date].timeIntervalSince1970;
                s.consecutiveSameHash = 0;
                [s mtSwitchToActive];
                [s mtStitchFrame:frame token:token];
            });
        }
    });
}

- (void)mtFrameUnchanged {
    self.busy = NO;
    self.consecutiveSameHash++;
    NSTimeInterval elapsed = [NSDate date].timeIntervalSince1970 - self.lastChangeTimestamp;
    // SHELLX 收尾判定：回退 1 帧且超 1.5s（已有 2 片）先于降档检查。
    if (self.consecutiveReverseFrames >= 1 && elapsed > MTShellXReverseFinishDelay &&
        [self mtSliceCount] >= 2) {
        MTCaptureLogInfo(@"shellx recording reverse finish (task %@ slices=%ld)",
                  self.taskID, (long)[self mtSliceCount]);
        [self.hud setStatusText:@"检测到回退\n正在保存"];
        [self mtRequestFinish];
        return;
    }
    if (elapsed >= MTShellXIdleAutoFinish) [self mtSwitchToIdle];
    else if (self.consecutiveSameHash >= MTShellXMediumSameHashThreshold) [self mtSwitchToMedium];
    if (self.finishRequested) [self mtExport];
}

- (BOOL)directoryReady { return self.sliceDirectory.length > 0; }

- (NSInteger)mtSliceCount {
    @synchronized(self.slicePaths) { return (NSInteger)self.slicePaths.count; }
}

- (void)mtStitchFrame:(UIImage *)frame token:(NSUInteger)token {
    NSInteger sw, sh;
    CGFloat pixelWidth = CGImageGetWidth(frame.CGImage);
    CGFloat pixelHeight = CGImageGetHeight(frame.CGImage);
    MTShellXRecordingStripSize(pixelWidth, pixelHeight, &sw, &sh);
    NSInteger comparePixels = (NSInteger)(sw * 0.8);
    NSInteger sliceHpx = (NSInteger)(pixelHeight * 0.85);
    // 上一条带所有权移交给后台：后台只做 C 层计算，不触碰任何 ObjC 属性；
    // 主线程回调统一释放，避免后台读与主线程 free 竞争。
    uint8_t *previousStrip = self.lastStrip;
    self.lastStrip = NULL;
    NSInteger previousWidth = sw, previousHeight = sh;
    __weak MTShellXRecordingSession *weak = self;
    dispatch_async(MTShellXFrameQueue(), ^{
        NSInteger scrollRows = -1;
        uint8_t *strip = MTShellXCreateStrip(frame, sw, sh);
        if (strip && previousStrip) {
            // 条带尺寸由 displayRect 决定，会话内恒定；尺寸异常时按无重叠处理。
            if (previousWidth == sw && previousHeight == sh) {
                scrollRows = MTShellXMatchScroll(previousStrip, strip, sw * 4, sh,
                                                 MAX(40, (NSInteger)(sh * 0.2)), comparePixels);
            }
        } else if (strip) {
            scrollRows = 0;                                  // 首帧
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            MTShellXRecordingSession *s = weak;
            if (previousStrip) free(previousStrip);
            if (![s mtLive] || s.generation != token) {
                if (strip) free(strip);
                return;
            }
            if (!strip) { s.busy = NO; [s mtFail:@"帧处理内存不足"]; return; }
            if (scrollRows == 0 && !s.lastFrame) {
                [s mtAppendFirstSlice:frame sliceHpx:sliceHpx];
            } else if (scrollRows > 0) {
                NSInteger scrollPx = (NSInteger)llround((CGFloat)scrollRows * pixelHeight / sh);
                if (scrollPx >= 3 && scrollPx <= sliceHpx) {
                    [s mtAppendSlice:frame sliceHpx:sliceHpx scrollPx:scrollPx];
                }
                s.consecutiveReverseFrames = 0;
            } else if (scrollRows < 0) {
                // 全范围仍无重叠：回退或跨度过大；按 SHELLX 语义计入回退，
                // 由 mtFrameUnchanged 的 1.5s 判定触发自动保存。
                s.consecutiveReverseFrames++;
            }
            s.lastStrip = strip;
            s.lastFrame = frame;
            s.busy = NO;
            [s mtUpdatePreview:frame];
            if (s.finishRequested) [s mtExport];
        });
    });
}

- (void)mtAppendFirstSlice:(UIImage *)frame sliceHpx:(NSInteger)sliceHpx {
    [self mtSaveSlice:frame top:0 height:sliceHpx];
    self.totalStitchedHeight = sliceHpx / MAX([self frameScale:frame], 0.01);
    MTCaptureLogInfo(@"shellx recording first slice (task %@ sliceH=%ld)", self.taskID, (long)sliceHpx);
}

- (void)mtAppendSlice:(UIImage *)frame sliceHpx:(NSInteger)sliceHpx scrollPx:(NSInteger)scrollPx {
    [self mtSaveSlice:frame top:sliceHpx - scrollPx height:scrollPx];
    self.totalStitchedHeight += scrollPx / MAX([self frameScale:frame], 0.01);
    [self.hud setSliceCount:[self mtSliceCount]];
    self.hud.statusText = [NSString stringWithFormat:@"已拼接 %ld px", (long)self.totalStitchedHeight];
}

- (CGFloat)frameScale:(UIImage *)frame { return frame.scale > 0 ? frame.scale : 1; }

- (void)mtSaveSlice:(UIImage *)frame top:(NSInteger)top height:(NSInteger)height {
    if (height < 1) return;
    CGImageRef cg = frame.CGImage;
    CGFloat pixelHeight = CGImageGetHeight(cg);
    top = MAX(0, MIN(top, (NSInteger)pixelHeight - 1));
    height = MIN(height, (NSInteger)pixelHeight - top);
    if (height < 1) return;
    CGImageRef piece = CGImageCreateWithImageInRect(cg, CGRectMake(0, top, CGImageGetWidth(cg), height));
    if (!piece) return;
    CGFloat scale = [self frameScale:frame];
    UIImage *slice = [UIImage imageWithCGImage:piece scale:scale orientation:frame.imageOrientation];
    CGImageRelease(piece);
    NSString *path = [self.sliceDirectory stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"shellx_slice_%ld.jpg", (long)[self mtSliceCount]]];
    NSData *data = UIImageJPEGRepresentation(slice, MTShellXSliceJPEGQuality);
    if (data && [data writeToFile:path atomically:YES]) {
        @synchronized(self.slicePaths) { [self.slicePaths addObject:path]; }
    }
}

- (void)mtUpdatePreview:(UIImage *)frame {
    if (!frame) return;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
        initWithSize:CGSizeMake(frame.size.width * 0.25, frame.size.height * 0.25) format:format];
    UIImage *thumb = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [frame drawInRect:CGRectMake(0, 0, frame.size.width * 0.25, frame.size.height * 0.25)];
    }];
    [self.hud setPreviewImage:thumb usedPixelHeight:(NSInteger)(frame.size.height * frame.scale * 0.25)];
}

#pragma mark - 导出

- (void)mtExport {
    if (![self mtLive] || self.exporting || self.finished) return;
    if (![self mtSliceCount]) { [self mtFail:@"没有可保存的截图内容"]; return; }
    self.exporting = YES;
    [self.hud setCaptureTitle:@"停止录制" enabled:NO];
    self.hud.statusText = @"正在合并长图";
    MTCaptureLogInfo(@"shellx recording export (task %@ slices=%ld totalH=%.0f)",
              self.taskID, (long)[self mtSliceCount], self.totalStitchedHeight);
    // SHELLX 收尾：把最后一帧未拼入的底部尾巴（15%）补为末片。
    UIImage *last = self.lastFrame;
    if (last) {
        CGFloat pixelHeight = CGImageGetHeight(last.CGImage);
        NSInteger sliceHpx = (NSInteger)(pixelHeight * 0.85);
        NSInteger tail = (NSInteger)pixelHeight - sliceHpx;
        if (tail >= 3) [self mtSaveSlice:last top:sliceHpx height:tail];
    }
    NSArray<NSString *> *paths = nil;
    @synchronized(self.slicePaths) { paths = [self.slicePaths copy]; }
    NSString *output = [[self.task existingTemporaryDirectory] ?: self.sliceDirectory
        stringByAppendingPathComponent:@"longshot.jpg"];
    __weak MTShellXRecordingSession *weak = self;
    dispatch_async(MTShellXFrameQueue(), ^{
        @autoreleasepool {
            CGSize size = CGSizeZero;
            NSError *error = nil;
            UIImage *image = MTShellXComposeSlices(paths, output,
                                                   self.task.configSnapshot.longShotOptions.maxCanvasHeight,
                                                   self.task.configSnapshot.longShotOptions.outputQuality,
                                                   &size, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                MTShellXRecordingSession *s = weak;
                if (![s mtLive]) return;
                if (!image) { [s mtFail:error.localizedDescription ?: @"长图合并失败"]; return; }
                MTCaptureLogInfo(@"shellx recording exported (task %@ size=%@)", s.taskID, NSStringFromCGSize(size));
                id<MTLongShotSessionDelegate> delegate = s.delegate;
                [s mtTeardown:NO];
                [delegate longShotSessionDidFinish:s resultImage:image];
            });
        }
    });
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
    self.finished = YES;
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
    if (self.lastStrip) { free(self.lastStrip); self.lastStrip = NULL; }
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
