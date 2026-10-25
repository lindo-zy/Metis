#import "MTQuickScrollStore.h"
#import "MTShellXSupport.h"
#import "../Output/MTLongImageComposer.h"
#import <math.h>
#import <stdlib.h>

// Prism 对齐的接缝/触底/擦除阈值：像素坐标按 3x 全屏（~2556 行）标定。
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
    int64_t _committedEnd;    // 承诺锚点 A = 帧位移 + 接缝行（内容坐标）
}
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) MTLongShotOptions *options;
@property (nonatomic, strong) MTLongShotCancellation *cancellation;
@property (nonatomic, strong) NSMutableArray<MTLongShotSlice *> *slices;
@property (nonatomic, strong) MTLongShotSlice *tail;
@property (nonatomic, strong) NSData *signature;
@property (nonatomic, strong) NSMutableData *fixedStreak;   // 每行同位置静止 streak
@property (nonatomic, strong) NSData *tailSignature;        // 当前尾部对应帧的整帧签名
@property (nonatomic) NSInteger width, rows, seam, bodyTop, tailSeam;
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
static NSData *MTQuickGrayImage(CGImageRef image, CGRect rect) {
    size_t width = MTQuickScrollSignatureWidth, height = (size_t)rect.size.height;
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
        _weakUpFlickTime = -MTQuickBounceWindow; _bounceTime = -MTQuickBottomMotionWindow;
        _lastMotionTime = -MTQuickBottomMotionWindow;
    }
    return self;
}

