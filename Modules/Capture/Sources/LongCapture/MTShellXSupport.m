#import "MTShellXSupport.h"
#import "../Common/MTLongShotControl.h"
#import <math.h>
#import <stdlib.h>

NSData * _Nullable MTShellXFastHash(UIImage *image) {
    if (!image || image.size.width < 1 || image.size.height < 1) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(20, 20) format:format];
    UIImage *thumb = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0, 0, 20, 20)];
    }];
    return UIImageJPEGRepresentation(thumb, 0.1);
}

uint8_t * _Nullable MTShellXCreateStrip(UIImage *image, NSInteger sw, NSInteger sh) {
    if (!image || sw < 1 || sh < 1) return NULL;
    CGImageRef cg = image.CGImage;
    if (!cg) return NULL;
    size_t bytesPerRow = (size_t)sw * 4;
    uint8_t *buffer = calloc(1, bytesPerRow * (size_t)sh);
    if (!buffer) return NULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    // 与 SHELLX 相同的位图布局：RGBA8、大端序、预乘 alpha。
    CGContextRef context = CGBitmapContextCreate(buffer, sw, sh, 8, bytesPerRow, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) { free(buffer); return NULL; }
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextTranslateCTM(context, -(CGFloat)sw * 0.1, 0);
    CGContextDrawImage(context, CGRectMake(0, 0, sw, sh), cg);
    CGContextRelease(context);
    // 位图上下文行 0 是底部；翻回顶部行序，后续偏移按物理方向计算。
    uint8_t *flipped = malloc(bytesPerRow * (size_t)sh);
    if (!flipped) { free(buffer); return NULL; }
    for (NSInteger row = 0; row < sh; row++) {
        memcpy(flipped + row * bytesPerRow, buffer + (sh - 1 - row) * bytesPerRow, bytesPerRow);
    }
    free(buffer);
    return flipped;
}

void MTShellXRecordingStripSize(CGFloat pixelWidth, CGFloat pixelHeight,
                                NSInteger *outWidth, NSInteger *outHeight) {
    NSInteger sw = (NSInteger)(pixelWidth * 0.25);
    NSInteger sh = (NSInteger)(pixelHeight * 0.25);
    *outWidth = MAX(64, sw);
    *outHeight = MAX(64, sh);
}

NSData * _Nullable MTShellXRowSignature(UIImage *image, NSInteger *outRows,
                                        NSInteger *outStripWidth, NSInteger *outBytesPerRow) {
    if (outRows) *outRows = 0;
    if (outStripWidth) *outStripWidth = 0;
    if (outBytesPerRow) *outBytesPerRow = 0;
    if (!image) return nil;
    CGImageRef cg = image.CGImage;
    if (!cg) return nil;
    CGFloat pixelWidth = CGImageGetWidth(cg), pixelHeight = CGImageGetHeight(cg);
    if (pixelWidth < 16 || pixelHeight < 16) return nil;
    NSInteger downW = MAX(64, (NSInteger)(pixelWidth / 4));
    NSInteger downH = MAX(64, (NSInteger)(pixelHeight / 4));
    NSInteger stripW = (NSInteger)(downW * 0.8);
    if (stripW < 16) return nil;
    uint8_t *strip = MTShellXCreateStrip(image, stripW, downH);
    if (!strip) return nil;
    NSData *signature = [NSData dataWithBytes:strip length:(NSUInteger)(stripW * 4 * downH)];
    free(strip);
    if (outRows) *outRows = downH;
    if (outStripWidth) *outStripWidth = stripW;
    if (outBytesPerRow) *outBytesPerRow = stripW * 4;
    return signature;
}

uint64_t MTShellXStripSAD(const uint8_t *prev, const uint8_t *cur, NSInteger bytesPerRow,
                          NSInteger dy, NSInteger rows, NSInteger comparePixels) {
    if (!prev || !cur || dy < 0 || rows <= 0) return UINT64_MAX;
    NSInteger pixels = comparePixels > 0 ? comparePixels : bytesPerRow / 4;
    if (pixels < 1) return UINT64_MAX;
    uint64_t total = 0;
    for (NSInteger row = 0; row < rows; row++) {
        const uint8_t *a = prev + (size_t)row * bytesPerRow;
        const uint8_t *b = cur + (size_t)(dy + row) * bytesPerRow;
        for (NSInteger pixel = 0; pixel < pixels; pixel += 4) {
            const uint8_t *pa = a + (size_t)pixel * 4;
            const uint8_t *pb = b + (size_t)pixel * 4;
            total += abs(pa[0] - pb[0]) + abs(pa[1] - pb[1]) + abs(pa[2] - pb[2]);
        }
    }
    return total;
}

