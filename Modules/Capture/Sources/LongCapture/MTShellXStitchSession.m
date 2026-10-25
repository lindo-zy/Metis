#import "MTShellXStitchSession.h"
#import "MTShellXSupport.h"
#import "MTShellXAutoAligner.h"
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

// 滑动、稳定采样、匹配、入账串行进行；失败帧不替换锚点。按真实位移调节
// 手指距离，避免惯性把预留重叠吃掉。所有重试有界，所有裁带在入账时确定。
static const CGFloat MTShellXAutoStepInitial = 0.15;
static const CGFloat MTShellXAutoStepMin = 0.04;
static const CGFloat MTShellXAutoStepMax = 0.20;
static const CGFloat MTShellXAutoStartFraction = 0.60;
static const NSTimeInterval MTShellXAutoProbeFirstGap = 0.3;
static const NSTimeInterval MTShellXAutoProbeDeferGap = 0.5;
static const NSInteger MTShellXAutoProbeMaxDeferrals = 2;
static const NSTimeInterval MTShellXAutoRecaptureDelay = 0.5;
static const CGFloat MTShellXAutoShiftBodyCap = 0.85;
static const NSInteger MTShellXBottomSameThreshold = 2;    // 连续高置信重复判到底
static const NSInteger MTShellXChromeRetryMax = 3;         // 工具栏吸收拖动的连续重试上限

static dispatch_queue_t MTShellXStitchQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.lindo.metis.capture.shellx.stitch", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

/// 自动拼接入账记录：位移与正文边界以采集时的配对匹配为准，导出只按记录
/// 裁带合并，不再从 JPEG 重新猜位移（采集通过、导出失败的一票否决即源于此）。
@interface MTShellXStitchRecord : NSObject
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic) NSInteger rows;        // 整屏帧像素高（行签名行数）
@property (nonatomic) NSInteger bodyTop;     // 正文边界（绝对行，含头不含尾）；首帧配对确认前为 -1
@property (nonatomic) NSInteger bodyBottom;
@property (nonatomic) NSInteger shiftRows;   // 与前一记录的确认位移；首帧 0
@property (nonatomic) NSInteger sliceTop;    // 入账即确定，后续配对不得改写旧帧
@end
@implementation MTShellXStitchRecord
@end

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
@property (nonatomic) BOOL loopRunning;       // 自动循环进行中
@property (nonatomic) BOOL busy;              // 一次截取/滑动在途
@property (nonatomic) BOOL finishRequested;
@property (nonatomic) BOOL exporting;
@property (nonatomic, assign, getter=isFinished) BOOL finished;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSInteger sameCount;
@property (nonatomic, strong) NSMutableArray<MTShellXStitchRecord *> *records;   // 主线程
@property (nonatomic, strong) NSData *lastSignature;
@property (nonatomic) NSInteger sigRows;
@property (nonatomic) NSInteger autoBodyTop, autoBodyBottom;   // 参照帧正文边界（-1 未确认）
@property (nonatomic, strong, nullable) NSData *lastProbeSignature;
@property (nonatomic) NSInteger probeRound;
@property (nonatomic) NSInteger recoveryAttempts;
@property (nonatomic) NSInteger chromeRetries;
@property (nonatomic) NSInteger anchorRetries;
@property (nonatomic) BOOL memoryStopped;
@property (nonatomic) CGFloat stepFraction;
@property (nonatomic) MTLongShotScrollPlan forwardPlan;
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
                     delegate:(id<MTLongShotSessionDelegate>)delegate {
    NSParameterAssert(NSThread.isMainThread);
    MTShellXStitchSession *s = [self new];
    s.task = task; s.taskID = task.taskID; s.delegate = delegate;
    s.displayRect = displayRect;
    s.target = MTLongShotFrontmostIdentifier(UIApplication.sharedApplication);
    s.provider = [MTCaptureProvider new];
    s.provider.detachesCapturedImage = YES;
    s.provider.keepsExcludedWindowsVisible = YES;
    s.cancellation = [MTLongShotCancellation new];
    task.baseImage = nil;
    s.records = [NSMutableArray array];
    s.autoBodyTop = -1; s.autoBodyBottom = -1;
    s.stepFraction = MTShellXAutoStepInitial;
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
    [s.hud setModeTitle:@"SHELLX 自动拼接"];
    [s.window showAnimated:NO becomeKey:NO];
    [s.hud setCaptureTitle:@"截取" enabled:YES];
    [s.hud setStatusText:@"点「截取」开始，到底自动保存"];
    atomic_fetch_add(&MTShellXStitchLockGeneration, 1); MTShellXStitchLockSession = s;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MTShellXStitchLockCallback,
                                    CFSTR("com.apple.springboard.lockstate"), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    __weak MTShellXStitchSession *weak = s;
    s.memoryObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weak mtMemoryWarning]; }];
    s.tickTimer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) { [weak mtTick]; }];
    [NSRunLoop.mainRunLoop addTimer:s.tickTimer forMode:NSRunLoopCommonModes];
    MTCaptureLogInfo(@"shellx auto ready (task %@ rect=%@)", s.taskID, NSStringFromCGRect(displayRect));
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
    self.memoryStopped = YES;
    self.finishRequested = YES; self.loopRunning = NO;
    [self.scroller cancel];
    if (!self.busy && !self.scrolling) { self.settling = NO; [self mtExport]; }
}
- (void)longShotHUDDidTapCapture:(UIView *)hud {
    if (![self mtLive] || self.finishRequested || self.exporting || self.terminalPause) return;
    if (self.loopRunning) { [self mtRequestFinish]; return; }
    if (self.busy || self.scrolling || self.settling) return;
    if (![self mtTargetCurrent]) { self.hud.statusText = @"请返回原 App，或点完成保存"; return; }
    if (![self mtHasMemory]) { [self mtRequestFinish]; return; }
    if (!self.workDirectory) self.workDirectory = [self.task ensureTemporaryDirectory];
    if (!self.workDirectory.length) { [self mtFail:@"临时目录创建失败"]; return; }
    if (!self.scroller) {
        MTLongShotScroller *scroller = [MTLongShotScroller new];
        if (scroller.availabilityError) { self.hud.statusText = scroller.availabilityError; return; }
        self.scroller = scroller;
    }
    self.loopRunning = YES;
    [self.hud setCaptureTitle:@"停止" enabled:YES];
    [self mtProbeThenCaptureAuto];
}
- (void)longShotHUDDidTapFinish:(UIView *)hud { [self mtRequestFinish]; }
- (void)longShotHUDDidTapCancel:(UIView *)hud { [self mtCancel]; }

