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
@property (nonatomic) BOOL busy, paused, finishRequested, skipFinal, exporting, finished, geometryPaused;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSInteger count, totalHeight, captureFailureStreak;
@property (nonatomic) UIInterfaceOrientation orientation;
@property (nonatomic) CFTimeInterval lastCapture, lastMemoryCheck, uncertainSince;
@property (nonatomic) MTOutputAction outputAction;
- (void)mtTick:(CADisplayLink *)link;
- (void)mtCaptureFinal:(BOOL)final;
- (void)mtExport;
- (void)mtPause:(NSString *)message;
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
            MTQuickScrollSession *live = weak;
            if (!live || live.finished || live.exporting) return;
            live.skipFinal = YES;
            [live mtRequestFinish:MTOutputActionSave];
        }];
    atomic_fetch_add(&MTQuickScrollLockGeneration, 1); MTQuickScrollLockSession = s;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MTQuickScrollLockCallback,
        CFSTR("com.apple.springboard.lockstate"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    MTCaptureLogInfo(@"quick scroll ready (task %@ rect=%@ source=request-local-context-exclusion systemCaptureVisible=1)", task.taskID, NSStringFromCGRect(displayRect));
    return s;
}
- (BOOL)isFinished { return _finished; }
- (BOOL)mtLive {
    return !self.finished && !self.cancellation.cancelled && self.task.currentState == MTCaptureStatePresenting;
}
- (BOOL)mtTargetCurrent {
    return MTLongShotTargetIsCurrent(UIApplication.sharedApplication, MTLongShotLockManager(), self.target);
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
    if (self.paused) return;
    if (![self mtGeometryCurrent]) {
        self.geometryPaused = YES;
        [self.hud setStatus:@"屏幕方向已变化，转回后自动继续" paused:NO];
        return;
    }
    CFTimeInterval now = link.timestamp;
    if (now - self.lastMemoryCheck > 0.5) {
        self.lastMemoryCheck = now;
        size_t available = MTLongShotAvailableMemoryBytes();
        if (available && available < MTLongShotMemoryFloorBytes()) {
            self.skipFinal = YES; [self mtRequestFinish:MTOutputActionSave]; return;
        }
    }
    // Backpressure: capture + analysis + optional strip encoding is ONE in-flight
    // operation. Busy ticks are skipped; no unbounded IOSurface/frame queue exists.
    if (!self.busy) [self mtCaptureFinal:NO];
}
- (void)mtCaptureFinal:(BOOL)final {
    if (![self mtLive] || self.exporting || self.busy || ![self mtTargetCurrent]) {
        if (final && !self.busy) [self mtExport]; return;
    }
    self.busy = YES; self.lastCapture = CACurrentMediaTime();
    NSUInteger token = ++self.generation;
    CFTimeInterval timestamp = self.lastCapture;
    __weak MTQuickScrollSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MTQuickScrollSession *s = weak;
        if (![s mtLive] || s.generation != token || !s.busy || s.exporting) return;
        // Cancel the whole session on timeout. A late worker must not mutate a store
        // while a second capture or export is using it.
        [s mtFail:@"快速截图处理超时，请重新开始"];
    });
    @try {
        [self.provider captureExcludingWindows:@[self.window] completion:^(UIImage *image, BOOL partial, NSString *method, NSError *error) {
            MTQuickScrollSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            if (![s mtGeometryCurrent]) {
                s.busy = NO; s.geometryPaused = YES;
                if (s.finishRequested) [s mtExport];
                return;
            }
            if (!image || partial || ![s mtTargetCurrent]) {
                s.busy = NO;
                s.captureFailureStreak++;
                if (!s.count && s.captureFailureStreak < 5 && !s.finishRequested)
                    [s.hud setStatus:@"正在准备页面采集…" paused:NO];
                else [s mtPause:error.localizedDescription ?: @"画面不可用，可保存已截内容"];
                if (s.finishRequested) [s mtExport];
                return;
            }
            s.captureFailureStreak = 0;
            BOOL finalFrame = final || s.finishRequested;
            CGRect rect = MTConvertDisplayRectToPixel(s.displayRect, s.task.capturedScreenBounds.size,
                CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage)));
            MTQuickScrollStore *store = s.store;
            MTLongShotCancellation *cancel = s.cancellation;
            dispatch_async(MTQuickScrollQueue(), ^{ @autoreleasepool {
                if (cancel.cancelled) return;
                NSError *failure = nil;
                MTQuickScrollResult *result = nil;
                @try {
                    result = [store consumeImage:image pixelRect:rect timestamp:timestamp final:finalFrame error:&failure];
                } @catch (NSException *exception) {
                    failure = [NSError errorWithDomain:@"com.lindo.metis.capture.quick" code:2
                        userInfo:@{NSLocalizedDescriptionKey:@"快速截图处理异常"}];
                    MTCaptureLogWarn(@"quick scroll exception (%@)", exception.name);
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    MTQuickScrollSession *live = weak;
                    if (![live mtLive] || live.generation != token) return;
                    live.busy = NO;
                    [live mtAccept:result error:failure final:finalFrame];
                });
            }});
        }];
    } @catch (NSException *exception) {
        self.busy = NO; [self mtPause:@"抓屏接口异常，可保存已截内容"];
        if (self.finishRequested) [self mtExport];
    }
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
            if (result.bottomReached && !self.finishRequested) {
                // 触底（回弹后静止）自动收尾：与自动拼装的到底自停同口径。
                MTCaptureLogInfo(@"quick scroll bottom reached, auto finishing (task %@)", self.task.taskID);
                [self.hud setStatus:@"已到底部，自动保存长截图" paused:NO];
                [self mtRequestFinish:self.task.configSnapshot.defaultResultAction];
                return;
            }
            if (!self.paused && !self.finishRequested) {
                NSString *text = self.count > 1 ? [NSString stringWithFormat:@"已截 %.1f 屏 · 蓝键保存",
                    (double)self.totalHeight / MAX(1, self.displayRect.size.height * self.task.capturedScreenScale)]
                    : @"直接滑动页面，点蓝键保存";
                [self.hud setStatus:text paused:NO];
            }
        }
    }
    if ((self.count >= self.task.configSnapshot.longShotOptions.maxSlices ||
         self.totalHeight >= self.task.configSnapshot.longShotOptions.maxCanvasHeight) && !self.finishRequested) {
        self.skipFinal = YES; [self mtRequestFinish:MTOutputActionSave]; return;
    }
    if (self.finishRequested) {
        if (final || self.skipFinal) [self mtExport];
        else [self mtCaptureFinal:YES];
    }
}
- (void)mtPause:(NSString *)message {
    self.paused = YES; [self.hud setStatus:message paused:YES];
}
- (void)quickScrollDidTogglePause {
    if (![self mtLive] || self.finishRequested || self.exporting) return;
    if (self.paused) {
        if (![self mtTargetCurrent]) { [self mtPause:@"请返回原 App 后继续"]; return; }
        self.paused = NO; self.uncertainSince = 0;
        [self.hud setStatus:@"直接滑动页面，点蓝键保存" paused:NO];
    } else [self mtPause:@"已暂停 · 点右上角继续"];
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
    [self.hud setFinishing];
    if (!self.busy) {
        if (self.skipFinal || ![self mtTargetCurrent]) [self mtExport];
        else [self mtCaptureFinal:YES];
    }
}
- (void)mtExport {
    if (![self mtLive] || self.exporting || self.busy) return;
    if (!self.count) { [self mtFail:@"尚未取得有效画面"]; return; }
    self.exporting = YES;
    [self.displayLink invalidate]; self.displayLink = nil; [self.hud setFinishing];
    // 智能输出格式：小图无损 PNG，大图分级 JPEG（规避超大 PNG 分享失败）。
    NSString *path = [[self.task ensureTemporaryDirectory]
        stringByAppendingPathComponent:[self.store smartOutputName]];
    MTQuickScrollStore *store = self.store;
    MTLongShotCancellation *cancel = self.cancellation;
    NSUInteger token = ++self.generation;
    __weak MTQuickScrollSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MTQuickScrollSession *s = weak;
        if ([s mtLive] && s.exporting && s.generation == token) [s mtFail:@"长图导出超时"];
    });
    dispatch_async(MTQuickScrollQueue(), ^{ @autoreleasepool {
        if (cancel.cancelled) return;
        NSError *error = nil;
        UIImage *image = nil;
        @try { image = [store exportToURL:[NSURL fileURLWithPath:path] error:&error]; }
        @catch (NSException *exception) { MTCaptureLogWarn(@"quick export exception (%@)", exception.name); }
        dispatch_async(dispatch_get_main_queue(), ^{
            MTQuickScrollSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            if (!image) { [s mtFail:error.localizedDescription ?: @"长图导出失败"]; return; }
            id<MTLongShotSessionDelegate> delegate = s.delegate;
            MTOutputAction action = s.outputAction;
            MTCaptureLogInfo(@"quick scroll exported (task %@ strips=%ld height=%ld)", s.task.taskID, (long)s.count, (long)s.totalHeight);
            [s mtTeardownRemovingFiles:NO];
            if ([delegate respondsToSelector:@selector(longShotSessionDidFinish:resultImage:outputAction:)])
                [delegate longShotSessionDidFinish:s resultImage:image outputAction:action];
            else [delegate longShotSessionDidFinish:s resultImage:image];
        });
    }});
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
    self.store = nil; self.provider = nil;
    if (remove) {
        NSString *taskID = self.task.taskID;
        dispatch_async(MTQuickScrollQueue(), ^{ [MTTemporaryFileStore removeTaskDirectory:taskID]; });
    }
}
@end
