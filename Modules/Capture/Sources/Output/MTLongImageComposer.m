#import "MTLongImageComposer.h"
#import "../Common/MTCaptureLog.h"
#import "../Common/MTLongShotAligner.h"
#import <ImageIO/ImageIO.h>
#import <math.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <os/proc.h>
#endif

const NSInteger MTLongShotMaxSlices = 200;
const NSInteger MTLongShotMaxCanvasHeight = 16384;
// SpringBoard 内还要容纳抓屏、预览与编码峰值；超预算的长图等比缩小并保留全部内容。
const NSInteger MTLongShotMaxCanvasPixels = 8 * 1000 * 1000;
const CGFloat MTLongShotSliceJPEGQuality = 0.95;
const CGFloat MTLongShotOutputJPEGQuality = 0.9;
const NSInteger MTLongShotCopyMaxPixelHeight = 8192;

#pragma mark - 分片

@interface MTLongShotSlice ()
@property (nonatomic, copy, readwrite) NSString *filePath;
@property (nonatomic, assign, readwrite) NSInteger pixelWidth;
@property (nonatomic, assign, readwrite) NSInteger pixelHeight;
@property (nonatomic, strong, readwrite) NSData *rowSignatures;
@end

@implementation MTLongShotSlice
- (void)discardAlignmentSignature { self.rowSignatures = [NSData data]; }
- (NSInteger)renderedPixelHeight { return MAX(0, self.pixelHeight - self.cropTopRows - self.cropBottomRows); }
@end

static NSError *MTLongShotError(NSString *message) {
    return [NSError errorWithDomain:@"com.lindo.metis.capture.longshot"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL MTLongShotWriteJPEG(CGImageRef image, NSURL *url, CGFloat quality) {
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)url, CFSTR("public.jpeg"), 1, NULL);
    if (!destination) return NO;
    CGImageDestinationAddImage(destination, image,
                               (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @(quality)});
    BOOL ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    return ok;
}

@implementation MTLongImageComposer

+ (nullable MTLongShotSlice *)sliceFromScreenImage:(UIImage *)screenImage
                                         pixelRect:(CGRect)pixelRect
                                          filePath:(NSString *)filePath
                                      cancellation:(MTLongShotCancellation *)cancellation
                                             error:(NSError **)error {
    return [self sliceFromScreenImage:screenImage pixelRect:pixelRect filePath:filePath
                              options:[[MTLongShotOptions alloc] initWithValues:@{}]
                         cancellation:cancellation error:error];
}
+ (nullable MTLongShotSlice *)sliceFromScreenImage:(UIImage *)screenImage
                                         pixelRect:(CGRect)pixelRect filePath:(NSString *)filePath
                                           options:(MTLongShotOptions *)options
                                      cancellation:(MTLongShotCancellation *)cancellation error:(NSError **)error {
    if (cancellation.cancelled || !screenImage.CGImage || filePath.length == 0) return nil;
    CGImageRef source = screenImage.CGImage;
    NSInteger srcW = (NSInteger)CGImageGetWidth(source);
    NSInteger srcH = (NSInteger)CGImageGetHeight(source);
    CGRect rect = CGRectIntersection(pixelRect, CGRectMake(0, 0, srcW, srcH));
    NSInteger w = (NSInteger)CGRectGetWidth(rect);
    NSInteger h = (NSInteger)CGRectGetHeight(rect);
    if (w < 1 || h < 1) {
        if (error) *error = MTLongShotError(@"分片像素矩形无效");
        return nil;
    }

    // 与 MTCaptureCoordinator mtCropImage 同一套解码约束：IOSurface 惰性子图必须
    // 绘制成独立位图；pixelRect 为顶部原点，CG 上下文为底部原点，需翻转对齐。
    CGContextRef context = CGBitmapContextCreate(NULL, (NSUInteger)w, (NSUInteger)h, 8, 0,
                                                 CGImageGetColorSpace(source),
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (!context) {
        if (error) *error = MTLongShotError(@"分片位图创建失败");
        return nil;
    }
    CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, w, h));
    CGContextClipToRect(context, CGRectMake(0, 0, w, h));
    CGContextTranslateCTM(context, -rect.origin.x, h - srcH + rect.origin.y);
    CGContextDrawImage(context, CGRectMake(0, 0, srcW, srcH), source);

    // 签名在释放位图前从缓冲直接采样，避免再做一次降采样解码。
    NSInteger bytesPerRow = (NSInteger)CGBitmapContextGetBytesPerRow(context);
    uint8_t *buffer = (uint8_t *)CGBitmapContextGetData(context);
    NSMutableData *signatures = [NSMutableData dataWithLength:(NSUInteger)h * (NSUInteger)MTLongShotSigWidth];
    uint8_t *sigBytes = (uint8_t *)signatures.mutableBytes;
    if (buffer && sigBytes) {
        for (NSInteger r = 0; r < h; r++) {
            MTLongShotComputeRowSignature(buffer, w, bytesPerRow, r, sigBytes + r * MTLongShotSigWidth);
        }
    }

    CGImageRef cropped = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!cropped) {
        if (error) *error = MTLongShotError(@"分片图像提取失败");
        return nil;
    }

    if (cancellation.cancelled) { CGImageRelease(cropped); return nil; }
    BOOL written = MTLongShotWriteJPEG(cropped, [NSURL fileURLWithPath:filePath],
                                       options.sliceQuality);
    CGImageRelease(cropped);
    if (!written) {
        if (error) *error = MTLongShotError(@"分片写入磁盘失败");
        return nil;
    }

    MTLongShotSlice *slice = [[MTLongShotSlice alloc] init];
    slice.filePath = filePath;
    slice.pixelWidth = w;
    slice.pixelHeight = h;
    slice.rowSignatures = signatures;
    return slice;
}

