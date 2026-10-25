#import "MTShellXStitchSession.h"
#import "MTShellXSupport.h"
#import "../Capture/MTCaptureTask.h"
#import "../Capture/MTCaptureProvider.h"
#import "../Capture/MTLongShotScroller.h"
#import "../Capture/MTLongShotTarget.h"
#import "../Common/MTCaptureLog.h"
#import "../Common/MTLongShotControl.h"
#import "../Common/MTGeometry.h"
#import "../Output/MTTemporaryFileStore.h"
#import "../Overlay/MTCaptureWindow.h"
#import "../Overlay/MTLongShotHUD.h"
#import <stdatomic.h>
#import <math.h>

// SHELLX 拼接式节奏常量：滑动后 0.7s 稳定再截；到底判定为相邻两屏
// 行签名逐字节相同 ×2；收尾间隔 0.18s；原图/切片 JPEG 质量 0.92。
static const NSInteger MTShellXBottomSameThreshold = 2;

static dispatch_queue_t MTShellXStitchQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.lindo.metis.capture.shellx.stitch", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

@interface MTShellXStitchSession () <MTLongShotHUDDelegate>
@property (nonatomic, strong) MTCaptureTask *task;
@property (nonatomic, copy) NSString *taskID;
@property (nonatomic, weak) id<MTLongShotSessionDelegate> delegate;
@property (nonatomic, strong) MTCaptureProvider *provider;
@property (nonatomic, strong) MTLongShotCancellation *cancellation;
@property (nonatomic, strong) MTCaptureWindow *window;
@property (nonatomic, strong) MTLongShotHUD *hud;
@property (nonatomic, strong) MTLongShotScroller *scroller;
@property (nonatomic, strong) NSTimer *tickTimer;
@property (nonatomic, strong) id memoryObserver;
@property (nonatomic) CGRect displayRect;
@property (nonatomic) BOOL automatic;
@property (nonatomic) BOOL loopRunning;       // 自动循环进行中
@property (nonatomic) BOOL busy;              // 一次截取/滑动在途
@property (nonatomic) BOOL finishRequested;
@property (nonatomic) BOOL exporting;
@property (nonatomic, assign, getter=isFinished) BOOL finished;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSInteger sameCount;
@property (nonatomic) NSMutableArray<NSString *> *fullPaths;   // objc_sync 保护
@property (nonatomic, strong) NSData *lastSignature;
@property (nonatomic) NSInteger sigRows, sigBytesPerRow;
@property (nonatomic) BOOL scrolling, settling, terminalPause;
@property (nonatomic, copy) NSString *workDirectory;
@property (nonatomic, copy) NSString *target;
- (void)mtCancel;
@end

static __weak MTShellXStitchSession *MTShellXStitchLockSession;
static atomic_uint_fast64_t MTShellXStitchLockGeneration;
static void MTShellXStitchLockCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                       const void *object, CFDictionaryRef userInfo) {
    uint_fast64_t generation = atomic_load(&MTShellXStitchLockGeneration);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == atomic_load(&MTShellXStitchLockGeneration)) [MTShellXStitchLockSession mtCancel];
    });
}

@implementation MTShellXStitchSession

+ (instancetype)startWithTask:(MTCaptureTask *)task
                  displayRect:(CGRect)displayRect
                     delegate:(id<MTLongShotSessionDelegate>)delegate
                         auto:(BOOL)automatic {
    NSParameterAssert(NSThread.isMainThread);
    MTShellXStitchSession *s = [self new];
    s.task = task; s.taskID = task.taskID; s.delegate = delegate;
    s.displayRect = displayRect; s.automatic = automatic;
    s.target = MTLongShotFrontmostIdentifier(UIApplication.sharedApplication);
    s.provider = [MTCaptureProvider new];
    s.provider.detachesCapturedImage = YES;
    s.provider.keepsExcludedWindowsVisible = YES;
    s.cancellation = [MTLongShotCancellation new];
    task.baseImage = nil;
    s.fullPaths = [NSMutableArray array];
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
    [s.hud setModeTitle:automatic ? @"SHELLX 自动拼接" : @"SHELLX 手动拼接"];
    [s.window showAnimated:NO becomeKey:NO];
    [s.hud setCaptureTitle:@"截取" enabled:YES];
    [s.hud setStatusText:automatic ? @"点「截取」开始，到底自动保存" : @"截一屏，滑动后再截，点「完成」保存"];
    atomic_fetch_add(&MTShellXStitchLockGeneration, 1); MTShellXStitchLockSession = s;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MTShellXStitchLockCallback,
                                    CFSTR("com.apple.springboard.lockstate"), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    __weak MTShellXStitchSession *weak = s;
    s.memoryObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weak mtMemoryWarning]; }];
    s.tickTimer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) { [weak mtTick]; }];
    [NSRunLoop.mainRunLoop addTimer:s.tickTimer forMode:NSRunLoopCommonModes];
    MTCaptureLogInfo(@"shellx stitch ready (task %@ auto=%d rect=%@)", s.taskID, automatic, NSStringFromCGRect(displayRect));
    return s;
}