#pragma mark - 稳定抓帧

- (void)mtProbeThenCaptureAuto {
    if (![self mtLive] || self.exporting || self.busy) return;
    if (!self.loopRunning && !self.finishRequested) return;
    if (self.memoryStopped || ![self mtHasMemory]) { [self mtMemoryWarning]; return; }
    self.busy = YES;
    self.probeRound = 0;
    self.lastProbeSignature = nil;
    NSUInteger token = ++self.generation;
    self.hud.statusText = @"正在截取当前屏";
    __weak MTShellXStitchSession *weak = self;
    // 整个探测+配对阶段共用一个 8s 看门狗：无回调或后台卡住也不会永远停在 busy。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MTShellXStitchSession *s = weak;
        if (![s mtLive] || s.generation != token || !s.busy) return;
        s.generation++; s.busy = NO;
        MTCaptureLogWarn(@"shellx auto probe timed out (task %@)", s.taskID);
        [s mtRequestFinish];
    });
    [self mtProbeSample:token];
}

- (void)mtProbeSample:(NSUInteger)token {
    CGSize screen = self.task.capturedScreenBounds.size;
    __weak MTShellXStitchSession *weak = self;
    @try {
        [self.provider captureExcludingWindows:@[self.window] completion:^(UIImage *image, BOOL partial, NSString *method, NSError *error) {
            MTShellXStitchSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            if (![s mtTargetCurrent]) { s.busy = NO; [s mtRequestFinish]; return; }
            if (!image.CGImage || partial) {
                s.busy = NO;
                MTCaptureLogWarn(@"shellx auto probe capture failed (task %@ method=%@ error=%@)", s.taskID, method, error.localizedDescription);
                [s mtRequestFinish]; return;
            }
            CGRect pixelRect = CGRectIntegral(MTConvertDisplayRectToPixel(s.displayRect, screen,
                CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage))));
            MTLongShotCancellation *cancel = s.cancellation;
            dispatch_async(MTShellXStitchQueue(), ^{ @autoreleasepool { @try {
                if (cancel.cancelled) return;
                CGImageRef cg = CGImageCreateWithImageInRect(image.CGImage, pixelRect);
                UIImage *frame = cg ? [UIImage imageWithCGImage:cg scale:image.scale orientation:UIImageOrientationUp] : nil;
                if (cg) CGImageRelease(cg);
                NSData *signature = frame ? MTShellXRowSignature(frame, NULL, NULL, NULL) : nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    MTShellXStitchSession *s2 = weak;
                    if (![s2 mtLive] || s2.generation != token) return;
                    [s2 mtProbeDidSample:signature frame:frame token:token];
                });
            } @catch (NSException *exception) {
                MTCaptureLogWarn(@"shellx signature exception (%@)", exception.name);
                dispatch_async(dispatch_get_main_queue(), ^{
                    MTShellXStitchSession *s2 = weak;
                    if (![s2 mtLive] || s2.generation != token) return;
                    s2.busy = NO; [s2 mtRequestFinish];
                });
            } }});
        }];
    } @catch (NSException *exception) {
        self.busy = NO;
        MTCaptureLogWarn(@"shellx auto probe exception (task %@ name=%@)", self.taskID, exception.name);
        [self mtRequestFinish];
    }
}