#pragma mark - 拼接

+ (nullable UIImage *)composedImageWithSlices:(NSArray<MTLongShotSlice *> *)slices
                                  screenScale:(CGFloat)screenScale
                                    outputURL:(NSURL *)outputURL
                                    maxPixels:(NSInteger)maxPixels
                                 cancellation:(MTLongShotCancellation *)cancellation
                                progressBlock:(nullable void (^)(NSInteger done, NSInteger total))progressBlock
                                 outPixelSize:(CGSize *)outPixelSize
                                        error:(NSError **)error {
    return [self composedImageWithSlices:slices screenScale:screenScale outputURL:outputURL maxPixels:maxPixels
                                options:[[MTLongShotOptions alloc] initWithValues:@{}] cancellation:cancellation
                          progressBlock:progressBlock outPixelSize:outPixelSize error:error];
}
+ (nullable UIImage *)composedImageWithSlices:(NSArray<MTLongShotSlice *> *)slices
                                  screenScale:(CGFloat)screenScale outputURL:(NSURL *)outputURL
                                    maxPixels:(NSInteger)maxPixels options:(MTLongShotOptions *)options
                                 cancellation:(MTLongShotCancellation *)cancellation
                                progressBlock:(nullable void (^)(NSInteger done, NSInteger total))progressBlock
                                 outPixelSize:(CGSize *)outPixelSize error:(NSError **)error {
    if (cancellation.cancelled) return nil;
    if (slices.count == 0) {
        if (error) *error = MTLongShotError(@"没有可拼接的分片");
        return nil;
    }

    NSInteger sliceCount = (NSInteger)slices.count;
    // 进度口径 2n：前 n 步累计已确认偏移，后 n 步逐片解码绘制。
    if (progressBlock) progressBlock(0, sliceCount * 2);

    // 采用入列时已确认的重叠累计总高：offset 为顶部原点的原始像素。
    NSInteger totalHeight = 0;
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithCapacity:slices.count];
    for (NSInteger i = 0; i < sliceCount; i++) {
        if (cancellation.cancelled) return nil;
        MTLongShotSlice *slice = slices[i];
        if (slice.cropTopRows < 0 || slice.cropBottomRows < 0 || slice.renderedPixelHeight <= 0 ||
            slice.pixelWidth != slices[0].pixelWidth) {
            if (error) *error = MTLongShotError(@"分片裁切位置无效");
            return nil;
        }
        [offsets addObject:@(totalHeight)];
        totalHeight += slice.renderedPixelHeight;
        if (progressBlock) progressBlock(i + 1, sliceCount * 2);
    }

    size_t availableBytes = 0;
#if TARGET_OS_IPHONE
    availableBytes = os_proc_available_memory();
