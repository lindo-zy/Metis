#import "MTQuickScrollSession.h"
#import "MTQuickScrollStore.h"
#import "../Capture/MTCaptureTask.h"
#import "../Capture/MTCaptureProvider.h"
#import "../Capture/MTLongShotTarget.h"
#import "../Overlay/MTCaptureWindow.h"
#import "../Overlay/MTQuickScrollHUD.h"
#import "../Common/MTCaptureLog.h"
#import "../Output/MTTemporaryFileStore.h"
#import <QuartzCore/QuartzCore.h>
#import <stdatomic.h>

static dispatch_queue_t MTQuickScrollQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.lindo.metis.capture.quick", DISPATCH_QUEUE_SERIAL); });
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
@property (nonatomic, strong) MTCaptureProvider *provider;
@property (nonatomic, strong) MTLongShotCancellation *cancellation;
@property (nonatomic, strong) MTQuickScrollStore *store;
@property (nonatomic, strong) MTCaptureWindow *window;
@property (nonatomic, strong) MTQuickScrollHUD *hud;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) id memoryObserver;
@property (nonatomic, copy) NSString *target;
@property (nonatomic) CGRect displayRect;
@property (nonatomic) BOOL busy, paused, finishRequested, skipFinal, exporting, finished;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSInteger count, totalHeight;
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
    s.provider = [MTCaptureProvider new];
    s.provider.keepsExcludedWindowsVisible = YES;
    s.provider.detachesCapturedImage = YES;
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
    s.window.windowLevel = UIWindowLevelStatusBar;
    s.window.passesTouchesOutsideHostedContent = YES;
    s.hud = [[MTQuickScrollHUD alloc] initWithFrame:s.window.bounds]; s.hud.delegate = s;
    [s.window hostContentView:s.hud];
    s.window.rootViewController.view.frame = s.window.bounds; s.hud.frame = s.window.bounds;
    [s.window showAnimated:NO becomeKey:NO];
    MTQuickScrollDisplayTarget *proxy = [MTQuickScrollDisplayTarget new]; proxy.session = s;
    s.displayLink = [CADisplayLink displayLinkWithTarget:proxy selector:@selector(tick:)];
    s.displayLink.preferredFramesPerSecond = 30;
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
    MTCaptureLogInfo(@"quick scroll ready (task %@ rect=%@)", task.taskID, NSStringFromCGRect(displayRect));
    return s;
}
- (BOOL)isFinished { return _finished; }
- (BOOL)mtLive {
    return !self.finished && !self.cancellation.cancelled && self.task.currentState == MTCaptureStatePresenting;
}
- (BOOL)mtTargetCurrent {
    return MTLongShotTargetIsCurrent(UIApplication.sharedApplication, MTLongShotLockManager(), self.target);
}
- (void)mtTick:(CADisplayLink *)link {
    if (![self mtLive] || self.exporting || self.finishRequested) return;
    if (![self mtTargetCurrent]) {
        [self mtPause:@"已离开原 App，可保存已截内容"]; return;
    }
    if (self.paused) return;
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
            if (!image || partial || ![s mtTargetCurrent]) {
                s.busy = NO;
                [s mtPause:error.localizedDescription ?: @"画面不可用，可保存已截内容"];
                if (s.finishRequested) [s mtExport];
                return;
            }
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
        if (result.match.kind == MTQuickScrollUncertain) {
            if (!self.uncertainSince) self.uncertainSince = CACurrentMediaTime();
            [self.hud setStatus:@"匹配中，请慢滑或稍微回滑" paused:self.paused];
            if (CACurrentMediaTime() - self.uncertainSince >= 0.8)
                [self mtPause:@"未找到重叠，稍回滑后点继续"];
            if (final) MTCaptureLogWarn(@"quick scroll unconfirmed tail omitted (task %@)", self.task.taskID);
        } else {
            self.uncertainSince = 0;
            if (!self.paused && !self.finishRequested) {
                NSString *text = self.count > 1 ? [NSString stringWithFormat:@"已截 %.1f 屏 · 蓝键保存",
                    (double)self.totalHeight / MAX(1, self.displayRect.size.height * self.task.capturedScreenScale)]
                    : @"直接滑动页面，点蓝键保存";
                [self.hud setStatus:text paused:NO];
            }
        }
    }
    if (self.count >= self.task.configSnapshot.longShotOptions.maxSlices && !self.finishRequested) {
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
    NSString *path = [[self.task ensureTemporaryDirectory] stringByAppendingPathComponent:@"longshot.jpg"];
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