- (void)mtProbeDidSample:(NSData *)signature frame:(UIImage *)frame token:(NSUInteger)token {
    if (self.memoryStopped) { self.busy = NO; self.lastProbeSignature = nil; [self mtExport]; return; }
    // 20px JPEG 指纹会把不同的重复列表压成相同画面。改用原生行签名，
    // 正文静止才入账；同一份签名直接用于匹配，避免再次解码整屏位图。
    if (signature && self.lastProbeSignature && MTShellXAutoSignaturesAreStable(self.lastProbeSignature.bytes,
            self.lastProbeSignature.length / MTLongShotSigWidth, signature.bytes, signature.length / MTLongShotSigWidth)) {
        self.lastProbeSignature = nil;
        [self mtProcessAutoFrame:frame signature:signature token:token];
        return;
    }
    self.lastProbeSignature = signature;
    if (!signature || !frame.CGImage) { self.busy = NO; [self mtFail:@"抓屏帧无效"]; return; }
    if (self.probeRound > MTShellXAutoProbeMaxDeferrals) {
        MTCaptureLogWarn(@"shellx auto probe still unstable, pausing (task %@ rounds=%ld)",
                  self.taskID, (long)self.probeRound);
        self.busy = NO; self.lastProbeSignature = nil;
        if (self.finishRequested) [self mtPauseForUnconfirmedTail];
        else [self mtPauseAutoTerminal];
        return;
    }
    NSTimeInterval gap = self.probeRound == 0 ? MTShellXAutoProbeFirstGap : MTShellXAutoProbeDeferGap;
    self.probeRound++;
    __weak MTShellXStitchSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(gap * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MTShellXStitchSession *s = weak;
        if (![s mtLive] || s.generation != token || !s.busy) return;
        [s mtProbeSample:token];
    });
}