#endif
    NSInteger pixelBudget = MTLongShotCanvasPixelBudget(availableBytes, MIN(maxPixels, MTLongShotMaxCanvasPixels));
    if (cancellation.cancelled) return nil;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef canvas = NULL;
    CGSize canvasSize = CGSizeZero;
    CGFloat scale = 1.0;
    // 分配失败时按半量预算重试；不追加重复分片，也不丢弃图尾。
    while (!cancellation.cancelled) {
        if (!MTLongShotCanvasGeometry(slices[0].pixelWidth, totalHeight, options.maxCanvasHeight,
                                      pixelBudget, &canvasSize, &scale)) break;
        canvas = CGBitmapContextCreate(NULL, (NSUInteger)canvasSize.width, (NSUInteger)canvasSize.height, 8, 0,
                                      colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        if (canvas || pixelBudget <= 256000) break;
        pixelBudget = MAX(256000, pixelBudget / 2);
    }
    CGColorSpaceRelease(colorSpace);
    if (!canvas) {
        if (error) *error = MTLongShotError(@"拼接画布创建失败");
        return nil;
    }
    NSInteger canvasW = (NSInteger)canvasSize.width, canvasH = (NSInteger)canvasSize.height;
    MTCaptureLogInfo(@"long shot canvas budget (slices=%ld pixels=%ld available=%llu canvas=%ldx%ld)",
              (long)sliceCount, (long)pixelBudget, (unsigned long long)availableBytes, (long)canvasW, (long)canvasH);
    CGContextSetFillColorWithColor(canvas, [UIColor blackColor].CGColor);
    CGContextFillRect(canvas, CGRectMake(0, 0, canvasW, canvasH));
    CGContextSetInterpolationQuality(canvas, kCGInterpolationMedium);

    BOOL drewAll = YES;
    for (NSInteger i = 0; i < sliceCount; i++) {
        if (cancellation.cancelled) { CGContextRelease(canvas); return nil; }
        // 绘制进度在循环体头部上报：单片解码失败 continue 时进度仍单调推进。
        if (progressBlock) progressBlock(sliceCount + i, sliceCount * 2);
        @autoreleasepool {
            MTLongShotSlice *slice = slices[i];
            CGImageSourceRef source = CGImageSourceCreateWithURL(
                (__bridge CFURLRef)[NSURL fileURLWithPath:slice.filePath], NULL);
            if (!source) { drewAll = NO; continue; }
            // 超长图已经缩放时直接按目标尺寸解码，避免逐片仍分配整屏大小位图。
            CGImageRef tile = scale < 1.0
                ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
                    (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                    (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:
                        @(MAX(1, (NSInteger)ceil(MAX(slice.pixelWidth, slice.pixelHeight) * scale))),
                    (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES})
                : CGImageSourceCreateImageAtIndex(source, 0,
                    (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache: @NO});
            CFRelease(source);
            if (!tile) { drewAll = NO; continue; }

            NSInteger offset = offsets[i].integerValue;
            MTLongShotDrawTile(canvas, tile, canvasH, offset, slice.pixelWidth, slice.pixelHeight,
                               slice.cropTopRows, slice.cropBottomRows, scale);
            CGImageRelease(tile);
        }
    }

    if (progressBlock) progressBlock(sliceCount * 2, sliceCount * 2);   // 进入编码阶段

    CGImageRef composed = CGBitmapContextCreateImage(canvas);
    CGContextRelease(canvas);
    if (!composed || !drewAll) {
        if (composed) CGImageRelease(composed);
        if (error) *error = MTLongShotError(@"分片绘制失败");
        return nil;
    }

    if (cancellation.cancelled) { CGImageRelease(composed); return nil; }
    BOOL written = MTLongShotWriteJPEG(composed, outputURL, options.outputQuality);
    if (outPixelSize) *outPixelSize = CGSizeMake(canvasW, canvasH);
    CGImageRelease(composed);
    if (!written) {
        if (error) *error = MTLongShotError(@"长图编码失败");
        return nil;
    }

    // 文件回读：resultImage 以磁盘为后端，拼接画布立即释放不驻留。
    if (cancellation.cancelled) return nil;
    CGImageSourceRef outSource = CGImageSourceCreateWithURL((__bridge CFURLRef)outputURL, NULL);
    CGImageRef outImage = outSource
        ? CGImageSourceCreateImageAtIndex(outSource, 0,
                                          (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache: @NO})
        : NULL;
    if (outSource) CFRelease(outSource);
    if (!outImage) {
        if (error) *error = MTLongShotError(@"长图回读失败");
        return nil;
    }
    UIImage *result = [UIImage imageWithCGImage:outImage scale:screenScale orientation:UIImageOrientationUp];
    CGImageRelease(outImage);
    if (!result) {
        if (error) *error = MTLongShotError(@"长图回读失败");
    }
    return result;
}

@end
