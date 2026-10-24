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
static const double MTShellXFullJPEGQuality = 0.92;
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
@property (nonatomic) BOOL stopAfterShot;     // 用户要求当前屏截完即收
@property (nonatomic) BOOL busy;              // 一次截取/滑动在途
@property (nonatomic) BOOL finishRequested;
@property (nonatomic) BOOL exporting;
@property (nonatomic, assign, getter=isFinished) BOOL finished;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSInteger sameCount;
@property (nonatomic) NSMutableArray<NSString *> *fullPaths;   // objc_sync 保护
@property (nonatomic) NSMutableArray<NSData *> *rowSigs;       // objc_sync 保护
@property (nonatomic) NSInteger sigRows;
@property (nonatomic) NSInteger sigStripWidth;
@property (nonatomic) NSInteger sigBytesPerRow;
@property (nonatomic) CGFloat baseScale;
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
    s.rowSigs = [NSMutableArray array];
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

- (NSInteger)mtFullCount {
    @synchronized(self.fullPaths) { return (NSInteger)self.fullPaths.count; }
}

#pragma mark - 生命周期

- (void)mtTick {
    if (![self mtLive] || self.exporting) return;
    if (![self mtTargetCurrent]) {
        if (self.automatic && (self.loopRunning || self.busy)) {
            [self.hud setStatusText:@"前台 App 已变化\n正在保存"];
            [self mtRequestFinish];
        } else if (!self.automatic && (self.loopRunning || self.busy)) {
            self.loopRunning = NO;
            self.hud.statusText = @"前台 App 已变化\n点完成保存";
        }
        return;
    }
}

- (void)mtMemoryWarning {
    if (![self mtLive]) return;
    [self.hud setPreviewImage:nil usedPixelHeight:0];
    if (self.exporting) return;
    [self.hud setStatusText:@"内存紧张\n保存已截内容"];
    [self mtRequestFinish];
    MTCaptureLogWarn(@"shellx stitch memory stop (task %@ fulls=%lu)",
              self.taskID, (unsigned long)[self mtFullCount]);
}

#pragma mark - HUD

- (void)longShotHUDDidTapCapture:(UIView *)hud {
    if (![self mtLive] || self.finishRequested || self.exporting) return;
    if (self.automatic && self.loopRunning) {
        // SHELLX autoStopAfterShot：当前屏截完即收尾。
        self.stopAfterShot = YES;
        [self.hud setCaptureTitle:@"停止中" enabled:NO];
        self.hud.statusText = @"当前屏截取完成后保存";
        return;
    }
    if (self.busy) return;
    if (![self mtTargetCurrent]) { self.hud.statusText = @"请返回原 App\n点完成保存"; return; }
    if (![self mtHasMemory]) {
        [self.hud setStatusText:@"内存紧张\n保存已截内容"];
        [self mtRequestFinish];
        return;
    }
    if (!self.workDirectory) {
        NSString *directory = [self.task ensureTemporaryDirectory];
        if (!directory.length) { [self mtFail:@"临时目录创建失败"]; return; }
        self.workDirectory = directory;
    }
    if (self.automatic && !self.scroller) {
        self.scroller = [MTLongShotScroller new];
        if (self.scroller.availabilityError) {
            self.hud.statusText = self.scroller.availabilityError;
            MTCaptureLogWarn(@"shellx stitch scroller unavailable (task %@): %@",
                      self.taskID, self.scroller.availabilityError);
            return;
        }
    }
    self.loopRunning = YES;
    [self mtCapture];
}

- (void)longShotHUDDidTapFinish:(UIView *)hud {
    if (![self mtLive] || self.exporting) return;
    if ((self.loopRunning || self.busy) && !self.finishRequested) {
        // 自动循环中：等当前屏收齐再收尾；手动：当前帧处理完再收尾。
        self.finishRequested = YES;
        if (self.automatic) self.stopAfterShot = YES;
        self.hud.statusText = @"收齐当前屏后保存";
        return;
    }
    [self mtExport];
}