- (void)mtProcessAutoFrame:(UIImage *)frame signature:(NSData *)signature token:(NSUInteger)token {
    // 探测确认静止后才配对：签名、正文匹配与原图落盘全部在串行后台完成。
    NSString *path = [self.workDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"full_%ld.jpg", (long)self.records.count]];
    NSData *previous = self.lastSignature;
    NSInteger previousRows = self.sigRows;
    NSInteger priorTop = self.autoBodyTop, priorBottom = self.autoBodyBottom;
    BOOL first = self.records.count == 0;
    MTLongShotCancellation *cancel = self.cancellation;
    __weak MTShellXStitchSession *weak = self;
    dispatch_async(MTShellXStitchQueue(), ^{ @autoreleasepool { @try {
        if (cancel.cancelled) return;
        NSInteger rows = signature.length / MTLongShotSigWidth;
        MTShellXAutoMatchResult match = {MTShellXAutoMatchUncertain, 0, 0, -1.0, 0, 0, NO, NO, -1, -1};
        if (!first && previous)
            match = MTShellXAutoMatchFrames(previous.bytes, previousRows, signature.bytes, rows, priorTop, priorBottom);
        NSInteger fullHeight = frame.CGImage ? CGImageGetHeight(frame.CGImage) : 0;
        BOOL written = NO;
        UIImage *thumb = nil;
        if ((first || match.kind == MTShellXAutoMatchForward) && !cancel.cancelled &&
            MTShellXWriteSlice(frame, 0, fullHeight, path)) {
            written = YES;
            thumb = MTShellXThumbnail(frame, 240);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            MTShellXStitchSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            s.busy = NO; s.lastProbeSignature = nil;
            [s mtAcceptAuto:match signature:signature rows:rows path:path written:written thumb:thumb];
        });
    } @catch (NSException *exception) {
        MTCaptureLogWarn(@"shellx frame processing exception (%@)", exception.name);
        dispatch_async(dispatch_get_main_queue(), ^{
            MTShellXStitchSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            s.busy = NO; [s mtRequestFinish];
        });
    } }});
}

