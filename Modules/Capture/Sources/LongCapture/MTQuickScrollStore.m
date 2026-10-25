#import "MTQuickScrollStore.h"
#import "MTShellXSupport.h"
#import "../Output/MTLongImageComposer.h"
#import <math.h>
#import <stdlib.h>

// Native-row thresholds; matching is validated before motion or output state advances.
enum {
    MTQuickFixedStreakThreshold = 3,      // 连续 N 个运动帧同位置静止 → 固定元素
    MTQuickStickyWarmupFrames = 4,        // 累积期沿用保守边界（顶 1/5、底 1/7）
    MTQuickBottomStillFrames = 3,         // 回弹后静止帧数确认到底
    MTQuickBlankTailMinimumRows = 60,     // 末尾空白行数达到才自动裁剪
};
static const CFTimeInterval MTQuickBounceWindow = 0.8;
static const CFTimeInterval MTQuickBottomMotionWindow = 1.5;

@implementation MTQuickScrollResult
@end

@interface MTQuickScrollStore () {
    int64_t _position;        // 纯位移累计（诊断与回滚判定）
    int64_t _committedEnd;    // Confirmed content coordinate at the output seam.
    int64_t _outputPosition; // Position of the output reference, separate from tracking.
}
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) MTLongShotOptions *options;
@property (nonatomic, strong) MTLongShotCancellation *cancellation;
@property (nonatomic, strong) NSMutableArray<MTLongShotSlice *> *slices;
@property (nonatomic, strong) MTLongShotSlice *tail;
@property (nonatomic, strong) NSData *signature;
@property (nonatomic, strong) NSData *nativeLuma;
@property (nonatomic, strong) NSData *outputSignature;
@property (nonatomic, strong) NSData *outputLuma;
@property (nonatomic, strong) UIImage *outputFrame;
@property (nonatomic) CGRect outputRect;
@property (nonatomic) NSInteger outputBottom;
@property (nonatomic, strong) dispatch_queue_t spoolQueue;
@property (nonatomic, strong) NSMutableData *fixedStreak;   // 每行同位置静止 streak
@property (nonatomic, strong) NSData *tailSignature;        // 当前尾部对应帧的整帧签名
@property (nonatomic) NSInteger width, rows, seam, tailSeam;
@property (nonatomic) NSInteger stickyTop, stickyBottom;    // 0 = 未测定（用保守默认）
@property (nonatomic) NSInteger movedFrames, stillStreak;
@property (nonatomic) CFTimeInterval referenceTime, referenceInterval, previewTime;
@property (nonatomic) CFTimeInterval lastMotionTime, weakUpFlickTime, bounceTime;
@property (nonatomic) BOOL bottomConfirmed, indicatorVisible, geometryMismatch;
@property (nonatomic) int lastDelta;
@property (nonatomic) CGFloat scale;
@end

static void MTQuickStoreError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"com.lindo.metis.capture.quick" code:1
                                      userInfo:@{NSLocalizedDescriptionKey:message}];
}

// Small grayscale working buffer; vertical rows retain native pixel precision.
static NSData *MTQuickGrayImage(CGImageRef image, CGRect rect, size_t width) {
    size_t height = (size_t)rect.size.height;
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width, gray, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!context) return nil;
    CGContextScaleCTM(context, width / rect.size.width, 1);
    CGContextTranslateCTM(context, -rect.origin.x, (CGFloat)height - CGImageGetHeight(image) + rect.origin.y);
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image)), image);
    NSData *data = [NSData dataWithBytes:CGBitmapContextGetData(context) length:width * height];
    CGContextRelease(context);
    return data;
}

@implementation MTQuickScrollStore
- (instancetype)initWithDirectory:(NSString *)directory options:(MTLongShotOptions *)options
                     cancellation:(MTLongShotCancellation *)cancellation scale:(CGFloat)scale {
    if ((self = [super init])) {
        _directory = [directory copy]; _options = options; _cancellation = cancellation;
        _scale = MAX(1, scale); _slices = [NSMutableArray array]; _seam = -1;
        _spoolQueue = dispatch_queue_create("com.lindo.metis.quick.spool", DISPATCH_QUEUE_SERIAL);
        _weakUpFlickTime = -MTQuickBounceWindow; _bounceTime = -MTQuickBottomMotionWindow;
        _lastMotionTime = -MTQuickBottomMotionWindow;
    }
    return self;
}

