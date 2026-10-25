#import "MTShellXSupport.h"
#import "../Common/MTLongShotControl.h"
#import <math.h>
#import <stdlib.h>
#import <ImageIO/ImageIO.h>
#import "../Common/MTLongShotAligner.h"

UIImage *MTShellXThumbnail(UIImage *image, NSInteger maxDimension) {
    CGImageRef source = image.CGImage;
    if (!source || maxDimension < 1) return nil;
    CGFloat factor = MIN(1.0, (CGFloat)maxDimension / MAX(CGImageGetWidth(source), CGImageGetHeight(source)));
    size_t w = MAX(1, (size_t)(CGImageGetWidth(source) * factor));
    size_t h = MAX(1, (size_t)(CGImageGetHeight(source) * factor));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, w, h, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextDrawImage(context, CGRectMake(0, 0, w, h), source);
    CGImageRef cg = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    UIImage *result = cg ? [UIImage imageWithCGImage:cg scale:1 orientation:UIImageOrientationUp] : nil;
    if (cg) CGImageRelease(cg);
    return result;
}

BOOL MTShellXWriteSlice(UIImage *image, NSInteger top, NSInteger height, NSString *path) {
    CGImageRef cg = image.CGImage;
    if (!cg || !path.length || top < 0 || height < 1 || top > (NSInteger)CGImageGetHeight(cg) ||
        height > (NSInteger)CGImageGetHeight(cg) - top) return NO;
    CGImageRef piece = CGImageCreateWithImageInRect(cg, CGRectMake(0, top, CGImageGetWidth(cg), height));
    if (!piece) return NO;
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.jpeg"), 1, NULL);
    BOOL ok = NO;
    if (dest) {
        CGImageDestinationAddImage(dest, piece, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@0.92});
        ok = CGImageDestinationFinalize(dest);
        CFRelease(dest);
    }
    CGImageRelease(piece);
    return ok;
}

NSData * _Nullable MTShellXRowSignature(UIImage *image, NSInteger *outRows,
                                        NSInteger *outStripWidth, NSInteger *outBytesPerRow) {
    if (outRows) *outRows = 0;
    if (outStripWidth) *outStripWidth = 0;
    if (outBytesPerRow) *outBytesPerRow = 0;
    CGImageRef cg = image.CGImage;
    if (!cg) return nil;
    NSInteger width = CGImageGetWidth(cg), rows = CGImageGetHeight(cg);
    if (width < 16 || width > 8192 || rows < 128 || rows > 16384 || width > 24000000 / rows) return nil;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, rows, 8, 0, space,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextDrawImage(context, CGRectMake(0, 0, width, rows), cg);
    // 与 MTLongImageComposer 的原生像素提取使用同一行序和横向取样，
    // 不翻转行序、不先把文字缩糊；只留下每行 64 字节，内存与帧数无关。
    NSMutableData *signature = [NSMutableData dataWithLength:(NSUInteger)rows * MTLongShotSigWidth];
    const uint8_t *buffer = CGBitmapContextGetData(context);
    NSInteger bpr = CGBitmapContextGetBytesPerRow(context);
    for (NSInteger row = 0; row < rows; row++)
        MTLongShotComputeRowSignature(buffer, width, bpr, row,
            (uint8_t *)signature.mutableBytes + row * MTLongShotSigWidth);
    CGContextRelease(context);
    if (outRows) *outRows = rows;
    if (outStripWidth) *outStripWidth = MTLongShotSigWidth;
    if (outBytesPerRow) *outBytesPerRow = MTLongShotSigWidth;
    return signature;
}