- (void)mtAcceptAuto:(MTShellXAutoMatchResult)match
           signature:(NSData *)signature
                rows:(NSInteger)rows
                path:(NSString *)path
             written:(BOOL)written
                thumb:(UIImage *)thumb {
    if (self.records.count == 0) {
        // 首帧：无参照可配对，直接入库；正文边界待首次配对确认后回填。
        if (!signature || !written) { [self mtFail:@"首帧处理或写盘失败"]; return; }
        MTShellXStitchRecord *record = [MTShellXStitchRecord new];
        record.filePath = path; record.rows = rows;
        record.bodyTop = -1; record.bodyBottom = -1; record.shiftRows = 0; record.sliceTop = 0;
        [self.records addObject:record];
        self.lastSignature = signature; self.sigRows = rows;
        [self.hud setSliceCount:self.records.count];
        [self.hud setPreviewImage:thumb usedPixelHeight:CGImageGetHeight(thumb.CGImage)];
        MTCaptureLogInfo(@"shellx auto first frame (task %@ rows=%ld)", self.taskID, (long)rows);
        [self mtAfterCapturedAuto];
        return;
    }
    switch (match.kind) {
        case MTShellXAutoMatchForward: {
            NSInteger bodyRows = match.bodyBottom - match.bodyTop;
            if (!signature || !written || bodyRows <= 0 || match.shiftRows <= 0 ||
                (CGFloat)match.shiftRows > (CGFloat)bodyRows * MTShellXAutoShiftBodyCap) {
                // 写盘失败或位移越界（页面跳变）：按不确定处理进恢复，不直接失败。
                MTCaptureLogWarn(@"shellx auto forward rejected (task %@ shift=%ld body=%ld written=%d)",
                          self.taskID, (long)match.shiftRows, (long)bodyRows, written);
                self.sameCount = 0;
                [self mtRecoverAuto];
                return;
            }
            // 只有首帧尚未确定接缝。其后旧帧的裁带不可被下一次配对改写，
            // 否则导航栏/底栏变化会使先前确认的内容重复或消失。
            MTShellXStitchRecord *previous = self.records.lastObject;
            if (previous.bodyBottom < 0) {
                previous.bodyTop = match.bodyTop;
                previous.bodyBottom = MTShellXAutoSeamRow(self.lastSignature.bytes, self.sigRows, match.bodyBottom);
            }
            NSInteger sliceTop = previous.bodyBottom - match.shiftRows;
            NSInteger sliceBottom = MTShellXAutoSeamRow(signature.bytes, rows, match.bodyBottom);
            if (sliceTop < match.bodyTop || sliceTop >= sliceBottom) { [self mtRecoverAuto]; return; }
            MTShellXStitchRecord *record = [MTShellXStitchRecord new];
            record.filePath = path; record.rows = rows;
            record.bodyTop = match.bodyTop; record.bodyBottom = sliceBottom;
            record.shiftRows = match.shiftRows;
            record.sliceTop = sliceTop;
            [self.records addObject:record];
            self.lastSignature = signature; self.sigRows = rows;
            self.autoBodyTop = match.bodyTop; self.autoBodyBottom = match.bodyBottom;
            self.sameCount = 0; self.recoveryAttempts = 0; self.chromeRetries = 0; self.anchorRetries = 0;
            [self mtAdaptStep:(CGFloat)match.shiftRows / (CGFloat)bodyRows];
            [self.hud setSliceCount:self.records.count];
            [self.hud setPreviewImage:thumb usedPixelHeight:thumb ? CGImageGetHeight(thumb.CGImage) : 0];
            MTCaptureLogInfo(@"shellx auto frame (task %@ count=%ld shift=%ld body=[%ld,%ld) conf=%.2f dense=%.1f)",
                      self.taskID, (long)self.records.count, (long)match.shiftRows,
                      (long)match.bodyTop, (long)match.bodyBottom, match.confidence, match.denseError);
            [self mtAfterCapturedAuto];
            return;
        }
        case MTShellXAutoMatchDuplicate:
            if (match.chromeChanged && self.chromeRetries < MTShellXChromeRetryMax) {
                // 正文静止、仅标题/地址栏等工具栏变化：本次拖动被工具栏动画吸收，
                // 没有内容位移。参照帧保持不变，直接再滚一次（标题折叠后下一次
                // 拖动会真正滚动内容）；不计入到底判定，有限重试防死循环。
                self.chromeRetries++;
                self.sameCount = 0;
                self.recoveryAttempts = 0;
                self.hud.statusText = @"页面标题折叠中，继续滚动";
                MTCaptureLogInfo(@"shellx auto chrome absorbed scroll (task %@ retry=%ld body=[%ld,%ld))",
                          self.taskID, (long)self.chromeRetries, (long)match.bodyTop, (long)match.bodyBottom);
                [self mtAfterCapturedAutoKeepCount];
                return;
            }
            if (self.recoveryAttempts > 0) {
                // 回到参照锚点不是到底：缩步重新前进；恢复链未断，再失败即暂停。
                self.sameCount = 0;
                if (++self.anchorRetries > 2) { [self mtPauseAutoTerminal]; return; }
                self.stepFraction = MIN(self.stepFraction, MTShellXAutoStepMin);
                MTCaptureLogInfo(@"shellx auto duplicate at anchor, reforward (task %@)", self.taskID);
                [self mtAfterCapturedAuto];
                return;
            }
            self.sameCount++;
            MTCaptureLogInfo(@"shellx auto duplicate (task %@ same=%ld)", self.taskID, (long)self.sameCount);
            [self mtAfterCapturedAuto];
            return;
        case MTShellXAutoMatchSizeMismatch:
            // 旋转或抓帧几何变化时，不再向旧坐标发送触摸。
            [self mtRequestFinish];
            return;
        default:
            // 不确定或反向帧不替换参照帧，进入有界恢复。
            MTCaptureLogInfo(@"shellx auto match kind=%ld (task %@ recovery=%ld conf=%.2f dense=%.1f bounds=%d diag=%ld/%ld)",
                      (long)match.kind, self.taskID, (long)self.recoveryAttempts,
                      match.confidence, match.denseError, match.boundsValid,
                      (long)match.diagBestLen, (long)match.diagChangedOutside);
            self.sameCount = 0;
            [self mtRecoverAuto];
            return;
    }
}

- (void)mtAdaptStep:(CGFloat)ratio {
    if (ratio <= 0 || !isfinite(ratio)) return;
    // 真机中惯性/标题折叠后的推进可达手指距离数倍；按实测增益直接收步，
    // 只允许逐渐增大，保留约 75% 正文供下次匹配。
    CGFloat target = self.stepFraction * 0.22 / ratio;
    self.stepFraction = MAX(MTShellXAutoStepMin, MIN(MTShellXAutoStepMax,
        MIN(target, self.stepFraction * 1.2)));
}