- (void)longShotHUDDidTapCancel:(UIView *)hud { [self mtCancel]; }

#pragma mark - 截取

- (void)mtCapture {
    if (![self mtLive] || self.busy || self.exporting || self.finished) return;
    NSInteger count = [self mtFullCount];
    if (count >= self.task.configSnapshot.longShotOptions.maxSlices) {
        MTCaptureLogInfo(@"shellx stitch full cap (task %@ count=%ld)", self.taskID, (long)count);
        [self mtRequestFinish];
        return;
    }
    self.busy = YES;
    NSUInteger token = ++self.generation;
    __weak MTShellXStitchSession *weak = self;
    @try {
        [self.provider captureExcludingWindows:@[self.window] completion:^(UIImage *image, BOOL partial,
                                                                          NSString *method, NSError *error) {
            MTShellXStitchSession *s = weak;
            if (![s mtLive] || s.generation != token) return;
            if (!image || partial) {
                s.busy = NO;
                s.hud.statusText = @"抓屏失败";
                MTCaptureLogWarn(@"shellx stitch capture failed (task %@ method=%@ error=%@)",
                          s.taskID, method, error.localizedDescription);
                if (s.automatic) [s mtFinishAfterDelay:0.12];
                else if (s.finishRequested) [s mtExport];
                return;
            }
            [s mtHandleCaptured:image token:token];
        }];
    } @catch (__unused NSException *exception) {
        self.busy = NO;
        MTCaptureLogWarn(@"shellx stitch capture exception (task %@)", self.taskID);
        if (self.automatic) [self mtFinishAfterDelay:0.12];
    }
}

- (void)mtHandleCaptured:(UIImage *)image token:(NSUInteger)token {
    CGRect pixelRect = MTConvertDisplayRectToPixel(self.displayRect, self.task.capturedScreenBounds.size,
                            CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage)));
    pixelRect = CGRectIntegral(pixelRect);
    if (CGRectIsEmpty(pixelRect)) { self.busy = NO; [self mtFail:@"采集区域无效"]; return; }
    CGImageRef croppedRef = CGImageCreateWithImageInRect(image.CGImage, pixelRect);
    if (!croppedRef) { self.busy = NO; [self mtFail:@"帧裁剪失败"]; return; }
    CGFloat scale = image.scale;
    UIImage *frame = [UIImage imageWithCGImage:croppedRef scale:scale orientation:image.imageOrientation];
    CGImageRelease(croppedRef);
    NSInteger index = [self mtFullCount];
    __weak MTShellXStitchSession *weak = self;
    dispatch_async(MTShellXStitchQueue(), ^{
        @autoreleasepool {
            NSString *path = [self.workDirectory stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"full_%ld.jpg", (long)index]];
            NSData *jpeg = UIImageJPEGRepresentation(frame, MTShellXFullJPEGQuality);
            BOOL saved = jpeg && [jpeg writeToFile:path atomically:YES];
            NSInteger rows = 0, stripWidth = 0, bytesPerRow = 0;
            NSData *signature = saved ? MTShellXRowSignature(frame, &rows, &stripWidth, &bytesPerRow) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                MTShellXStitchSession *s = weak;
                if (![s mtLive] || s.generation != token) return;
                if (!saved) {
                    s.busy = NO;
                    s.hud.statusText = @"原图写盘失败";
                    if (s.automatic) [s mtFinishAfterDelay:0.12];
                    return;
                }
                @synchronized(s.fullPaths) { [s.fullPaths addObject:path]; }
                if (signature && rows >= 16 && stripWidth >= 16) {
                    if (s.sigRows == 0) {
                        s.sigRows = rows; s.sigStripWidth = stripWidth; s.sigBytesPerRow = bytesPerRow;
                        s.baseScale = scale;
                    }
                    if (rows == s.sigRows && stripWidth == s.sigStripWidth) {
                        @synchronized(s.rowSigs) { [s.rowSigs addObject:signature]; }
                    }
                }
                [s.hud setSliceCount:[s mtFullCount]];
                [s mtUpdatePreview:frame];
                s.busy = NO;
                [s mtAfterCaptured];
            });
        }
    });
}

