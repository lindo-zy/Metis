#import "MTQuickScrollStore.h"
#import "MTShellXSupport.h"
#import "../Output/MTQuickScrollSpool.h"
#import <ImageIO/ImageIO.h>
#import <math.h>
#import <stdlib.h>

enum { MTQuickFixedStreakThreshold = 3, MTQuickStickyWarmupFrames = 4 };

@implementation MTQuickScrollResult
@end

@interface MTQuickScrollStore () {
    int64_t _position;        // 纯位移累计（诊断与回滚判定）
    int64_t _committedEnd;    // Confirmed content coordinate at the output seam.
    int64_t _outputPosition; // Position of the output reference, separate from tracking.
}
@property (atomic, readwrite) CFAbsoluteTime exportProgressTime;
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) MTLongShotOptions *options;
@property (nonatomic, strong) MTLongShotCancellation *cancellation;
@property (nonatomic, strong) MTQuickScrollSpool *spool;
@property (nonatomic) NSInteger acceptedStrips;
@property (nonatomic) BOOL tailCommitted;
@property (nonatomic, strong) NSData *signature;
@property (nonatomic, strong) NSData *nativeLuma;
@property (nonatomic, strong) NSData *outputSignature;
@property (nonatomic, strong) NSData *outputLuma;
@property (nonatomic, strong) UIImage *outputFrame;
@property (nonatomic) CGRect outputRect;
@property (nonatomic) NSInteger outputBottom;
@property (nonatomic, strong) dispatch_queue_t spoolQueue;
@property (nonatomic, strong) NSMutableData *fixedStreak;   // 每行同位置静止 streak
@property (nonatomic) NSInteger width, rows, seam;
@property (nonatomic) NSInteger stickyTop, stickyBottom;    // 0 = 未测定（用保守默认）
@property (nonatomic) NSInteger movedFrames;
@property (nonatomic) CFTimeInterval referenceTime, referenceInterval, previewTime;
@property (nonatomic) BOOL indicatorVisible, geometryMismatch;
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
    NSMutableData *data = [NSMutableData dataWithLength:width * height];
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, width, height, 8, width, gray, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!context) return nil;
    CGContextScaleCTM(context, width / rect.size.width, 1);
    CGContextTranslateCTM(context, -rect.origin.x, (CGFloat)height - CGImageGetHeight(image) + rect.origin.y);
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image)), image);
    CGContextRelease(context);
    return data;
}