// finished 的 getter 本身必须直接读 ivar，不能通过属性再次发送 isFinished。
- (BOOL)isFinished { return _finished; }
- (BOOL)mtLive {
    return !_finished && !self.cancellation.cancelled && self.task.currentState == MTCaptureStatePresenting &&
        [self.taskID isEqual:self.task.taskID];
}
- (BOOL)mtTargetCurrent {
    return MTLongShotTargetIsCurrent(UIApplication.sharedApplication, MTLongShotLockManager(), self.target);
}
- (BOOL)mtHasMemory {
    size_t available = MTLongShotAvailableMemoryBytes();
    return !available || available >= MTLongShotMemoryFloorBytes();
}
- (NSInteger)mtFullCount { return self.fullPaths.count; } // 仅主线程访问

- (void)mtTick {
    if (![self mtLive] || self.exporting) return;
    if (![self mtTargetCurrent] && (self.loopRunning || self.busy || self.scrolling || self.settling)) {
        self.hud.statusText = @"前台 App 已变化，保存已截内容";
        self.finishRequested = YES; self.loopRunning = NO;
        [self.scroller cancel];
        if (!self.busy && !self.scrolling) { self.settling = NO; [self mtExport]; }
    }
}
- (void)mtMemoryWarning {
    if (![self mtLive] || self.exporting) return;
    [self.hud setPreviewImage:nil usedPixelHeight:0];
    self.finishRequested = YES; self.loopRunning = NO;
    [self.scroller cancel];
    if (!self.busy && !self.scrolling) { self.settling = NO; [self mtExport]; }
}
- (void)longShotHUDDidTapCapture:(UIView *)hud {
    if (![self mtLive] || self.finishRequested || self.exporting || self.terminalPause) return;
    if (self.automatic && self.loopRunning) { [self mtRequestFinish]; return; }
    if (self.busy || self.scrolling || self.settling) return;
    if (![self mtTargetCurrent]) { self.hud.statusText = @"请返回原 App，或点完成保存"; return; }
    if (![self mtHasMemory]) { [self mtRequestFinish]; return; }
    if (!self.workDirectory) self.workDirectory = [self.task ensureTemporaryDirectory];
    if (!self.workDirectory.length) { [self mtFail:@"临时目录创建失败"]; return; }
    if (self.automatic && !self.scroller) {
        MTLongShotScroller *scroller = [MTLongShotScroller new];
        if (scroller.availabilityError) { self.hud.statusText = scroller.availabilityError; return; }
        self.scroller = scroller;
    }
    self.loopRunning = self.automatic;
    [self.hud setCaptureTitle:self.automatic ? @"停止" : @"截取" enabled:self.automatic];
    [self mtCapture];
}
- (void)longShotHUDDidTapFinish:(UIView *)hud { [self mtRequestFinish]; }
- (void)longShotHUDDidTapCancel:(UIView *)hud { [self mtCancel]; }