- (MTLongShotSlice *)mtSlice:(UIImage *)image rect:(CGRect)rect name:(NSString *)name
              scrubRightColumns:(NSInteger)scrubColumns error:(NSError **)error {
    // Spool owns image encoding and disk writes; only completed files become output.
    __block MTLongShotSlice *slice = nil;
    __block NSError *failure = nil;
    dispatch_sync(self.spoolQueue, ^{ @autoreleasepool {
        slice = [MTLongImageComposer sliceFromScreenImage:image pixelRect:rect
            filePath:[self.directory stringByAppendingPathComponent:name] options:self.options
            scrubRightColumns:scrubColumns cancellation:self.cancellation error:&failure];
        [slice discardAlignmentSignature];
    }});
    if (failure && error) *error = failure;
    return slice;
}

- (void)mtLimits:(MTQuickScrollLimits *)limits {
    limits->stickyTop = self.stickyTop;
    limits->stickyBottom = self.stickyBottom;
    limits->fixedRows = self.fixedStreak.length == (NSUInteger)self.rows
        ? (const uint8_t *)self.fixedStreak.bytes : NULL;
    limits->fixedThreshold = MTQuickFixedStreakThreshold;
}

/// 吸顶/吸底边界 = 固定行 streak 的前后缀；无测定数据时回退保守默认。
- (void)mtRefreshStickyBounds {
    if (self.movedFrames < MTQuickStickyWarmupFrames || !self.fixedStreak.length) {
        self.stickyTop = 0; self.stickyBottom = 0;   // 未测定：matcher 内部用 1/5、1/7 默认
        return;
    }
    const uint8_t *streak = (const uint8_t *)self.fixedStreak.bytes;
    NSInteger rows = self.rows, prefix = 0, suffix = 0, cap = rows / 3;
    while (prefix < cap && streak[prefix] >= MTQuickFixedStreakThreshold) prefix++;
    while (suffix < cap && streak[rows - 1 - suffix] >= MTQuickFixedStreakThreshold) suffix++;
    self.stickyTop = MAX(rows / 16, MIN(prefix + 4, cap));
    self.stickyBottom = MAX(rows - rows / 3, rows - MAX(rows / 16, MIN(suffix + 4, cap)));
}

- (void)mtUpdateFixedRowsWithPrevious:(const uint8_t *)previous current:(const uint8_t *)current delta:(int)delta {
    if (!previous || !current || labs(delta) < 8) return;
    if (self.fixedStreak.length != (NSUInteger)self.rows)
        self.fixedStreak = [NSMutableData dataWithLength:(NSUInteger)self.rows];
    uint8_t *streak = self.fixedStreak.mutableBytes;
    for (NSInteger r = 0; r < self.rows; r++) {
        const uint8_t *row = current + r * MTQuickScrollSignatureWidth;
        uint8_t low = 255, high = 0;
        for (int x = 6; x < MTQuickScrollSignatureWidth - 6; x++) {
            if (row[x] < low) low = row[x];
            if (row[x] > high) high = row[x];
        }
        // 只有有纹理的行参与 streak：空白行既不能证明固定（背景处处相同），
        // 也不应在接缝代价里被当作悬浮元素惩罚——空白带恰是首选接缝。
        if (high - low <= 8) { streak[r] = 0; continue; }
        // 同位置跨帧静止且页面整体在滚动 → 固定悬浮/吸顶吸底元素；正文行对齐后不相似。
        if (MTQuickScrollRowDifference(previous, current, (int)self.rows, (int)r) <= 2) {
            if (streak[r] < 255) streak[r]++;
        } else {
            streak[r] = 0;
        }
    }
    [self mtRefreshStickyBounds];
}

