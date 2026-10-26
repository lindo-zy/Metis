#import "MTQuickScrollSession.h"
#import "MTQuickScrollStore.h"
#import "../Capture/MTCaptureTask.h"
#import "../Capture/MTContextSnapshotSource.h"
#import "../Capture/MTLongShotTarget.h"
#import "../Overlay/MTCaptureWindow.h"
#import "../Overlay/MTQuickScrollHUD.h"
#import "../Common/MTCaptureLog.h"
#import "../Output/MTTemporaryFileStore.h"
#import <QuartzCore/QuartzCore.h>
#import <stdatomic.h>
#import <math.h>

static dispatch_queue_t MTQuickScrollQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.lindo.metis.quick.normalize", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

@interface MTQuickScrollCapturedFrame : NSObject
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) CFTimeInterval timestamp;
@property (nonatomic) NSUInteger sequence;
@property (nonatomic) BOOL terminal;
@end
@implementation MTQuickScrollCapturedFrame
@end

@class MTQuickScrollSession;
@interface MTQuickScrollDisplayTarget : NSObject
@property (nonatomic, weak) MTQuickScrollSession *session;
- (void)tick:(CADisplayLink *)link;
@end

@interface MTQuickScrollSession () <MTQuickScrollHUDDelegate>
@property (nonatomic, strong) MTCaptureTask *task;
@property (nonatomic, weak) id<MTLongShotSessionDelegate> delegate;
@property (nonatomic, strong) MTContextSnapshotSource *provider;
@property (nonatomic, strong) MTLongShotCancellation *cancellation;
@property (nonatomic, strong) MTQuickScrollStore *store;
@property (nonatomic, strong) MTCaptureWindow *window;
@property (nonatomic, strong) MTQuickScrollHUD *hud;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) id memoryObserver;
@property (nonatomic, copy) NSString *target;
@property (nonatomic) CGRect displayRect;
@property (nonatomic) BOOL paused, finishRequested, skipFinal, exporting, finished, geometryPaused;
@property (nonatomic) BOOL capturePending, processing, terminalRequested, terminalCaptured;
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic, strong) NSMutableArray<MTQuickScrollCapturedFrame *> *queuedFrames;
@property (nonatomic) NSUInteger captureSequence, processingSequence, backpressureSkips;
@property (nonatomic) CFTimeInterval retryAt;
@property (nonatomic) CFAbsoluteTime exportStarted;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSInteger count, totalHeight;
@property (nonatomic) UIInterfaceOrientation orientation;
@property (nonatomic) CFTimeInterval lastCapture, lastMemoryCheck, uncertainSince;
@property (nonatomic) MTOutputAction outputAction;
- (void)mtTick:(CADisplayLink *)link;
- (void)mtCaptureFinal:(BOOL)final;
- (void)mtExport;
- (void)mtPause:(NSString *)message;
- (void)quickScrollDidRequestCancel;
- (void)mtStartNextFrame;
- (void)mtMaybeFinish;
@end

@implementation MTQuickScrollDisplayTarget
- (void)tick:(CADisplayLink *)link { [self.session mtTick:link]; }
@end

static __weak MTQuickScrollSession *MTQuickScrollLockSession;
static atomic_uint_fast64_t MTQuickScrollLockGeneration;
static void MTQuickScrollLockCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                       const void *object, CFDictionaryRef userInfo) {
    uint_fast64_t generation = atomic_load(&MTQuickScrollLockGeneration);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == atomic_load(&MTQuickScrollLockGeneration)) [MTQuickScrollLockSession quickScrollDidRequestCancel];
    });
}