/// 一屏入库后的分流：手动等待下一次截取；自动做到底判定并继续循环。
- (void)mtAfterCaptured {
    NSInteger count = [self mtFullCount];
    if (self.automatic) {
        NSInteger sigCount = 0;
        @synchronized(self.rowSigs) { sigCount = (NSInteger)self.rowSigs.count; }
        BOOL same = NO;
        if (sigCount >= 2) {
            NSData *previous, *current;
            @synchronized(self.rowSigs) {
                previous = self.rowSigs[sigCount - 2];
                current = self.rowSigs[sigCount - 1];
            }
            same = [previous isEqualToData:current];
        }
        self.sameCount = same ? self.sameCount + 1 : 0;
        MTCaptureLogInfo(@"shellx stitch auto check (task %@ count=%ld same=%d sameCount=%ld)",
                  self.taskID, (long)count, same, (long)self.sameCount);
        if (self.sameCount >= MTShellXBottomSameThreshold || self.finishRequested || self.stopAfterShot) {
            [self mtExport];
            return;
        }
        self.hud.statusText = [NSString stringWithFormat:@"已截 %ld 屏\n滚动到下一段", (long)count];
        [self mtScroll];
        return;
    }
    // 手动模式：截完即恢复待命。
    self.hud.statusText = [NSString stringWithFormat:@"已截 %ld 屏\n继续截取或点完成", (long)count];
    if (self.finishRequested) [self mtExport];
}

#pragma mark - 自动滑动

- (void)mtScroll {
    if (![self mtLive] || !self.automatic || self.finishRequested || self.exporting) return;
    MTLongShotScrollPlan plan;
    if (!MTLongShotBuildScrollPlan(self.displayRect, self.task.capturedScreenBounds, self.hud.panelFrame, &plan)) {
        self.hud.statusText = @"选区无法短滑\n点完成保存";
        [self mtFinishAfterDelay:0.0];
        return;
    }
    [self.hud setCaptureTitle:@"停止" enabled:YES];
    [self.hud setStatusText:@"正在滚动"];
    __weak MTShellXStitchSession *weak = self;
    [self.scroller scrollWithPlan:plan duration:self.task.configSnapshot.longShotOptions.scrollDuration
                       completion:^(BOOL completed) {
        MTShellXStitchSession *s = weak;
        if (![s mtLive]) return;
        if (!completed) {
            s.hud.statusText = @"滑动失败\n正在保存";
            [s mtFinishAfterDelay:0.12];
            return;
        }
        [s mtSettleThenCapture];
    }];
}

- (void)mtSettleThenCapture {
    if (![self mtLive] || self.finishRequested || self.exporting) return;
    [self.hud setStatusText:@"等待画面稳定"];
    __weak MTShellXStitchSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(self.task.configSnapshot.longShotOptions.settleDuration * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        MTShellXStitchSession *s = weak;
        if (![s mtLive] || s.finishRequested || s.exporting) return;
        [s mtCapture];
    });
}

- (void)mtFinishAfterDelay:(NSTimeInterval)delay {
    if (delay <= 0) { [self mtRequestFinish]; return; }
    __weak MTShellXStitchSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [weak mtRequestFinish]; });
}

- (void)mtRequestFinish {
    if (![self mtLive] || self.exporting || self.finished) return;
    self.finishRequested = YES;
    self.loopRunning = NO;
    [self.hud setCaptureTitle:@"截取" enabled:NO];
    if (!self.busy) [self mtExport];
    // busy 时由在途屏的 mtAfterCaptured 收尾，此处不重复导出。
}

#pragma mark - 收尾重拼