- (void)mtAfterCapturedAuto {
    NSInteger cap = self.task.configSnapshot.longShotOptions.maxSlices;
    if (self.finishRequested || self.records.count >= cap || self.sameCount >= MTShellXBottomSameThreshold) {
        if (self.sameCount >= MTShellXBottomSameThreshold && !self.finishRequested)
            MTCaptureLogInfo(@"shellx auto bottom reached (task %@ count=%ld)", self.taskID, (long)self.records.count);
        [self mtRequestFinish];
        return;
    }
    if (self.loopRunning) [self mtScrollAuto];
}

// 工具栏吸收拖动后的继续滚动：不计入到底判定（sameCount 不变），
// 其余收尾条件与常规路径一致。
- (void)mtAfterCapturedAutoKeepCount {
    NSInteger cap = self.task.configSnapshot.longShotOptions.maxSlices;
    if (self.finishRequested || self.records.count >= cap) { [self mtRequestFinish]; return; }
    if (self.loopRunning) [self mtScrollAuto];
}

#pragma mark - 滑动与恢复

- (BOOL)mtBuildAutoScrollPlan:(MTLongShotScrollPlan *)plan {
    // 屏幕 60% 处起滑、步长自适应（初始 15%），避开固定边栏，
    // 避开底部 Tab 栏与折叠标题；与右上 HUD 相交（小屏/区域长截图）时退回
    // 通用避让计划并按当前步长收紧。
    CGRect rect = self.displayRect;
    if (CGRectIsEmpty(rect) || rect.size.height < 100 || !plan) return NO;
    CGFloat midX = CGRectGetMidX(rect);
    CGFloat startY = CGRectGetMinY(rect) + rect.size.height * MTShellXAutoStartFraction;
    CGFloat step = rect.size.height * self.stepFraction;
    CGFloat endY = startY - step;
    CGRect band = CGRectMake(midX - 40.0, endY - 20.0, 80.0, (startY - endY) + 40.0);
    CGRect protectedRect = [self.hud convertRect:self.hud.panelFrame
                        toCoordinateSpace:self.window.screen.coordinateSpace];
    if (CGRectIsEmpty(protectedRect) || !CGRectIntersectsRect(band, protectedRect)) {
        plan->start = CGPointMake(midX, startY);
        plan->end = CGPointMake(midX, endY);
        return YES;
    }
    MTLongShotScrollPlan fallback;
    if (!MTLongShotBuildScrollPlan(self.displayRect, self.task.capturedScreenBounds, protectedRect, &fallback)) return NO;
    CGFloat distance = MIN(fallback.start.y - fallback.end.y, step);
    fallback.end.y = fallback.start.y - distance;
    *plan = fallback;
    return YES;
}

- (void)mtScrollAuto {
    if (![self mtLive] || self.exporting) return;
    if (self.finishRequested) { [self mtExport]; return; }
    if (!self.loopRunning) return;
    if (![self mtHasMemory]) { [self mtMemoryWarning]; return; }
    MTLongShotScrollPlan plan = {0};
    if (![self mtBuildAutoScrollPlan:&plan]) { [self mtRequestFinish]; return; }
    self.forwardPlan = plan;
    self.scrolling = YES;
    NSUInteger token = self.generation;
    self.hud.statusText = @"正在滚动";
    __weak MTShellXStitchSession *weak = self;
    [self.scroller scrollWithPlan:plan duration:self.task.configSnapshot.longShotOptions.scrollDuration completion:^(BOOL completed) {
        MTShellXStitchSession *s = weak;
        if (![s mtLive] || s.generation != token || s.exporting) return;
        s.scrolling = NO;
        if (!completed || ![s mtTargetCurrent]) { [s mtRequestFinish]; return; }
        [s mtSettleThenProbe];
    }];
}

- (void)mtSettleThenProbe {
    if (![self mtLive] || self.exporting) return;
    self.settling = YES;
    self.hud.statusText = @"等待画面稳定";
    NSUInteger token = self.generation;
    __weak MTShellXStitchSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.task.configSnapshot.longShotOptions.settleDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MTShellXStitchSession *s = weak;
        if (![s mtLive] || s.generation != token || !s.settling || s.exporting) return;
        s.settling = NO;
        if (s.memoryStopped) { [s mtExport]; return; }
        [s mtProbeThenCaptureAuto]; // 即使已点完成，也收齐滑动后的最后一屏。
    });
}