@implementation MTQuickScrollStore
- (instancetype)initWithDirectory:(NSString *)directory options:(MTLongShotOptions *)options
                     cancellation:(MTLongShotCancellation *)cancellation scale:(CGFloat)scale {
    if ((self = [super init])) {
        _directory = [directory copy]; _options = options; _cancellation = cancellation;
        _scale = MAX(1, scale); _seam = -1;
        _spool = [[MTQuickScrollSpool alloc] initWithDirectory:directory cancellation:cancellation];
        __weak MTQuickScrollStore *weak = self;
        _spool.onProgress = ^{ weak.exportProgressTime = CFAbsoluteTimeGetCurrent(); };
        _spoolQueue = dispatch_queue_create("com.lindo.metis.quick.spool", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)mtAppendImage:(UIImage *)image rect:(CGRect)rect scrub:(NSInteger)scrub error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *failure = nil;
    dispatch_sync(self.spoolQueue, ^{ @autoreleasepool {
        ok = [self.spool appendImage:image rect:rect scrubRightColumns:scrub error:&failure];
    }});
    if (failure && error) *error = failure;
    return ok;
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
        paused.count = (self.signature ? self.acceptedStrips + 1 : 0);
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
        self.width = rect.size.width; self.rows = rect.size.height;
        self.signature = signature; self.nativeLuma = native; self.referenceTime = timestamp;
        self.outputSignature = signature; self.outputLuma = native; self.outputFrame = image; self.outputRect = rect;
        self.outputBottom = self.rows;
        self.fixedStreak = [NSMutableData dataWithLength:(NSUInteger)self.rows];
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
            }
            if (match.kind == MTQuickScrollMoved) {
                // Still 帧不替换参考：亚像素/单像素慢滚必须累积到可测量。
                self.movedFrames++;
                [self mtUpdateFixedRowsWithPrevious:self.signature.bytes current:signature.bytes delta:match.delta];
                self.signature = signature; self.nativeLuma = native;
                self.lastDelta = match.delta;
                self.referenceInterval = elapsed; self.referenceTime = timestamp;
            }
        }
    }
    result.count = (self.signature ? self.acceptedStrips + 1 : 0);
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
    if ((self.outputLuma != self.nativeLuma || displacement != match->delta) &&
        !MTQuickScrollVerifyNative(self.outputLuma.bytes, native.bytes, (int)self.width,
            (int)self.rows, (int)displacement, (int)bodyTop, (int)bottom, &limits, NULL)) return -1;
    NSInteger preferred = MIN(high, MAX(low, bottom - self.rows / 4));
    NSInteger coarseSeam = MTQuickScrollSeamRow(self.outputSignature.bytes, signature.bytes,
        (int)self.rows, (int)displacement, (int)preferred, (int)low, (int)high, &limits);
    if (coarseSeam < low || coarseSeam > high) return -1;
    NSInteger seam = MTQuickScrollNativeSeamRow(self.outputLuma.bytes, native.bytes,
        (int)self.width, (int)self.rows, (int)displacement, (int)coarseSeam,
        (int)MAX(low, coarseSeam - 24), (int)MIN(high, coarseSeam + 24), &limits);
    if (seam < 0) seam = MTQuickScrollNativeSeamRow(self.outputLuma.bytes, native.bytes,
        (int)self.width, (int)self.rows, (int)displacement, (int)coarseSeam, (int)low, (int)high, &limits);
    if (seam < low || seam > high) return -1;
    NSInteger previousSeam = seam + displacement;
    int64_t anchor = nextPosition + seam;
    if (self.seam >= 0 && anchor <= _committedEnd) { _position = nextPosition; return 0; }
    NSInteger scrub = self.indicatorVisible ? MAX(8, MIN(24, lround(self.width * 0.012))) : 0;
    CGRect stripRect = CGRectMake(self.outputRect.origin.x, self.outputRect.origin.y + oldStart,
                                  self.width, previousSeam - oldStart);
    if (![self mtAppendImage:self.outputFrame rect:stripRect scrub:scrub error:error]) return -1;
    self.seam = seam; _committedEnd = anchor; self.acceptedStrips++;
    self.outputFrame = image; self.outputRect = rect; self.outputSignature = signature; self.outputLuma = native;
    self.outputBottom = bottom; _outputPosition = nextPosition; _position = nextPosition;
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

- (NSString *)smartOutputName { return @"longshot.png"; }
- (NSString *)smartOutputUTI { return @"public.png"; }
- (CGFloat)smartOutputQuality { return 1; }

- (UIImage *)exportToURL:(NSURL *)url error:(NSError **)error {
    if (self.cancellation.cancelled || !self.outputFrame) return nil;
    self.exportProgressTime = CFAbsoluteTimeGetCurrent();
    if (!self.tailCommitted) {
        NSInteger start = self.seam < 0 ? 0 : self.seam;
        CGRect tail = CGRectMake(self.outputRect.origin.x, self.outputRect.origin.y + start,
                                 self.width, self.rows - start);
        NSInteger scrub = self.indicatorVisible ? MAX(8, MIN(24, lround(self.width * 0.012))) : 0;
        if (![self mtAppendImage:self.outputFrame rect:tail scrub:scrub error:error]) return nil;
        self.tailCommitted = YES;
    }
    self.signature = nil; self.nativeLuma = nil;
    self.outputSignature = nil; self.outputLuma = nil;
    __block BOOL written = NO;
    __block NSError *failure = nil;
    dispatch_sync(self.spoolQueue, ^{ written = [self.spool writePNGToURL:url error:&failure]; });
    if (!written) { if (error) *error = failure; return nil; }
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url,
        (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO});
    CGImageRef cg = source ? CGImageSourceCreateImageAtIndex(source, 0,
        (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO}) : NULL;
    if (source) CFRelease(source);
    // Some consumers cannot instantiate extremely tall CGImages. The valid PNG
    // remains the output authority; a bounded viewport proxy lets file save/copy
    // continue without requiring a giant display surface in SpringBoard.
    UIImage *image = cg ? [UIImage imageWithCGImage:cg scale:self.scale orientation:UIImageOrientationUp] : self.outputFrame;
    if (cg) CGImageRelease(cg);
    self.outputFrame = nil;
    return image;
}

@end