NSInteger MTShellXMatchScroll(const uint8_t *prev, const uint8_t *cur, NSInteger bytesPerRow,
                              NSInteger rows, NSInteger winRows, NSInteger comparePixels) {
    if (!prev || !cur || rows < 8 || winRows < 8 || winRows > rows) return -1;
    NSInteger pixels = comparePixels > 0 ? comparePixels : bytesPerRow / 4;
    if (pixels < 4) return -1;
    // 阈值与 SHELLX 同构：单位是「(win/2) 组 × 每组 (pixels/4) 个采样」的放缩。
    uint64_t similarThreshold = (uint64_t)(winRows / 2) * (uint64_t)(pixels / 4) * 5;
    uint64_t acceptThreshold = (uint64_t)(winRows / 2) * (uint64_t)(pixels / 4) * 75;
    NSInteger maxDy = rows - winRows;
    if (maxDy < 1) return -1;
    // 粗扫步长 2，记录最优候选；再在候选邻域步长 1 细化。
    NSInteger bestDy = -1;
    uint64_t bestCost = UINT64_MAX;
    for (NSInteger dy = 1; dy <= maxDy; dy += 2) {
        uint64_t cost = MTShellXStripSAD(prev, cur, bytesPerRow, dy, winRows, pixels);
        if (cost < bestCost) { bestCost = cost; bestDy = dy; }
    }
    if (bestDy < 0) return -1;
    for (NSInteger dy = MAX(1, bestDy - 2); dy <= MIN(maxDy, bestDy + 2); dy++) {
        uint64_t cost = MTShellXStripSAD(prev, cur, bytesPerRow, dy, winRows, pixels);
        if (cost < bestCost) { bestCost = cost; bestDy = dy; }
    }
    if (bestCost > acceptThreshold) return -1;
    if (bestDy == 0 || bestCost < similarThreshold) return 0;
    return bestDy;
}

UIImage * _Nullable MTShellXComposeSlices(NSArray<NSString *> *slicePaths,
                                          NSString *outputPath,
                                          NSInteger maxCanvasHeight,
                                          double quality,
                                          CGSize *outSize,
                                          NSError **error) {
    if (outSize) *outSize = CGSizeZero;
    if (error) *error = nil;
    NSMutableArray<UIImage *> *slices = [NSMutableArray array];
    CGFloat width = 0, totalHeight = 0, scale = 0;
    for (NSString *path in slicePaths) {
        UIImage *slice = [UIImage imageWithContentsOfFile:path];
        if (!slice || slice.size.width < 1 || slice.size.height < 1) continue;
        if (width == 0) { width = slice.size.width; scale = slice.scale; }
        if (fabs(slice.size.width - width) > 1) continue; // 宽度不一致的坏片跳过
        [slices addObject:slice];
        totalHeight += slice.size.height;
    }
    if (!slices.count || width < 1 || totalHeight < 1) {
        if (error) *error = [NSError errorWithDomain:@"MTShellXSupport" code:1
                                          userInfo:@{NSLocalizedDescriptionKey: @"没有可合并的切片"}];
        return nil;
    }
    CGFloat baseScale = scale > 0 ? scale : 1;
    CGFloat fullHeightPixels = totalHeight * baseScale;
    NSInteger maxHeightPixels = maxCanvasHeight > 0 ? maxCanvasHeight : 16384;
    NSInteger budgetPixels = MTLongShotCanvasPixelBudget(MTLongShotAvailableMemoryBytes(),
                                                         (NSInteger)(width * baseScale * fullHeightPixels));
    // 先按限高收缩，再按像素预算收缩；两者都只降不升。
    CGFloat shrink = MIN(1.0, (CGFloat)maxHeightPixels / fullHeightPixels);
    CGFloat pixels = width * baseScale * fullHeightPixels * shrink;
    if (pixels > (CGFloat)budgetPixels) shrink *= sqrt((CGFloat)budgetPixels / pixels);
    shrink = MAX(shrink, 0.05);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = baseScale * shrink;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(width, totalHeight) format:format];
    UIImage *output = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGFloat yOffset = 0;
        for (UIImage *slice in slices) {
            // 片高 +0.5pt 重叠绘制，消除相邻切片的取整接缝。
            [slice drawInRect:CGRectMake(0, yOffset, width, slice.size.height + 0.5)];
            yOffset += slice.size.height;
        }
    }];
    NSData *data = UIImageJPEGRepresentation(output, MIN(MAX(quality, 0.5), 1.0));
    if (!data || ![data writeToFile:outputPath atomically:YES]) {
        if (error) *error = [NSError errorWithDomain:@"MTShellXSupport" code:3
                                          userInfo:@{NSLocalizedDescriptionKey: @"长图编码失败"}];
        return nil;
    }
    if (outSize) *outSize = CGSizeMake(width * baseScale * shrink, totalHeight * baseScale * shrink);
    return output;
}