- (void)mtRecoverAuto {
    if (self.finishRequested) { [self mtPauseForUnconfirmedTail]; return; }
    if (self.recoveryAttempts <= 0) {
        // 第一次失败多为动画未稳/瞬时遮挡：停 0.5s 原地重抓，仍对上一确认帧匹配。
        self.recoveryAttempts = 1;
        self.hud.statusText = @"重新识别画面";
        NSUInteger token = self.generation;
        __weak MTShellXStitchSession *weak = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MTShellXAutoRecaptureDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            MTShellXStitchSession *s = weak;
            if (![s mtLive] || s.generation != token || s.exporting || s.busy ||
                s.scrolling || s.settling) return;
            if (s.finishRequested) { [s mtRequestFinish]; return; }
            [s mtProbeThenCaptureAuto];
        });
        return;
    }
    if (self.recoveryAttempts == 1) {
        // 第二次失败：有限回滑半步回到上一确认内容附近；回到锚点后缩步重新前进。
        MTLongShotScrollPlan rollback;
        if (MTLongShotBuildCorrectiveScrollPlan(self.forwardPlan, 0.5, &rollback)) {
            self.recoveryAttempts = 2;
            self.stepFraction = MIN(self.stepFraction, MTShellXAutoStepMin);
            self.scrolling = YES;
            NSUInteger token = self.generation;
            self.hud.statusText = @"正在恢复拼接重叠";
            __weak MTShellXStitchSession *weak = self;
            [self.scroller scrollWithPlan:rollback duration:self.task.configSnapshot.longShotOptions.scrollDuration completion:^(BOOL completed) {
                MTShellXStitchSession *s = weak;
                if (![s mtLive] || s.generation != token || s.exporting) return;
                s.scrolling = NO;
                if (!completed || ![s mtTargetCurrent]) { [s mtRequestFinish]; return; }
                [s mtSettleThenProbe];
            }];
            return;
        }
    }
    [self mtPauseAutoTerminal];
}

- (void)mtPauseForUnconfirmedTail {
    // 用户点完成时，未匹配的末屏不能被悄悄丢掉并报告完整成功。
    self.finishRequested = NO;
    [self.hud setFinishing:NO];
    [self mtPauseAutoTerminal];
    self.hud.statusText = @"末段未能可靠拼接，点完成保存已确认内容";
}

- (void)mtPauseAutoTerminal {
    // 持续动态画面、歧义或有界恢复耗尽时安全停止；已确认的内容仍可保存。
    self.loopRunning = NO;
    self.terminalPause = YES;
    self.hud.statusText = @"页面持续变化或无法确认重叠，点完成保存已截内容";
    [self.hud setCaptureTitle:@"截取" enabled:NO];
    MTCaptureLogWarn(@"shellx auto terminal pause (task %@ count=%ld)", self.taskID, (long)self.records.count);
    if (self.finishRequested) [self mtExport];
}