- (void)mtExport {
    if (![self mtLive] || self.exporting || self.finished) return;
    if (![self mtFullCount]) { [self mtFail:@"没有可保存的截图内容"]; return; }
    self.exporting = YES;
    [self.hud setCaptureTitle:@"截取" enabled:NO];
    self.hud.statusText = @"正在按行签名重拼";
    NSArray<NSString *> *fulls = nil;
    NSArray<NSData *> *sigs = nil;
    @synchronized(self.fullPaths) { fulls = [self.fullPaths copy]; }
    @synchronized(self.rowSigs) { sigs = [self.rowSigs copy]; }
    NSInteger sigRows = self.sigRows, sigWidth = self.sigStripWidth, sigBPR = self.sigBytesPerRow;
    // 行签名与原图一一对应才做重拼；签名缺失（理论不可达）时退化为首片+尾片。
    BOOL sigsAligned = (sigs.count == fulls.count) && sigRows >= 16 && sigWidth >= 16;
    if (!sigsAligned) {
        MTCaptureLogWarn(@"shellx stitch rebuild sig misaligned (task %@ fulls=%lu sigs=%lu) fallback first+tail",
                  self.taskID, (unsigned long)fulls.count, (unsigned long)sigs.count);
    }
    __weak MTShellXStitchSession *weak = self;
    dispatch_async(MTShellXStitchQueue(), ^{
        @autoreleasepool {
            NSMutableArray<NSString *> *slicePaths = [NSMutableArray array];
            NSString *sliceDirectory = self.workDirectory;
            NSInteger appended = 0;
            for (NSUInteger i = 0; i < fulls.count; i++) {
                @autoreleasepool {
                    UIImage *full = [UIImage imageWithContentsOfFile:fulls[i]];
                    if (!full) continue;
                    CGImageRef cg = full.CGImage;
                    CGFloat pixelHeight = CGImageGetHeight(cg);
                    NSInteger sliceH = (NSInteger)(pixelHeight * 0.85);
                    NSInteger maxRow = MIN((NSInteger)pixelHeight - 4, sliceH);
                    if (i == 0) {
                        appended += [self mtWriteSlice:full top:0 height:maxRow directory:sliceDirectory index:appended];
                        continue;
                    }
                    NSData *prevSig = sigsAligned && i >= 1 ? sigs[i - 1] : nil;
                    NSData *curSig = sigsAligned ? sigs[i] : nil;
                    NSInteger scrollRows = -1;
                    if (prevSig && curSig) {
                        scrollRows = MTShellXMatchScroll(prevSig.bytes, curSig.bytes, sigBPR, sigRows,
                                                         MAX(40, (NSInteger)(sigRows * 0.2)), sigWidth);
                    }
                    if (scrollRows > 0) {
                        NSInteger scrollPx = (NSInteger)llround((CGFloat)scrollRows * pixelHeight / sigRows);
                        // 切片 k+1 覆盖 full[k+1] 的 [0.85H - S, 0.85H]：
                        // 内容上恰好衔接切片 k 的末尾（SHELLX 同款裁剪公式）。
                        NSInteger height = MIN(scrollPx, maxRow);
                        if (height >= 4) {
                            appended += [self mtWriteSlice:full top:maxRow - height height:height
                                                 directory:sliceDirectory index:appended];
                        }
                    }
                    MTCaptureLogInfo(@"shellx stitch rebuild (task %@ full=%lu scroll=%ld appended=%ld)",
                              self.taskID, (unsigned long)i, (long)scrollRows, (long)appended);
                }
            }
            // 最后一屏的底部尾巴补齐（与循环内判定独立执行一次）。
            if (fulls.count) {
                @autoreleasepool {
                    UIImage *last = [UIImage imageWithContentsOfFile:fulls.lastObject];
                    if (last) {
                        CGFloat pixelHeight = CGImageGetHeight(last.CGImage);
                        NSInteger sliceH = (NSInteger)(pixelHeight * 0.85);
                        NSInteger tail = (NSInteger)pixelHeight - sliceH;
                        if (tail >= 3) {
                            [self mtWriteSlice:last top:sliceH height:tail directory:sliceDirectory index:appended];
                        }
                    }
                }
            }
            NSString *output = [self.workDirectory ?: sliceDirectory
                stringByAppendingPathComponent:@"longshot.jpg"];
            CGSize size = CGSizeZero;
            NSError *error = nil;
            UIImage *image = MTShellXComposeSlices(slicePaths, output,
                                                   self.task.configSnapshot.longShotOptions.maxCanvasHeight,
                                                   self.task.configSnapshot.longShotOptions.outputQuality,
                                                   &size, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                MTShellXStitchSession *s = weak;
                if (![s mtLive]) return;
                if (!image) { [s mtFail:error.localizedDescription ?: @"长图合并失败"]; return; }
                MTCaptureLogInfo(@"shellx stitch exported (task %@ fulls=%lu slices=%lu size=%@)",
                          s.taskID, (unsigned long)fulls.count, (unsigned long)slicePaths.count,
                          NSStringFromCGSize(size));
                id<MTLongShotSessionDelegate> delegate = s.delegate;
                [s mtTeardown:NO];
                [delegate longShotSessionDidFinish:s resultImage:image];
            });
        }
    });
}