- (MTQuickScrollResult *)consumeImage:(UIImage *)image pixelRect:(CGRect)rect
                            timestamp:(CFTimeInterval)timestamp final:(BOOL)final error:(NSError **)error {
    if (self.cancellation.cancelled) return nil;
    if (!image.CGImage || !isfinite(rect.origin.x) || !isfinite(rect.origin.y) ||
        !isfinite(rect.size.width) || !isfinite(rect.size.height)) {
        MTQuickStoreError(error, @"快速截图的画面区域无效"); return nil;
    }
    rect = CGRectIntegral(CGRectIntersection(rect, CGRectMake(0, 0, CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage))));
    if (CGRectIsNull(rect) || CGRectIsEmpty(rect) || rect.size.height < 240 ||
        rect.size.height > 16384 || rect.size.width < 32) {
        MTQuickStoreError(error, @"快速截图的画面区域无效"); return nil;
    }
    if (self.rows && (self.rows != rect.size.height || self.width != rect.size.width)) {
        // 旋转/几何变化：保留已确认内容，等待几何转回；不再让整个会话失败。
        self.geometryMismatch = YES;
        MTQuickScrollResult *paused = [MTQuickScrollResult new];
        paused.match = (MTQuickScrollMatch){MTQuickScrollUncertain, 0, 0, 0, (int)self.rows, 255};
        paused.geometryMismatch = YES;
        paused.count = self.slices.count;
        paused.totalHeight = self.seam >= 0 ? (NSInteger)_committedEnd + (self.rows - self.seam) : self.rows;
        [self mtAttachPreview:paused image:image rect:rect timestamp:timestamp final:final];
        return paused;
    }
    self.geometryMismatch = NO;
    NSData *signature = MTQuickGrayImage(image.CGImage, rect, MTQuickScrollSignatureWidth);
    NSData *native = MTQuickGrayImage(image.CGImage, rect, (size_t)rect.size.width);
    if (!signature || !native) { MTQuickStoreError(error, @"画面分析缓冲区创建失败"); return nil; }
    MTQuickScrollResult *result = [MTQuickScrollResult new];
    if (!self.signature) {
        MTLongShotSlice *first = [self mtSlice:image rect:rect name:@"quick_first.png" scrubRightColumns:0 error:error];
        if (!first) return nil;
        self.width = rect.size.width; self.rows = rect.size.height;
        self.signature = signature; self.nativeLuma = native; self.referenceTime = timestamp;
        self.outputSignature = signature; self.outputLuma = native; self.outputFrame = image; self.outputRect = rect;
        self.outputBottom = self.rows;
        self.fixedStreak = [NSMutableData dataWithLength:(NSUInteger)self.rows];
        [self.slices addObject:first];
        result.match = (MTQuickScrollMatch){MTQuickScrollStill, 0, 0, 0, (int)self.rows, 0};
    } else {
        double elapsed = MAX(0.001, timestamp - self.referenceTime);
        double ratio = self.referenceInterval > 0 ? MIN(4, MAX(0.25, elapsed / self.referenceInterval)) : 1;
        int predicted = (int)lround(self.lastDelta * ratio);
        MTQuickScrollLimits limits;
        [self mtLimits:&limits];
        MTQuickScrollMatch match = MTQuickScrollMatchFrames(self.signature.bytes, signature.bytes,
                                                            (int)self.rows, predicted, &limits);
        if (match.kind == MTQuickScrollMoved &&
            !MTQuickScrollVerifyNative(self.nativeLuma.bytes, native.bytes, (int)self.width,
                (int)self.rows, match.delta, match.bodyTop, match.bodyBottom, &limits, NULL))
            match.kind = MTQuickScrollUncertain;
        result.match = match;
        if (match.kind != MTQuickScrollUncertain) {
            // 右缘滚动条检测：对齐后内部列一致而最右列异常 → 条带擦除。
            self.indicatorVisible = match.kind == MTQuickScrollMoved &&
                MTQuickScrollIndicatorVisible(self.signature.bytes, signature.bytes, (int)self.rows,
                                              match.delta, match.bodyTop, match.bodyBottom);
            NSInteger seam = [self mtAdvanceWithMatch:&match signature:signature native:native image:image
                                                 rect:rect timestamp:timestamp final:final error:error];
            if (seam < 0) {
                if (error && *error) return nil;
                match.kind = MTQuickScrollUncertain; result.match = match;
            } else if (seam > 0) {
                // seam > 0：本次已入账新条带与可替换尾部。
                self.tailSignature = signature; self.tailSeam = seam;
            }
            if (match.kind != MTQuickScrollUncertain) {
                // 触底形态：微弱上滑后小幅回弹（橡皮筋），随后画面静止。
                if (match.kind == MTQuickScrollMoved && labs(match.delta) >= 8) {
                    self.movedFrames++; self.stillStreak = 0;
                    self.lastMotionTime = timestamp;
                    if (match.delta > 0 && match.delta <= self.rows / 20) {
                        self.weakUpFlickTime = timestamp;
                    } else if (match.delta < 0 && -match.delta <= self.rows / 20 &&
                               timestamp - self.weakUpFlickTime < MTQuickBounceWindow) {
                        self.bounceTime = timestamp;
                    } else if (labs(match.delta) > self.rows / 20) {
                        self.weakUpFlickTime = -MTQuickBounceWindow;
                    }
                } else {
                    self.stillStreak++;
                }
                if (!self.bottomConfirmed && self.bounceTime > 0 && self.stillStreak >= MTQuickBottomStillFrames &&
                    timestamp - self.bounceTime < MTQuickBottomMotionWindow &&
                    timestamp - self.lastMotionTime < MTQuickBottomMotionWindow) {
                    self.bottomConfirmed = YES;
                    result.bottomReached = YES;
                }
            }
            if (match.kind == MTQuickScrollMoved) {
                // Still 帧不替换参考：亚像素/单像素慢滚必须累积到可测量。
                [self mtUpdateFixedRowsWithPrevious:self.signature.bytes current:signature.bytes delta:match.delta];
                self.signature = signature; self.nativeLuma = native;
                self.lastDelta = match.delta;
                self.referenceInterval = elapsed; self.referenceTime = timestamp;
            }
        }
    }
    result.count = self.slices.count;
    result.totalHeight = self.seam >= 0 ? (NSInteger)_committedEnd + (self.rows - self.seam) : self.rows;
    [self mtAttachPreview:result image:image rect:rect timestamp:timestamp final:final];
    return result;
}

