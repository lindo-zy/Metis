#import "MTLongShotFrameStore.h"
#import "../Output/MTLongPreviewCanvas.h"
#import <math.h>

@implementation MTLongShotFrameResult
@end
@interface MTLongShotFrameStore ()
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) MTLongShotOptions *options;
@property (nonatomic, strong) MTLongShotCancellation *cancellation;
@property (nonatomic, strong) NSMutableArray<MTLongShotSlice *> *slices;
@property (nonatomic, strong) NSData *anchorSignature;
@property (nonatomic, strong) MTLongPreviewCanvas *preview;
@property (nonatomic) NSInteger fixedTop;
@property (nonatomic) NSInteger fixedBottom;
@property (nonatomic) NSUInteger sequence;
@property (nonatomic) CGFloat scale;
@property (nonatomic) BOOL previewDisabled;
@end

static void MTFrameError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"com.lindo.metis.capture.longshot.frames" code:1
                                       userInfo:@{NSLocalizedDescriptionKey:message}];
}

// 只横向缩小，逐行保留原始纵向精度；临时 RGBA 内存上限约为 192 × 屏高 × 4。
// 所有候选与锚点都使用同一签名路径，不能与 JPEG 解码签名混比。
static NSData *MTFrameSignature(CGImageRef source, CGRect rect) {
    NSInteger width = MIN(192, (NSInteger)rect.size.width), height = (NSInteger)rect.size.height;
    if (!source || width < 1 || height < 128) return nil;
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, color,
                                                  (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color);
    if (!context) return nil;
    CGFloat scaleX = width / rect.size.width;
    CGContextScaleCTM(context, scaleX, 1);
    CGContextTranslateCTM(context, -rect.origin.x, (CGFloat)height - (CGFloat)CGImageGetHeight(source) + rect.origin.y);
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(source), CGImageGetHeight(source)), source);
    NSMutableData *signature = [NSMutableData dataWithLength:height * MTLongShotSigWidth];
    const uint8_t *buffer = CGBitmapContextGetData(context);
    for (NSInteger row = 0; row < height; row++)
        MTLongShotComputeRowSignature(buffer, width, CGBitmapContextGetBytesPerRow(context), row,
                                      (uint8_t *)signature.mutableBytes + row * MTLongShotSigWidth);
    CGContextRelease(context);
    return signature;
}

@implementation MTLongShotFrameStore
- (instancetype)initWithDirectory:(NSString *)directory options:(MTLongShotOptions *)options
                     cancellation:(MTLongShotCancellation *)cancellation scale:(CGFloat)scale {
    if ((self = [super init])) {
        _directory = [directory copy]; _options = options; _cancellation = cancellation;
        _scale = MAX(1, scale); _slices = [NSMutableArray array];
        _fixedTop = _fixedBottom = -1;
    }
    return self;
}
- (MTLongShotFrameResult *)consumeImage:(UIImage *)image pixelRect:(CGRect)rect error:(NSError **)error {
    if (self.cancellation.cancelled) return nil;
    if (!image.CGImage || !isfinite(rect.origin.x) || !isfinite(rect.origin.y) ||
        !isfinite(rect.size.width) || !isfinite(rect.size.height)) {
        MTFrameError(error, @"抓屏区域无效"); return nil;
    }
    rect = CGRectIntegral(CGRectIntersection(rect, CGRectMake(0, 0, CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage))));
    if (CGRectIsEmpty(rect) || CGRectIsNull(rect) || rect.size.height < 128) {
        MTFrameError(error, @"截取区域太小"); return nil;
    }
    MTLongShotSlice *anchor = self.slices.lastObject;
    if (anchor && (anchor.pixelWidth != rect.size.width || anchor.pixelHeight != rect.size.height)) {
        MTFrameError(error, @"屏幕尺寸已变化"); return nil;
    }
    NSData *signature = MTFrameSignature(image.CGImage, rect);
    if (!signature) { MTFrameError(error, @"帧分析失败"); return nil; }
    MTLongShotFrameMatch match = {MTLongShotMatchForward, 0, 0, 0};
    if (anchor) match = MTLongShotMatchFrames(self.anchorSignature.bytes, signature.bytes,
                                             rect.size.height, self.fixedTop, self.fixedBottom);
    if (self.cancellation.cancelled) return nil;
    NSString *path = [self.directory stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"longframe_%06lu.jpg", (unsigned long)++self.sequence]];
    // 只有可靠推进帧参与编码；判歧/回退帧直接跳过，不落盘、不参与正式结果。
    if (match.kind == MTLongShotMatchForward) {
        MTLongShotSlice *slice = [MTLongImageComposer sliceFromScreenImage:image pixelRect:rect filePath:path
                                        options:self.options cancellation:self.cancellation error:error];
        if (!slice || self.cancellation.cancelled) {
            [NSFileManager.defaultManager removeItemAtPath:path error:nil]; return nil;
        }
        [slice discardAlignmentSignature];
        if (anchor) {
            if (self.fixedTop < 0) { self.fixedTop = match.fixedTopRows; self.fixedBottom = match.fixedBottomRows; }
            NSInteger crop = slice.pixelHeight - self.fixedBottom - match.shiftRows;
            if (crop < self.fixedTop || crop >= slice.pixelHeight || match.shiftRows <= 0) {
                [NSFileManager.defaultManager removeItemAtPath:path error:nil];
                MTFrameError(error, @"拼接边界无效"); return nil;
            }
            // 接缝移到两帧共享正文的内侧，避开视口底缘的阴影/模糊栏。
            // 两侧裁切等量变化，累计高度仍只增加实际滚动位移。
            NSInteger overlap = slice.pixelHeight - self.fixedTop - self.fixedBottom - match.shiftRows;
            NSInteger inset = MIN(MAX(0, overlap / 2),
                                  MAX(0, anchor.pixelHeight - anchor.cropTopRows - self.fixedBottom - 1));
            anchor.cropBottomRows = self.fixedBottom + inset;
            slice.cropTopRows = crop - inset;
        }
        [self.slices addObject:slice];
        self.anchorSignature = signature;
    }
    MTLongShotFrameResult *result = [MTLongShotFrameResult new];
    result.match = match; result.count = self.slices.count;
    for (MTLongShotSlice *slice in self.slices) result.totalHeight += slice.renderedPixelHeight;
    if (match.kind == MTLongShotMatchForward && !self.previewDisabled) {
        if (!self.preview) self.preview = [[MTLongPreviewCanvas alloc] initWithWidthPixels:88 * self.scale
                                               maxPixels:300000 uiScale:self.scale cancellation:self.cancellation];
        result.preview = [self.preview updateWithSlices:self.slices];
        if (!result.preview) [self discardPreview];
    }
    result.previewUnavailable = self.previewDisabled;
    return result;
}
- (void)discardPreview { self.preview = nil; self.previewDisabled = YES; }
- (UIImage *)exportToURL:(NSURL *)url pixelSize:(CGSize *)size
               progress:(void (^)(NSInteger, NSInteger))progress error:(NSError **)error {
    [self discardPreview]; self.anchorSignature = nil;
    NSInteger cap = MTLongShotStitchPixelCap(MTLongShotProcessMemoryLimitBytes(), MTLongShotMaxCanvasPixels);
    return [MTLongImageComposer composedImageWithSlices:self.slices screenScale:self.scale outputURL:url
            maxPixels:cap options:self.options cancellation:self.cancellation progressBlock:progress outPixelSize:size error:error];
}
@end