- (NSInteger)mtWriteSlice:(UIImage *)full top:(NSInteger)top height:(NSInteger)height
                directory:(NSString *)directory index:(NSInteger)index {
    CGImageRef cg = full.CGImage;
    CGFloat pixelHeight = CGImageGetHeight(cg);
    top = MAX(0, MIN(top, (NSInteger)pixelHeight - 1));
    height = MIN(height, (NSInteger)pixelHeight - top);
    if (height < 1) return 0;
    CGImageRef piece = CGImageCreateWithImageInRect(cg, CGRectMake(0, top, CGImageGetWidth(cg), height));
    if (!piece) return 0;
    UIImage *slice = [UIImage imageWithCGImage:piece scale:full.scale orientation:full.imageOrientation];
    CGImageRelease(piece);
    NSString *path = [directory stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"slice_%ld.jpg", (long)index]];
    NSData *data = UIImageJPEGRepresentation(slice, MTShellXFullJPEGQuality);
    BOOL ok = data && [data writeToFile:path atomically:YES];
    if (!ok) MTCaptureLogWarn(@"shellx stitch slice write failed (index=%ld)", (long)index);
    return ok ? 1 : 0;
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

#pragma mark - 清理

- (void)mtCancel {
    if (self.finished) return;
    id<MTLongShotSessionDelegate> delegate = self.delegate;
    [self mtTeardown:YES];
    [delegate longShotSessionDidCancel:self];
}

- (void)mtFail:(NSString *)message {
    if (self.finished) return;
    MTCaptureLogWarn(@"shellx stitch failed (task %@): %@", self.taskID, message);
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
    self.loopRunning = NO;
    self.cancellation.cancelled = YES;
    [self.tickTimer invalidate]; self.tickTimer = nil;
    [self.scroller cancel]; self.scroller = nil;
    if (self.memoryObserver) [NSNotificationCenter.defaultCenter removeObserver:self.memoryObserver];
    self.memoryObserver = nil;
    if (MTShellXStitchLockSession == self) {
        atomic_fetch_add(&MTShellXStitchLockGeneration, 1); MTShellXStitchLockSession = nil;
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                           CFSTR("com.apple.springboard.lockstate"), NULL);
    }
    self.hud.delegate = nil;
    [self.window hideAndDestroyWithCompletion:nil];
    self.window = nil; self.hud = nil; self.task = nil; self.delegate = nil;
    if (remove) {
        NSString *taskID = self.taskID;
        dispatch_async(MTShellXStitchQueue(), ^{ [MTTemporaryFileStore removeTaskDirectory:taskID]; });
    }
}

@end