#pragma mark - 收尾

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
    if (!self.records.count) { [self mtFail:@"没有可保存的截图内容"]; return; }
    self.exporting = YES; self.loopRunning = NO;
    [self.hud setCaptureTitle:@"截取" enabled:NO]; [self.hud setFinishing:YES];
    [self.hud setPreviewImage:nil usedPixelHeight:0]; self.lastSignature = nil;
    self.hud.statusText = @"正在拼接长图";
    // 只按入账时固定的裁带合并：cur[y] 对应 prev[y + shift]。
    // 顶栏只在首帧保留，底栏只在末帧补齐，导出不再猜测位移。
    NSArray<MTShellXStitchRecord *> *records = [self.records copy];
    NSString *directory = self.workDirectory;
    MTLongShotOptions *options = self.task.configSnapshot.longShotOptions;
    MTLongShotCancellation *cancel = self.cancellation;
    __weak MTShellXStitchSession *weak = self;
    NSUInteger token = ++self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MTShellXStitchSession *s = weak;
        if ([s mtLive] && s.exporting && s.generation == token) [s mtFail:@"长图处理超时，请重试"];
    });
    dispatch_async(MTShellXStitchQueue(), ^{ @autoreleasepool { @try {
        NSMutableArray<NSString *> *slices = [NSMutableArray array];
        BOOL valid = YES;
        NSString *failure = nil;
        for (NSUInteger i = 0; i < records.count && !cancel.cancelled; i++) { @autoreleasepool {
            MTShellXStitchRecord *rec = records[i];
            MTShellXStitchRecord *prev = i > 0 ? records[i - 1] : nil;
            UIImage *full = [UIImage imageWithContentsOfFile:rec.filePath];
            NSInteger h = full.CGImage ? CGImageGetHeight(full.CGImage) : 0;
            if (!full.CGImage || h != rec.rows) { valid = NO; failure = @"原图读取失败"; break; }
            NSInteger bodyBottom = rec.bodyBottom;
            NSInteger sliceTop, sliceBottom;
            if (!prev) {
                bodyBottom = (rec.bodyBottom > 0 && rec.bodyBottom <= h) ? rec.bodyBottom : h;
                sliceTop = 0;
                sliceBottom = bodyBottom;
            } else {
                if (rec.bodyTop < 0 || rec.bodyBottom <= rec.bodyTop ||
                    prev.bodyTop < 0 || prev.bodyBottom <= prev.bodyTop ||
                    prev.bodyBottom > h || rec.bodyBottom > h) {
                    valid = NO; failure = @"正文边界记录缺失"; break;
                }
                NSInteger yNew = rec.sliceTop;
                if (yNew < 0 || yNew >= rec.bodyBottom) { valid = NO; failure = @"切片边界记录异常"; break; }
                sliceTop = yNew;
                sliceBottom = rec.bodyBottom;
            }
            if (sliceBottom > sliceTop) {
                NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"slice_%lu.jpg", (unsigned long)slices.count]];
                if (!MTShellXWriteSlice(full, sliceTop, sliceBottom - sliceTop, path)) { valid = NO; failure = @"切片写盘失败"; break; }
                [slices addObject:path];
            }
            if (i == records.count - 1 && bodyBottom < h) {
                NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"slice_%lu.jpg", (unsigned long)slices.count]];
                if (!MTShellXWriteSlice(full, bodyBottom, h - bodyBottom, path)) { valid = NO; failure = @"切片写盘失败"; break; }
                [slices addObject:path];
            }
        }}
        CGSize size = CGSizeZero; NSError *error = nil;
        UIImage *result = valid && slices.count && !cancel.cancelled
            ? MTShellXComposeSlices(slices, [directory stringByAppendingPathComponent:@"longshot.jpg"], options.maxCanvasHeight, options.outputQuality, cancel, &size, &error)
            : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            MTShellXStitchSession *s = weak;
            if (![s mtLive]) return;
            if (!result) { [s mtFail:error.localizedDescription ?: (failure ?: @"自动拼接切片生成失败")]; return; }
            MTCaptureLogInfo(@"shellx auto exported (task %@ frames=%lu slices=%lu size=%@)",
                      s.taskID, (unsigned long)records.count, (unsigned long)slices.count, NSStringFromCGSize(size));
            id<MTLongShotSessionDelegate> delegate = s.delegate;
            [s mtTeardown:NO]; [delegate longShotSessionDidFinish:s resultImage:result];
        });
    } @catch (NSException *exception) {
        MTCaptureLogWarn(@"shellx export exception (%@)", exception.name);
        dispatch_async(dispatch_get_main_queue(), ^{
            MTShellXStitchSession *s = weak;
            if ([s mtLive] && s.generation == token) [s mtFail:@"长图处理失败，请重试"];
        });
    } }});
}

- (void)mtCancel {
    if (_finished) return;
    id<MTLongShotSessionDelegate> delegate = self.delegate;
    [self mtTeardown:YES]; [delegate longShotSessionDidCancel:self];
}
- (void)mtFail:(NSString *)message {
    if (_finished) return;
    MTCaptureLogWarn(@"shellx auto failed (task %@): %@", self.taskID, message);
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
    self.lastSignature = nil; self.lastProbeSignature = nil;
    [self.records removeAllObjects];
    if (remove) {
        NSString *taskID = self.taskID;
        dispatch_async(MTShellXStitchQueue(), ^{ [MTTemporaryFileStore removeTaskDirectory:taskID]; });
    }
}
@end