/// Position and output reference are separate (Prism rememberPositionFrame/outputEnd).
/// All validation and disk writes complete before any output anchor is committed.
- (NSInteger)mtAdvanceWithMatch:(MTQuickScrollMatch *)match signature:(NSData *)signature native:(NSData *)native image:(UIImage *)image
                           rect:(CGRect)rect timestamp:(CFTimeInterval)timestamp final:(BOOL)final error:(NSError **)error {
    int64_t nextPosition = _position + match->delta;
    int64_t displacement = nextPosition - _outputPosition;
    if (displacement <= 0) { _position = nextPosition; return 0; }
    NSInteger minimum = final ? 1 : MAX(24, self.rows / 20);
    if (displacement < minimum) { _position = nextPosition; return 0; }
    if (displacement >= self.rows) return -1;
    MTQuickScrollLimits limits;
    [self mtLimits:&limits];
    NSInteger bodyTop = MAX(match->bodyTop, self.stickyTop);
    NSInteger bottom = MIN(self.rows, match->bodyBottom);
    if (self.stickyBottom > 0) bottom = MIN(bottom, self.stickyBottom);
    NSInteger oldBottom = self.seam < 0 ? bottom : self.outputBottom;
    NSInteger oldStart = self.seam < 0 ? 0 : self.seam;
    // Both sides of the cut must lie in the same, observed overlap. In particular,
    // slow frames and rollback cannot apply the last frame's delta to an older seam.
    NSInteger low = MAX(bodyTop + 3, oldStart - displacement + 1);
    NSInteger high = MIN(bottom - 3, oldBottom - displacement - 3);
    if (low > high) return -1;
    if (!MTQuickScrollVerifyNative(self.outputLuma.bytes, native.bytes, (int)self.width,
        (int)self.rows, (int)displacement, (int)bodyTop, (int)bottom, &limits, NULL)) return -1;
    NSInteger preferred = MIN(high, MAX(low, bottom - self.rows / 4));
    NSInteger coarseSeam = MTQuickScrollSeamRow(self.outputSignature.bytes, signature.bytes,
        (int)self.rows, (int)displacement, (int)preferred, (int)low, (int)high, &limits);
    if (coarseSeam < low || coarseSeam > high) return -1;
    NSInteger seam = MTQuickScrollNativeSeamRow(self.outputLuma.bytes, native.bytes,
        (int)self.width, (int)self.rows, (int)displacement, (int)coarseSeam, (int)low, (int)high, &limits);
    if (seam < low || seam > high) return -1;
    NSInteger previousSeam = seam + displacement;
    int64_t anchor = nextPosition + seam;
    if (self.seam >= 0 && anchor <= _committedEnd) { _position = nextPosition; return 0; }
    NSInteger scrub = self.indicatorVisible ? MAX(8, MIN(24, lround(self.width * 0.012))) : 0;
    MTLongShotSlice *strip = nil;
    NSString *stripPath = nil;
    if (self.seam >= 0) {
        CGRect stripRect = CGRectMake(self.outputRect.origin.x, self.outputRect.origin.y + oldStart,
                                     self.width, previousSeam - oldStart);
        NSString *name = [NSString stringWithFormat:@"quick_%05lu.png", (unsigned long)self.slices.count];
        strip = [self mtSlice:self.outputFrame rect:stripRect name:name scrubRightColumns:scrub error:error];
        if (!strip) return -1;
        stripPath = strip.filePath;
    }
    CGRect tailRect = CGRectMake(rect.origin.x, rect.origin.y + seam, self.width, self.rows - seam);
    NSString *tailName = [NSString stringWithFormat:@"quick_tail_%@.png", NSUUID.UUID.UUIDString];
    MTLongShotSlice *tail = [self mtSlice:image rect:tailRect name:tailName scrubRightColumns:scrub error:error];
    if (!tail || self.cancellation.cancelled) {
        if (stripPath) [NSFileManager.defaultManager removeItemAtPath:stripPath error:nil];
        return -1;
    }
    if (self.seam < 0) self.slices.firstObject.cropBottomRows = self.rows - previousSeam;
    else [self.slices addObject:strip];
    NSString *oldTail = self.tail.filePath;
    self.tail = tail; self.seam = seam; _committedEnd = anchor;
    self.outputFrame = image; self.outputRect = rect; self.outputSignature = signature; self.outputLuma = native;
    self.outputBottom = bottom; _outputPosition = nextPosition; _position = nextPosition;
    if (oldTail && ![oldTail isEqualToString:tail.filePath])
        [NSFileManager.defaultManager removeItemAtPath:oldTail error:nil];
    return seam;
}