- (void)mtCapture {
    if (![self mtLive] || self.busy || self.exporting) return;
    if (![self mtTargetCurrent] || ![self mtHasMemory]) { [self mtRequestFinish]; return; }
    if ([self mtFullCount] >= MIN(65, self.task.configSnapshot.longShotOptions.maxSlices)) { [self mtRequestFinish]; return; }
    self.busy = YES;
    NSUInteger token = ++self.generation;
    self.hud.statusText = @"正在截取当前屏";
    __weak MTShellXStitchSession *weak = self;
    // 异步抓屏/归一化没有回调时仍可取消，且不会永远卡在 busy。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MTShellXStitchSession *s = weak;
        if (![s mtLive] || s.generation != token || !s.busy) return;
        s.generation++; s.busy = NO;
        MTCaptureLogWarn(@"shellx stitch capture timed out (task %@)", s.taskID);
        [s mtRequestFinish];
    });
    @try {
        [self.provider captureExcludingWindows:@[self.window] completion:^(UIImage *image, BOOL partial, NSString *method, NSError *error) {
            MTShellXStitchSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            if (![s mtTargetCurrent]) {
                s.busy = NO;
                [s mtRequestFinish]; return;
            }
            if (!image.CGImage || partial) {
                s.busy = NO;
                MTCaptureLogWarn(@"shellx stitch capture failed (task %@ method=%@ error=%@)", s.taskID, method, error.localizedDescription);
                [s mtRequestFinish]; return;
            }
            [s mtHandleCaptured:image token:token];
        }];
    } @catch (NSException *exception) {
        self.busy = NO;
        MTCaptureLogWarn(@"shellx stitch capture exception (task %@ name=%@)", self.taskID, exception.name);
        [self mtRequestFinish];
    }
}