@implementation MTQuickScrollSession
- (instancetype)init {
    if ((self = [super init])) _queuedFrames = [NSMutableArray array];
    return self;
}
- (BOOL)busy { return self.capturePending || self.processing || self.queuedFrames.count > 0; }
+ (instancetype)startWithTask:(MTCaptureTask *)task displayRect:(CGRect)displayRect
                     delegate:(id<MTLongShotSessionDelegate>)delegate {
    NSParameterAssert(NSThread.isMainThread);
    NSString *directory = [task ensureTemporaryDirectory];
    if (!directory.length) return nil;
    MTQuickScrollSession *s = [self new];
    s.task = task; s.delegate = delegate; s.displayRect = displayRect;
    s.target = MTLongShotFrontmostIdentifier(UIApplication.sharedApplication);
    s.cancellation = [MTLongShotCancellation new];
    s.provider = [MTContextSnapshotSource new];
    s.store = [[MTQuickScrollStore alloc] initWithDirectory:directory options:task.configSnapshot.longShotOptions
        cancellation:s.cancellation scale:task.capturedScreenScale];
    task.baseImage = nil;
    s.window = [MTCaptureWindow mtCaptureWindow];
    CGRect screen = task.capturedScreenBounds;
    UIEdgeInsets safe = s.window.windowScene.keyWindow.safeAreaInsets;
    CGFloat width = MIN(166, MAX(138, screen.size.width * 0.37));
    CGFloat aspect = displayRect.size.height / MAX(1, displayRect.size.width);
    CGFloat height = MIN(screen.size.height - safe.top - safe.bottom - 20, (width - 36) * aspect + 105);
    s.window.frame = CGRectMake(CGRectGetMaxX(screen) - safe.right - width - 4,
                                CGRectGetMinY(screen) + safe.top + 8, width, MAX(180, height));
    s.orientation = s.window.windowScene.interfaceOrientation;
    s.window.windowLevel = UIWindowLevelStatusBar;
    s.window.passesTouchesOutsideHostedContent = YES;
    s.hud = [[MTQuickScrollHUD alloc] initWithFrame:s.window.bounds]; s.hud.delegate = s;
    [s.window hostContentView:s.hud];
    s.window.rootViewController.view.frame = s.window.bounds; s.hud.frame = s.window.bounds;
    [s.window showAnimated:NO becomeKey:NO];
    MTQuickScrollDisplayTarget *proxy = [MTQuickScrollDisplayTarget new]; proxy.session = s;
    s.displayLink = [CADisplayLink displayLinkWithTarget:proxy selector:@selector(tick:)];
    s.displayLink.preferredFramesPerSecond = 0;
    [s.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    __weak MTQuickScrollSession *weak = s;
    s.memoryObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [weak mtHandleMemoryWarning];
        }];
    atomic_fetch_add(&MTQuickScrollLockGeneration, 1); MTQuickScrollLockSession = s;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MTQuickScrollLockCallback,
        CFSTR("com.apple.springboard.lockstate"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    MTCaptureLogInfo(@"quick scroll ready (task %@ rect=%@ source=request-local-context-exclusion systemCaptureVisible=1)", task.taskID, NSStringFromCGRect(displayRect));
    return s;
}
- (void)mtHandleMemoryWarning {
    if (![self mtLive] || self.exporting) return;
    [self.queuedFrames removeAllObjects];
    [self mtPause:@"内存紧张，等待恢复或点蓝键保存"];
    if (self.finishRequested) self.skipFinal = YES;
    [self mtMaybeFinish];
}
- (BOOL)isFinished { return _finished; }
- (BOOL)mtLive {
    return !self.finished && !self.cancellation.cancelled && self.task.currentState == MTCaptureStatePresenting;
}
- (BOOL)mtTargetCurrent {
    return MTLongShotTargetIsCurrent(UIApplication.sharedApplication, MTLongShotLockManager(), self.target);
}
- (NSUInteger)mtNativeFrameLimit {
    double pixels = self.task.capturedScreenBounds.size.width * self.task.capturedScreenBounds.size.height *
        self.task.capturedScreenScale * self.task.capturedScreenScale;
    return pixels > 4000000 ? 1 : 2;
}
- (BOOL)mtGeometryCurrent {
    CGSize current = UIScreen.mainScreen.bounds.size;
    CGSize baseline = self.task.capturedScreenBounds.size;
    UIInterfaceOrientation orientation = self.window.windowScene.interfaceOrientation;
    return fabs(current.width - baseline.width) < 0.5 && fabs(current.height - baseline.height) < 0.5 &&
        (self.orientation == UIInterfaceOrientationUnknown || orientation == self.orientation);
}
- (void)mtTick:(CADisplayLink *)link {
    if (![self mtLive] || self.exporting || self.finishRequested) return;
    if (![self mtTargetCurrent]) {
        [self mtPause:@"已离开原 App，可保存已截内容"]; return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (self.paused && now < self.retryAt) return;
    self.paused = NO;
    if (![self mtGeometryCurrent]) {
        self.geometryPaused = YES;
        [self.hud setStatus:@"屏幕方向已变化，转回后自动继续" paused:NO]; return;
    }
    if (now - self.lastMemoryCheck > 0.5) {
        self.lastMemoryCheck = now;
        size_t available = MTLongShotAvailableMemoryBytes();
        double pixels = self.task.capturedScreenBounds.size.width * self.task.capturedScreenBounds.size.height *
            self.task.capturedScreenScale * self.task.capturedScreenScale;
        size_t reserve = MAX((size_t)(48ull * 1024 * 1024), (size_t)(pixels * 10) + 24ull * 1024 * 1024);
        if (available && available < reserve) {
            [self mtPause:@"内存紧张，等待恢复或点蓝键保存"]; return;
        }
    }
    // Two native ingress frames at most, including the frame being analyzed.
    // Rendering can overlap normalization/spool; memory never grows with length.
    if (!self.capturePending && self.queuedFrames.count + (self.processing ? 1 : 0) < [self mtNativeFrameLimit])
        [self mtCaptureFinal:NO];
    else self.backpressureSkips++;
}
- (void)mtCaptureFinal:(BOOL)final {
    if (![self mtLive] || self.exporting || self.capturePending || ![self mtTargetCurrent]) {
        if (final && !self.busy) [self mtExport]; return;
    }
    if (!final && self.queuedFrames.count + (self.processing ? 1 : 0) >= [self mtNativeFrameLimit]) return;
    self.capturePending = YES;
    if (final) self.terminalRequested = YES;
    NSUInteger token = self.generation, sequence = ++self.captureSequence;
    self.lastCapture = CACurrentMediaTime();
    __weak MTQuickScrollSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MTQuickScrollSession *s = weak;
        if ([s mtLive] && s.generation == token && s.capturePending && s.captureSequence == sequence)
            [s mtFail:@"快速截图采集超时，请重新开始"];
    });
    @try {
        [self.provider captureExcludingWindows:@[self.window] completion:^(UIImage *image, BOOL partial, NSString *method, NSError *error) {
            MTQuickScrollSession *s = weak;
            if (![s mtLive] || s.generation != token || s.captureSequence != sequence) return;
            s.capturePending = NO;
            if (s.finishRequested && s.skipFinal) {
                if (final) s.terminalCaptured = YES;
                [s mtMaybeFinish]; return;
            }
            if (![s mtGeometryCurrent] || ![s mtTargetCurrent] || !image || partial) {
                if (final) s.terminalCaptured = YES;
                [s mtPause:error.localizedDescription ?: @"画面暂不可用，返回原方向或原 App 后继续"];
                [s mtStartNextFrame]; [s mtMaybeFinish]; return;
            }
            MTQuickScrollCapturedFrame *frame = [MTQuickScrollCapturedFrame new];
            frame.image = image; frame.timestamp = CACurrentMediaTime();
            frame.sequence = sequence; frame.terminal = final;
            [s.queuedFrames addObject:frame];
            [s mtStartNextFrame];
        }];
    } @catch (NSException *exception) {
        self.capturePending = NO;
        if (final) self.terminalCaptured = YES;
        [self mtPause:@"抓屏接口异常，可点蓝键保存已截内容"]; [self mtMaybeFinish];
    }
}
- (void)mtStartNextFrame {
    if (![self mtLive] || self.processing || self.exporting) return;
    if (!self.queuedFrames.count) { [self mtMaybeFinish]; return; }
    MTQuickScrollCapturedFrame *frame = self.queuedFrames.firstObject;
    [self.queuedFrames removeObjectAtIndex:0];
    self.processing = YES; self.processingSequence = frame.sequence;
    NSUInteger token = self.generation;
    CGRect rect = MTConvertDisplayRectToPixel(self.displayRect, self.task.capturedScreenBounds.size,
        CGSizeMake(CGImageGetWidth(frame.image.CGImage), CGImageGetHeight(frame.image.CGImage)));
    MTQuickScrollStore *store = self.store;
    MTLongShotCancellation *cancel = self.cancellation;
    __weak MTQuickScrollSession *weak = self;
    NSUInteger sequence = frame.sequence;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MTQuickScrollSession *s = weak;
        if ([s mtLive] && s.generation == token && s.processing && s.processingSequence == sequence)
            [s mtFail:@"快速截图处理超时，请重新开始"];
    });
    dispatch_async(MTQuickScrollQueue(), ^{ @autoreleasepool {
        if (cancel.cancelled) return;
        NSError *failure = nil;
        MTQuickScrollResult *result = nil;
        @try {
            result = [store consumeImage:frame.image pixelRect:rect timestamp:frame.timestamp final:frame.terminal error:&failure];
        } @catch (NSException *exception) {
            failure = [NSError errorWithDomain:@"com.lindo.metis.capture.quick" code:2
                userInfo:@{NSLocalizedDescriptionKey:@"快速截图处理异常，可保存已截内容"}];
            MTCaptureLogWarn(@"quick scroll processing exception (%@)", exception.name);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            MTQuickScrollSession *s = weak;
            if (![s mtLive] || s.generation != token || s.processingSequence != frame.sequence) return;
            s.processing = NO;
            if (frame.terminal) s.terminalCaptured = YES;
            [s mtAccept:result error:failure final:frame.terminal];
            [s mtStartNextFrame];
        });
    }});
}
- (void)mtMaybeFinish {
    if (!self.finishRequested || self.exporting || self.busy || ![self mtLive]) return;
    if (self.skipFinal || self.terminalCaptured || ![self mtTargetCurrent] || ![self mtGeometryCurrent]) [self mtExport];
    else if (!self.terminalRequested) [self mtCaptureFinal:YES];
}
- (void)mtAccept:(MTQuickScrollResult *)result error:(NSError *)error final:(BOOL)final {
    if (!result) {
        [self mtPause:error.localizedDescription ?: @"画面处理失败，可保存已截内容"];
    } else {
        self.count = result.count; self.totalHeight = result.totalHeight;
        if (result.preview) [self.hud setPreviewImage:result.preview];
        if (result.geometryMismatch) {
            // 旋转/几何变化：不暂停采集，转回原方向自动恢复；已确认内容不受影响。
            self.uncertainSince = 0; self.geometryPaused = YES;
            if (!self.paused && !self.finishRequested)
                [self.hud setStatus:@"屏幕方向已变化，转回后自动继续" paused:NO];
        } else if (result.match.kind == MTQuickScrollUncertain) {
            if (!self.uncertainSince) self.uncertainSince = CACurrentMediaTime();
            CFTimeInterval elapsed = CACurrentMediaTime() - self.uncertainSince;
            if (elapsed >= 0.8) {
                // Continuity loss keeps observing the page. Rolling back into the
                // last reliable reference recovers without an extra resume tap.
                [self.hud setStatus:@"未找到重叠，请稍回滑以继续" paused:NO];
            } else if (!self.paused && !self.finishRequested) {
                // Keep observing while showing a continuity warning, allowing rollback recovery.
                [self.hud setStatus:elapsed >= 0.35 ? @"滚动过快，请稍慢或稍微回滑"
                                                   : @"匹配中，请慢滑或稍微回滑"
                                                  paused:self.paused];
            }
            if (final) MTCaptureLogWarn(@"quick scroll unconfirmed tail omitted (task %@)", self.task.taskID);
        } else {
            self.uncertainSince = 0;
            if (self.geometryPaused) self.geometryPaused = NO;
            if (!self.paused && !self.finishRequested) {
                NSString *text = self.count > 1 ? [NSString stringWithFormat:@"已截 %.1f 屏 · 蓝键保存",
                    (double)self.totalHeight / MAX(1, self.displayRect.size.height * self.task.capturedScreenScale)]
                    : @"直接滑动页面，点蓝键保存";
                [self.hud setStatus:text paused:NO];
            }
        }
    }
    // Manual capture ends only through copy/save. Export height and old slice
    // preferences are never capture limits; a short rebound is not end-of-page.
    [self mtMaybeFinish];
}
- (void)mtPause:(NSString *)message {
    self.paused = YES; self.retryAt = CACurrentMediaTime() + 0.5;
    [self.hud setStatus:message paused:NO];
}
- (void)quickScrollDidDragBy:(CGPoint)translation {
    CGRect rect = self.window.frame;
    rect.origin.x += translation.x; rect.origin.y += translation.y;
    CGRect screen = self.task.capturedScreenBounds;
    UIEdgeInsets safe = self.window.windowScene.keyWindow.safeAreaInsets;
    rect.origin.x = MAX(CGRectGetMinX(screen), MIN(rect.origin.x, CGRectGetMaxX(screen) - rect.size.width));
    rect.origin.y = MAX(CGRectGetMinY(screen) + safe.top,
        MIN(rect.origin.y, CGRectGetMaxY(screen) - safe.bottom - rect.size.height));
    self.window.frame = rect;
}
- (void)quickScrollDidRequestCopy { [self mtRequestFinish:MTOutputActionCopy]; }
- (void)quickScrollDidRequestSave { [self mtRequestFinish:MTOutputActionSave]; }
- (void)mtRequestFinish:(MTOutputAction)action {
    if (![self mtLive] || self.finishRequested || self.exporting) return;
    self.finishRequested = YES; self.outputAction = action;
    [self.displayLink invalidate]; self.displayLink = nil;
    if (self.paused) self.skipFinal = YES;
    [self.hud setFinishing]; [self mtMaybeFinish];
}
- (void)mtExport {
    if (![self mtLive] || self.exporting || self.busy) return;
    if (!self.count) { [self mtFail:@"尚未取得有效画面"]; return; }
    self.exporting = YES;
    self.exportStarted = CFAbsoluteTimeGetCurrent();
    [self.displayLink invalidate]; self.displayLink = nil; [self.hud setFinishing];
    // Row-streamed PNG: full native resolution without allocating a tall canvas.
    NSString *path = [[self.task ensureTemporaryDirectory]
        stringByAppendingPathComponent:[self.store smartOutputName]];
    MTQuickScrollStore *store = self.store;
    MTLongShotCancellation *cancel = self.cancellation;
    NSUInteger token = ++self.generation;
    __weak MTQuickScrollSession *weak = self;
    [self mtWatchExport:token];
    dispatch_async(MTQuickScrollQueue(), ^{ @autoreleasepool {
        if (cancel.cancelled) return;
        NSError *error = nil;
        UIImage *image = nil;
        @try { image = [store exportToURL:[NSURL fileURLWithPath:path] error:&error]; }
        @catch (NSException *exception) { MTCaptureLogWarn(@"quick export exception (%@)", exception.name); }
        dispatch_async(dispatch_get_main_queue(), ^{
            MTQuickScrollSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            if (!image) {
                // The committed RGB ledger survives export errors. Keep only
                // copy/save retry active; a committed footer cannot resume capture.
                s.exporting = NO; s.finishRequested = NO; s.skipFinal = YES; s.paused = YES;
                [s.hud setRetryMessage:@"导出失败，腾出空间后点复制或保存重试"];
                MTCaptureLogWarn(@"quick scroll export deferred (task %@ reason=%@)", s.task.taskID, error.localizedDescription);
                return;
            }
            id<MTLongShotSessionDelegate> delegate = s.delegate;
            MTOutputAction action = s.outputAction;
            MTCaptureLogInfo(@"quick scroll exported (task %@ strips=%ld height=%ld captures=%lu backpressure=%lu)", s.task.taskID, (long)s.count, (long)s.totalHeight, (unsigned long)s.captureSequence, (unsigned long)s.backpressureSkips);
            [s mtTeardownRemovingFiles:NO];
            if ([delegate respondsToSelector:@selector(longShotSessionDidFinish:resultImage:outputAction:)])
                [delegate longShotSessionDidFinish:s resultImage:image outputAction:action];
            else [delegate longShotSessionDidFinish:s resultImage:image];
        });
    }});
}
- (void)mtWatchExport:(NSUInteger)token {
    __weak MTQuickScrollSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MTQuickScrollSession *s = weak;
        if (![s mtLive] || !s.exporting || s.generation != token) return;
        CFAbsoluteTime activity = MAX(s.exportStarted, s.store.exportProgressTime);
        if (CFAbsoluteTimeGetCurrent() - activity > 30) [s mtFail:@"长图导出长时间无进展"];
        else [s mtWatchExport:token];
    });
}
- (void)mtFail:(NSString *)message {
    if (self.finished) return;
    id<MTLongShotSessionDelegate> delegate = self.delegate;
    [self mtTeardownRemovingFiles:YES];
    [delegate longShotSessionDidFail:self message:message];
}
- (void)quickScrollDidRequestCancel {
    if (self.finished) return;
    id<MTLongShotSessionDelegate> delegate = self.delegate;
    [self mtTeardownRemovingFiles:YES]; [delegate longShotSessionDidCancel:self];
}
- (void)teardownForExternalCancel { [self mtTeardownRemovingFiles:YES]; }
- (void)mtTeardownRemovingFiles:(BOOL)remove {
    if (self.finished) return;
    self.finished = YES; self.generation++; self.cancellation.cancelled = YES;
    [self.displayLink invalidate]; self.displayLink = nil;
    // Cancel pending request-local snapshots before destroying the control window.
    [self.provider invalidate];
    if (self.memoryObserver) [NSNotificationCenter.defaultCenter removeObserver:self.memoryObserver];
    self.memoryObserver = nil;
    if (MTQuickScrollLockSession == self) {
        atomic_fetch_add(&MTQuickScrollLockGeneration, 1); MTQuickScrollLockSession = nil;
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            CFSTR("com.apple.springboard.lockstate"), NULL);
    }
    self.hud.delegate = nil; [self.window hideAndDestroyWithCompletion:nil]; self.window = nil; self.hud = nil;
    [self.queuedFrames removeAllObjects];
    self.store = nil; self.provider = nil;
    if (remove) {
        NSString *taskID = self.task.taskID;
        dispatch_async(MTQuickScrollQueue(), ^{ [MTTemporaryFileStore removeTaskDirectory:taskID]; });
    }
}
@end