UIImage * _Nullable MTShellXComposeSlices(NSArray<NSString *> *slicePaths, NSString *outputPath,
                                          NSInteger maxCanvasHeight, double quality,
                                          MTLongShotCancellation *cancellation, CGSize *outSize, NSError **error) {
    if (outSize) *outSize = CGSizeZero;
    if (error) *error = nil;
    NSInteger width = 0, totalHeight = 0;
    NSMutableArray<NSNumber *> *heights = [NSMutableArray array];
    NSString *failure = nil;
    // 只读 JPEG 元数据；禁止把全部分片解码后同时保存在数组内。
    for (NSString *path in slicePaths) {
        if (cancellation.cancelled) return nil;
        CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
        NSDictionary *properties = src ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL)) : nil;
        if (src) CFRelease(src);
        NSInteger w = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] integerValue];
        NSInteger h = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] integerValue];
        if (w < 1 || h < 1 || (width && width != w) || totalHeight > NSIntegerMax - h) { failure = @"分片文件损坏或尺寸不一致"; break; }
        width = w; totalHeight += h; [heights addObject:@(h)];
    }
    if (!failure && (!heights.count || totalHeight < 1)) failure = @"没有可合并的切片";
    CGContextRef canvas = NULL;
    CGSize size = CGSizeZero;
    CGFloat scale = 1;
    if (!failure) {
        NSInteger budget = MTLongShotCanvasPixelBudget(MTLongShotAvailableMemoryBytes(), 8000000);
        budget = MIN(budget, MTLongShotStitchPixelCap(MTLongShotProcessMemoryLimitBytes(), 8000000));
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        while (!cancellation.cancelled && MTLongShotCanvasGeometry(width, totalHeight, maxCanvasHeight, budget, &size, &scale)) {
            canvas = CGBitmapContextCreate(NULL, (size_t)size.width, (size_t)size.height, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            if (canvas || budget <= 256000) break;
            budget = MAX(256000, budget / 2);
        }
        CGColorSpaceRelease(space);
        if (!canvas) failure = @"拼接画布创建失败";
    }
    if (canvas) {
        NSInteger offset = 0;
        for (NSUInteger i = 0; i < slicePaths.count; i++) {
            if (cancellation.cancelled) break;
            @autoreleasepool {
                CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:slicePaths[i]], NULL);
                CGImageRef tile = src ? CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)@{
                    (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                    (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@(MAX(1, (NSInteger)ceil(MAX(width, heights[i].integerValue) * scale))),
                    (__bridge NSString *)kCGImageSourceShouldCacheImmediately:@YES}) : NULL;
                if (src) CFRelease(src);
                if (!tile) { failure = @"分片解码失败"; break; }
                MTLongShotDrawTile(canvas, tile, size.height, offset, width, heights[i].integerValue, 0, 0, scale);
                CGImageRelease(tile);
                offset += heights[i].integerValue;
            }
        }
        CGImageRef output = !failure && !cancellation.cancelled ? CGBitmapContextCreateImage(canvas) : NULL;
        CGContextRelease(canvas);
        if (output) {
            CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:outputPath], CFSTR("public.jpeg"), 1, NULL);
            BOOL written = NO;
            if (dest) {
                CGImageDestinationAddImage(dest, output, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@(MIN(MAX(quality, 0.5), 1.0))});
                written = CGImageDestinationFinalize(dest); CFRelease(dest);
            }
            CGImageRelease(output);
            if (!written) failure = @"长图编码失败";
        } else if (!failure) failure = @"长图合成失败";
    }
    if (cancellation.cancelled) return nil;
    if (failure) {
        if (error) *error = [NSError errorWithDomain:@"MTShellXSupport" code:1 userInfo:@{NSLocalizedDescriptionKey:failure}];
        return nil;
    }
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:outputPath], NULL);
    CGImageRef cg = src ? CGImageSourceCreateImageAtIndex(src, 0, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO}) : NULL;
    if (src) CFRelease(src);
    UIImage *result = cg ? [UIImage imageWithCGImage:cg scale:1 orientation:UIImageOrientationUp] : nil;
    if (cg) CGImageRelease(cg);
    if (outSize) *outSize = size;
    if (!result && error) *error = [NSError errorWithDomain:@"MTShellXSupport" code:2 userInfo:@{NSLocalizedDescriptionKey:@"长图回读失败"}];
    return result;
}
