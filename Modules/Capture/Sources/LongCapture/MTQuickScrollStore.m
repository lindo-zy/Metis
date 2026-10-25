#import "MTQuickScrollStore.h"
#import "MTShellXSupport.h"
#import "../Output/MTLongImageComposer.h"
#import <math.h>

@implementation MTQuickScrollResult
@end

@interface MTQuickScrollStore () {
    MTQuickScrollCoverage _coverage;
}
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) MTLongShotOptions *options;
@property (nonatomic, strong) MTLongShotCancellation *cancellation;
@property (nonatomic, strong) NSMutableArray<MTLongShotSlice *> *slices;
@property (nonatomic, strong) MTLongShotSlice *tail;
@property (nonatomic, strong) NSData *signature;
@property (nonatomic) NSInteger width, rows, seam, bodyTop;
@property (nonatomic) int lastDelta;
@property (nonatomic) CFTimeInterval referenceTime, referenceInterval, previewTime;
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
    }
    return self;
}

- (MTLongShotSlice *)mtSlice:(UIImage *)image rect:(CGRect)rect name:(NSString *)name error:(NSError **)error {
    MTLongShotSlice *slice = [MTLongImageComposer sliceFromScreenImage:image pixelRect:rect
        filePath:[self.directory stringByAppendingPathComponent:name] options:self.options
        cancellation:self.cancellation error:error];
    [slice discardAlignmentSignature];
    return slice;
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
        MTQuickStoreError(error, @"屏幕尺寸已变化，请保存已截内容"); return nil;
    }
    NSData *signature = MTQuickGrayImage(image.CGImage, rect);
    if (!signature) { MTQuickStoreError(error, @"画面分析缓冲区创建失败"); return nil; }
    MTQuickScrollResult *result = [MTQuickScrollResult new];
    if (!self.signature) {
        MTLongShotSlice *first = [self mtSlice:image rect:rect name:@"quick_first.jpg" error:error];
        if (!first) return nil;
        self.width = rect.size.width; self.rows = rect.size.height;
        self.signature = signature; self.referenceTime = timestamp;
        [self.slices addObject:first];
        result.match = (MTQuickScrollMatch){MTQuickScrollStill, 0, 0, 0, (int)self.rows, 0};
    } else {
        double elapsed = MAX(0.001, timestamp - self.referenceTime);
        double ratio = self.referenceInterval > 0 ? MIN(4, MAX(0.25, elapsed / self.referenceInterval)) : 1;
        int predicted = (int)lround(self.lastDelta * ratio);
        MTQuickScrollMatch match = MTQuickScrollMatchFrames(self.signature.bytes, signature.bytes, (int)self.rows, predicted);
        result.match = match;
        if (match.kind != MTQuickScrollUncertain) {
            NSInteger seam = self.seam >= 0 ? self.seam : match.bodyBottom - MIN(12, self.rows / 120);
            NSInteger bodyTop = self.seam >= 0 ? self.bodyTop : match.bodyTop;
            // No motion has no measured body boundaries yet; keep the complete first frame.
            if (match.kind == MTQuickScrollStill && self.seam < 0) seam = self.rows;
            MTQuickScrollCoverage next = _coverage;
            int minimum = final || self.seam < 0 ? 1 : MAX(24, self.rows / 5);
            int advance = MTQuickScrollAdvance(&next, match.delta, (int)(seam - bodyTop), minimum, 1);
            if (advance < 0 || seam > self.rows || seam <= bodyTop || seam - advance < bodyTop) {
                match.kind = MTQuickScrollUncertain; result.match = match;
            } else {
                if (advance > 0) {
                    // Persist only the new strip, plus a replaceable current footer. The
                    // same seam is frozen for all frames, so recorded pixels never move.
                    CGRect stripRect = CGRectMake(rect.origin.x, rect.origin.y + seam - advance, self.width, advance);
                    NSString *name = [NSString stringWithFormat:@"quick_%05lu.jpg", (unsigned long)self.slices.count];
                    MTLongShotSlice *strip = [self mtSlice:image rect:stripRect name:name error:error];
                    if (!strip) return nil;
                    MTLongShotSlice *tail = nil;
                    if (seam < self.rows) {
                        CGRect tailRect = CGRectMake(rect.origin.x, rect.origin.y + seam, self.width, self.rows - seam);
                        NSString *tailName = [NSString stringWithFormat:@"quick_tail_%05lu.jpg", (unsigned long)self.slices.count];
                        tail = [self mtSlice:image rect:tailRect name:tailName error:error];
                        if (!tail) return nil;
                    }
                    if (self.seam < 0) {
                        self.seam = seam; self.bodyTop = bodyTop;
                        self.slices.firstObject.cropBottomRows = self.rows - seam;
                    }
                    NSString *oldTail = self.tail.filePath;
                    self.tail = tail;
                    [self.slices addObject:strip];
                    if (oldTail) [NSFileManager.defaultManager removeItemAtPath:oldTail error:nil];
                }
                _coverage = next;
                // Still frames do not replace the reference: subpixel/one-pixel
                // slow scrolling must accumulate until it becomes measurable.
                if (match.kind == MTQuickScrollMoved) {
                    self.signature = signature;
                    self.lastDelta = match.delta;
                    self.referenceInterval = elapsed; self.referenceTime = timestamp;
                }
            }
        }
    }
    result.count = self.slices.count;
    result.totalHeight = self.rows + (NSInteger)_coverage.frontier;
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
    return result;
}

- (UIImage *)exportToURL:(NSURL *)url error:(NSError **)error {
    self.signature = nil;
    NSMutableArray *slices = [self.slices mutableCopy];
    if (self.tail) [slices addObject:self.tail];
    NSInteger cap = MTLongShotStitchPixelCap(MTLongShotProcessMemoryLimitBytes(), MTLongShotMaxCanvasPixels);
    return [MTLongImageComposer composedImageWithSlices:slices screenScale:self.scale outputURL:url
        maxPixels:cap options:self.options cancellation:self.cancellation progressBlock:nil outPixelSize:NULL error:error];
}
@end