- (void)mtHandleCaptured:(UIImage *)image token:(NSUInteger)token {
    // 主线程只取不可变快照；裁图、签名、预览缩放、JPEG 与写盘全部串行后台执行。
    CGRect pixelRect = CGRectIntegral(MTConvertDisplayRectToPixel(self.displayRect, self.task.capturedScreenBounds.size,
        CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage))));
    NSString *path = [self.workDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"full_%ld.jpg", (long)[self mtFullCount]]];
    NSData *previous = self.lastSignature;
    NSInteger previousRows = self.sigRows, previousBPR = self.sigBytesPerRow;
    MTLongShotCancellation *cancel = self.cancellation;
    __weak MTShellXStitchSession *weak = self;
    dispatch_async(MTShellXStitchQueue(), ^{ @autoreleasepool {
        if (cancel.cancelled) return;
        CGImageRef cg = CGImageCreateWithImageInRect(image.CGImage, pixelRect);
        UIImage *frame = cg ? [UIImage imageWithCGImage:cg scale:image.scale orientation:UIImageOrientationUp] : nil;
        if (cg) CGImageRelease(cg);
        NSInteger rows = 0, width = 0, bpr = 0;
        NSData *signature = frame ? MTShellXRowSignature(frame, &rows, &width, &bpr) : nil;
        NSInteger shift = previous ? -1 : 1;
        if (previous && signature && rows == previousRows && bpr == previousBPR)
            shift = MTShellXMatchScroll(previous.bytes, signature.bytes, bpr, rows, MAX(8, rows / 5), width);
        BOOL saved = signature && shift > 0 && !cancel.cancelled &&
            MTShellXWriteSlice(frame, 0, CGImageGetHeight(frame.CGImage), path);
        UIImage *thumb = saved ? MTShellXThumbnail(frame, 240) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            MTShellXStitchSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            s.busy = NO;
            if (!signature || (shift > 0 && !saved)) { [s mtFail:@"帧处理或写盘失败"]; return; }
            if (shift < 0) {
                s.loopRunning = NO; s.terminalPause = YES;
                s.hud.statusText = @"画面重叠不足，点完成保存已截内容";
                [s.hud setCaptureTitle:@"截取" enabled:NO];
                if (s.finishRequested) [s mtExport];
                return;
            }
            s.sameCount = shift == 0 ? s.sameCount + 1 : 0;
            if (saved) {
                [s.fullPaths addObject:path]; s.lastSignature = signature; s.sigRows = rows; s.sigBytesPerRow = bpr;
                [s.hud setSliceCount:[s mtFullCount]];
                [s.hud setPreviewImage:thumb usedPixelHeight:CGImageGetHeight(thumb.CGImage)];
            }
            MTCaptureLogInfo(@"shellx stitch frame (task %@ count=%ld shift=%ld same=%ld)", s.taskID, (long)[s mtFullCount], (long)shift, (long)s.sameCount);
            [s mtAfterCaptured];
        });
    }});
}
- (void)mtAfterCaptured {
    if (self.finishRequested || (self.automatic && self.sameCount >= MTShellXBottomSameThreshold) ||
        [self mtFullCount] >= MIN(65, self.task.configSnapshot.longShotOptions.maxSlices)) { [self mtRequestFinish]; return; }
    if (self.automatic && self.loopRunning) { [self mtScroll]; return; }
    [self.hud setCaptureTitle:@"截取" enabled:YES];
    self.hud.statusText = @"滑动后继续截取，或点完成保存";
}
- (void)mtScroll {
    if (![self mtLive] || self.exporting) return;
    if (self.finishRequested) { [self mtExport]; return; }
    MTLongShotScrollPlan plan;
    CGRect protected = [self.hud convertRect:self.hud.panelFrame toCoordinateSpace:self.window.screen.coordinateSpace];
    if (!MTLongShotBuildScrollPlan(self.displayRect, self.task.capturedScreenBounds, protected, &plan)) { [self mtRequestFinish]; return; }
    // SHELLX 原包短滑 0.60→0.42/0.47，保留充分重叠，防止折叠标题栏吞掉整屏交集。
    CGFloat distance = MIN(plan.start.y - plan.end.y, self.displayRect.size.height * 0.18);
    plan.end.y = plan.start.y - distance;
    self.scrolling = YES;
    NSUInteger token = self.generation;
    self.hud.statusText = @"正在滚动";
    __weak MTShellXStitchSession *weak = self;
    [self.scroller scrollWithPlan:plan duration:self.task.configSnapshot.longShotOptions.scrollDuration completion:^(BOOL completed) {
        MTShellXStitchSession *s = weak;
        if (![s mtLive] || s.generation != token || s.exporting) return;
        s.scrolling = NO;
        if (!completed || ![s mtTargetCurrent]) { [s mtRequestFinish]; return; }
        [s mtSettleThenCapture];
    }];
}
- (void)mtSettleThenCapture {
    if (![self mtLive] || self.exporting) return;
    self.settling = YES;
    self.hud.statusText = @"等待画面稳定";
    NSUInteger token = self.generation;
    __weak MTShellXStitchSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.task.configSnapshot.longShotOptions.settleDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MTShellXStitchSession *s = weak;
        if (![s mtLive] || s.generation != token || !s.settling || s.exporting) return;
        s.settling = NO;
        [s mtCapture]; // 即使已点完成，也收齐滑动后的最后一屏。
    });
}
- (void)mtRequestFinish {
    if (![self mtLive] || self.exporting) return;
    self.finishRequested = YES; self.loopRunning = NO;
    [self.hud setCaptureTitle:@"停止中" enabled:NO];
    [self.hud setFinishing:YES];
    self.hud.statusText = @"收齐当前屏后保存";
    if (!self.busy && !self.scrolling && !self.settling) [self mtExport];
}
- (void)mtExport {
    if (![self mtLive] || self.exporting || self.busy || self.scrolling || self.settling) return;
    if (![self mtFullCount]) { [self mtFail:@"没有可保存的截图内容"]; return; }
    self.exporting = YES; self.loopRunning = NO;
    [self.hud setCaptureTitle:@"截取" enabled:NO]; [self.hud setFinishing:YES];
    [self.hud setPreviewImage:nil usedPixelHeight:0]; self.lastSignature = nil;
    self.hud.statusText = @"正在拼接长图";
    NSArray<NSString *> *fulls = [self.fullPaths copy];
    NSString *directory = self.workDirectory;
    MTLongShotOptions *options = self.task.configSnapshot.longShotOptions;
    MTLongShotCancellation *cancel = self.cancellation;
    __weak MTShellXStitchSession *weak = self;
    dispatch_async(MTShellXStitchQueue(), ^{ @autoreleasepool {
        NSMutableArray<NSString *> *slices = [NSMutableArray array];
        NSData *previous = nil;
        NSInteger previousRows = 0, previousBPR = 0;
        BOOL valid = YES;
        for (NSUInteger i = 0; i < fulls.count && !cancel.cancelled; i++) { @autoreleasepool {
            UIImage *full = [UIImage imageWithContentsOfFile:fulls[i]];
            NSInteger h = full.CGImage ? CGImageGetHeight(full.CGImage) : 0;
            NSInteger cut = MIN(h - 4, (NSInteger)(h * 0.85));
            NSInteger rows = 0, w = 0, bpr = 0;
            NSData *signature = full ? MTShellXRowSignature(full, &rows, &w, &bpr) : nil;
            NSInteger shift = i == 0 ? 0 : -1;
            if (previous && signature && rows == previousRows && bpr == previousBPR)
                shift = MTShellXMatchScroll(previous.bytes, signature.bytes, bpr, rows, MAX(8, rows / 5), w);
            NSInteger added = i == 0 ? cut : (NSInteger)llround((CGFloat)shift * h / MAX(1, rows));
            if (!signature || cut < 1 || shift < 0 || added > cut) { valid = NO; break; }
            if (added > 0) {
                NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"slice_%lu.jpg", (unsigned long)slices.count]];
                if (!MTShellXWriteSlice(full, cut - added, added, path)) { valid = NO; break; }
                [slices addObject:path]; // 写盘成功后必须入列，禁止导出空列表。
            }
            previous = signature; previousRows = rows; previousBPR = bpr;
            if (i == fulls.count - 1) {
                NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"slice_%lu.jpg", (unsigned long)slices.count]];
                if (!MTShellXWriteSlice(full, cut, h - cut, path)) { valid = NO; break; }
                [slices addObject:path];
            }
        }}
        CGSize size = CGSizeZero; NSError *error = nil;
        UIImage *result = valid ? MTShellXComposeSlices(slices, [directory stringByAppendingPathComponent:@"longshot.jpg"], options.maxCanvasHeight, options.outputQuality, cancel, &size, &error) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            MTShellXStitchSession *s = weak;
            if (![s mtLive]) return;
            if (!result) { [s mtFail:error.localizedDescription ?: @"原图重叠校验或切片写盘失败"]; return; }
            MTCaptureLogInfo(@"shellx stitch exported (task %@ fulls=%lu slices=%lu size=%@)", s.taskID, (unsigned long)fulls.count, (unsigned long)slices.count, NSStringFromCGSize(size));
            id<MTLongShotSessionDelegate> delegate = s.delegate;
            [s mtTeardown:NO]; [delegate longShotSessionDidFinish:s resultImage:result];
        });
    }});
}
- (void)mtCancel {
    if (_finished) return;
    id<MTLongShotSessionDelegate> delegate = self.delegate;
    [self mtTeardown:YES]; [delegate longShotSessionDidCancel:self];
}
- (void)mtFail:(NSString *)message {
    if (_finished) return;
    MTCaptureLogWarn(@"shellx stitch failed (task %@): %@", self.taskID, message);
    id<MTLongShotSessionDelegate> delegate = self.delegate;
    [self mtTeardown:YES]; [delegate longShotSessionDidFail:self message:message];
}
- (void)teardownForExternalCancel {
    if (NSThread.isMainThread) [self mtTeardown:YES];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self mtTeardown:YES]; });
}
- (void)mtTeardown:(BOOL)remove {
    if (_finished) return;
    _finished = YES; self.generation++; self.loopRunning = NO; self.cancellation.cancelled = YES;
    [self.tickTimer invalidate]; self.tickTimer = nil;
    [self.scroller cancel]; self.scroller = nil;
    if (self.memoryObserver) [NSNotificationCenter.defaultCenter removeObserver:self.memoryObserver];
    self.memoryObserver = nil;
    if (MTShellXStitchLockSession == self) {
        atomic_fetch_add(&MTShellXStitchLockGeneration, 1); MTShellXStitchLockSession = nil;
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CFSTR("com.apple.springboard.lockstate"), NULL);
    }
    self.hud.delegate = nil; [self.window hideAndDestroyWithCompletion:nil];
    self.window = nil; self.hud = nil; self.task = nil; self.delegate = nil;
    self.lastSignature = nil; [self.fullPaths removeAllObjects];
    if (remove) {
        NSString *taskID = self.taskID;
        dispatch_async(MTShellXStitchQueue(), ^{ [MTTemporaryFileStore removeTaskDirectory:taskID]; });
    }
}
@end