- (MTLongShotSlice *)mtSlice:(UIImage *)image rect:(CGRect)rect name:(NSString *)name
              scrubRightColumns:(NSInteger)scrubColumns error:(NSError **)error {
    MTLongShotSlice *slice = [MTLongImageComposer sliceFromScreenImage:image pixelRect:rect
        filePath:[self.directory stringByAppendingPathComponent:name] options:self.options
        scrubRightColumns:scrubColumns cancellation:self.cancellation error:error];
    [slice discardAlignmentSignature];
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
    NSData *signature = MTQuickGrayImage(image.CGImage, rect);
    if (!signature) { MTQuickStoreError(error, @"画面分析缓冲区创建失败"); return nil; }
    MTQuickScrollResult *result = [MTQuickScrollResult new];
    if (!self.signature) {
        MTLongShotSlice *first = [self mtSlice:image rect:rect name:@"quick_first.jpg" scrubRightColumns:0 error:error];
        if (!first) return nil;
        self.width = rect.size.width; self.rows = rect.size.height;
        self.signature = signature; self.referenceTime = timestamp;
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
        result.match = match;
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
            // 右缘滚动条检测：对齐后内部列一致而最右列异常 → 条带擦除。
            self.indicatorVisible = match.kind == MTQuickScrollMoved &&
                MTQuickScrollIndicatorVisible(self.signature.bytes, signature.bytes, (int)self.rows,
                                              match.delta, match.bodyTop, match.bodyBottom);
            NSInteger seam = [self mtAdvanceWithMatch:&match signature:signature image:image
                                                 rect:rect timestamp:timestamp final:final error:error];
            if (seam < 0) {
                match.kind = MTQuickScrollUncertain; result.match = match;
            } else if (seam > 0) {
                // seam > 0：本次已入账新条带与可替换尾部。
                self.tailSignature = signature; self.tailSeam = seam;
            }
            if (match.kind == MTQuickScrollMoved) {
                // Still 帧不替换参考：亚像素/单像素慢滚必须累积到可测量。
                [self mtUpdateFixedRowsWithPrevious:self.signature.bytes current:signature.bytes delta:match.delta];
                self.signature = signature;
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

/// 返回值：-1 = 匹配退化（调用方转 Uncertain）；0 = 无新增；> 0 = 本帧入账后的接缝行。
/// 记账模型：承诺锚点 A = 帧位移 + 接缝行（内容坐标）。条带高度 = A_k - A_{k-1}，
/// 于是「首帧 + 条带 + 末帧尾」恒等于「末帧位移 + 屏高」，与接缝如何移动无关。
- (NSInteger)mtAdvanceWithMatch:(MTQuickScrollMatch *)match signature:(NSData *)signature image:(UIImage *)image
                           rect:(CGRect)rect timestamp:(CFTimeInterval)timestamp final:(BOOL)final error:(NSError **)error {
    MTQuickScrollLimits limits;
    [self mtLimits:&limits];
    NSInteger chromeFloor = match->bodyBottom > 0 ? MIN(match->bodyBottom, self.rows) : self.rows;
    if (self.stickyBottom > 0) chromeFloor = MIN(chromeFloor, self.stickyBottom);
    NSInteger bodyTop = self.seam >= 0 ? self.bodyTop : MAX(match->bodyTop, self.stickyTop);
    _position += match->delta;   // 纯位移累计（含 Still 的 0 与回滚的负值）
    if (match->kind == MTQuickScrollStill && self.seam < 0) return 0;
    // 承诺内容只进不退：上帧接缝内容在当前帧的落点。回滚（含位置滞后的回滚）
    // 会把它推到帧底以下——该帧没有可裁的新正文，只累计位移。
    NSInteger committedFloor = MAX(bodyTop + 1, self.seam >= 0 ? self.seam - match->delta : bodyTop + 1);
    if (self.seam >= 0 && committedFloor > chromeFloor - 1) return 0;
    // 接缝锚定正文底界（与自动拼接同口径）：每帧在底界上方的安静带内落刀。
    NSInteger preferred = chromeFloor - MIN(12, self.rows / 120);
    NSInteger low = MAX(committedFloor, preferred - 240);
    NSInteger high = MIN(chromeFloor - 1, preferred + 60);
    if (low > high) {
        NSInteger mid = MIN(MAX(preferred, committedFloor), chromeFloor - 1);
        low = mid; high = mid;
    }
    NSInteger seam = MTQuickScrollSeamRow(self.signature.bytes, signature.bytes, (int)self.rows, match->delta,
                                          (int)MIN(MAX(preferred, low), high), (int)low, (int)high, &limits);
    if (seam < committedFloor || seam > chromeFloor - 1) return -1;
    int64_t anchor = _position + seam;
    if (self.seam < 0) _committedEnd = seam;   // 首帧入账前先裁掉底部，锚点=首接缝
    int64_t height = anchor - _committedEnd;
    int minimum = final || self.seam < 0 ? 1 : (int)MAX(24, self.rows / 5);
    if (height <= 0 || height < minimum) return 0;
    if (seam - height < bodyTop) return -1;    // 条带越出正文上界：真实丢重叠
    NSInteger scrub = self.indicatorVisible ? (NSInteger)MAX(8, MIN(24, lround(self.width * 0.012))) : 0;
    // Persist only the new strip, plus a replaceable current footer. Recorded
    // pixels above the seam never move; the seam itself tracks quiet bands.
    CGRect stripRect = CGRectMake(rect.origin.x, rect.origin.y + seam - height, self.width, height);
    NSString *name = [NSString stringWithFormat:@"quick_%05lu.jpg", (unsigned long)self.slices.count];
    MTLongShotSlice *strip = [self mtSlice:image rect:stripRect name:name scrubRightColumns:scrub error:error];
    if (!strip) return -1;
    MTLongShotSlice *tail = nil;
    if (seam < self.rows) {
        CGRect tailRect = CGRectMake(rect.origin.x, rect.origin.y + seam, self.width, self.rows - seam);
        NSString *tailName = [NSString stringWithFormat:@"quick_tail_%05lu.jpg", (unsigned long)self.slices.count];
        tail = [self mtSlice:image rect:tailRect name:tailName scrubRightColumns:scrub error:error];
        if (!tail) return -1;
    }
    if (self.seam < 0) {
        self.bodyTop = bodyTop;
        self.slices.firstObject.cropBottomRows = self.rows - seam;
    }
    NSString *oldTail = self.tail.filePath;
    self.tail = tail; self.seam = seam; _committedEnd = anchor;
    [self.slices addObject:strip];
    if (oldTail) [NSFileManager.defaultManager removeItemAtPath:oldTail error:nil];
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
    self.signature = nil;
    NSMutableArray *slices = [self.slices mutableCopy];
    if (self.tail) {
        // 空白尾部自动裁剪：尾部底缘连续安静行（页面内容早于视口结束且无底栏）裁掉。
        MTLongShotSlice *tail = self.tail;
        if (self.tailSignature.length == (NSUInteger)self.rows * MTQuickScrollSignatureWidth && tail) {
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