- (void)mtAttachPreview:(MTQuickScrollResult *)result image:(UIImage *)image
                   rect:(CGRect)rect timestamp:(CFTimeInterval)timestamp final:(BOOL)final {
    if (timestamp - self.previewTime >= 0.10 || final) {
        // Video-style phone preview shows the current clean viewport; it must not
        // retain an IOSurface or a full-resolution capture between callbacks.
        CGImageRef crop = CGImageCreateWithImageInRect(image.CGImage, rect);
        if (crop) {
            result.preview = MTShellXThumbnail([UIImage imageWithCGImage:crop], 640);
            CGImageRelease(crop);
        }
        self.previewTime = timestamp;
    }
}

- (NSInteger)mtEstimatedPixels {
    NSInteger height = self.seam >= 0 ? (NSInteger)_committedEnd + (self.rows - self.seam) : self.rows;
    return self.width > 0 && height > 0 ? self.width * height : 0;
}

- (NSString *)smartOutputName {
    return [self mtEstimatedPixels] <= 2200000 ? @"longshot.png" : @"longshot.jpg";
}
- (NSString *)smartOutputUTI {
    return [[self smartOutputName] hasSuffix:@"png"] ? @"public.png" : @"public.jpeg";
}
- (CGFloat)smartOutputQuality {
    NSInteger pixels = [self mtEstimatedPixels];
    CGFloat base = self.options.outputQuality;
    if (pixels > 5500000) return MIN(base, 0.85);
    if (pixels > 2200000) return MIN(base, 0.92);
    return base;
}

- (UIImage *)exportToURL:(NSURL *)url error:(NSError **)error {
    self.signature = nil; self.nativeLuma = nil;
    self.outputSignature = nil; self.outputLuma = nil; self.outputFrame = nil;
    NSMutableArray *slices = [self.slices mutableCopy];
    if (self.tail) {
        // 空白尾部自动裁剪：尾部底缘连续安静行（页面内容早于视口结束且无底栏）裁掉。
        MTLongShotSlice *tail = self.tail;
        if (self.bottomConfirmed && self.tailSignature.length == (NSUInteger)self.rows * MTQuickScrollSignatureWidth && tail) {
            NSInteger run = MTQuickScrollTrailingQuietRows((const uint8_t *)self.tailSignature.bytes,
                                                           (int)self.rows, (int)self.tailSeam, (int)self.rows);
            NSInteger crop = run >= MTQuickBlankTailMinimumRows ? run - 8 : 0;
            if (crop > 0 && crop < tail.pixelHeight - tail.cropBottomRows) {
                tail.cropBottomRows += crop;
            }
        }
        [slices addObject:tail];
    }
    NSInteger cap = MTLongShotStitchPixelCap(MTLongShotProcessMemoryLimitBytes(), MTLongShotMaxCanvasPixels);
    return [MTLongImageComposer composedImageWithSlices:slices screenScale:self.scale outputURL:url
        maxPixels:cap outputUTI:self.smartOutputUTI outputQuality:self.smartOutputQuality
        maxCanvasHeight:self.options.maxCanvasHeight
        cancellation:self.cancellation progressBlock:nil outPixelSize:NULL error:error];
}
@end
