#import "MTWatermarkRenderer.h"
#import "../../../../Core/MTPathResolver.h"
#import <ImageIO/ImageIO.h>

static NSString *MTWatermarkRoot(void) {
    return [MTPrivateDataRoot() stringByAppendingPathComponent:@"Capture/Watermarks"];
}
static NSString *MTWatermarkPath(NSString *identifier) {
    if (![[NSUUID alloc] initWithUUIDString:identifier]) return nil;
    return [MTWatermarkRoot() stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"png"]];
}
static void MTWatermarkError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"com.lindo.metis.capture.watermark" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
}
static UIImage *MTWatermarkLoad(NSURL *url) {
    unsigned long long bytes = [[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil] fileSize];
    if (!bytes || bytes > 40 * 1024 * 1024) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;
    CGImageRef cg = CGImageSourceGetCount(source) == 1 ? CGImageSourceCreateThumbnailAtIndex(source, 0,
        (__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
            (id)kCGImageSourceCreateThumbnailWithTransform:@YES,
            (id)kCGImageSourceThumbnailMaxPixelSize:@2048, (id)kCGImageSourceShouldCacheImmediately:@YES}) : NULL;
    CFRelease(source);
    UIImage *image = cg ? [UIImage imageWithCGImage:cg] : nil;
    if (cg) CGImageRelease(cg);
    return image;
}
@implementation MTWatermarkRenderer
+ (NSArray<NSString *> *)materials {
    NSMutableArray *materials = [NSMutableArray new];
    NSArray *entries = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:MTWatermarkRoot() error:nil]
        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *entry in entries) {
        if ([entry.pathExtension isEqualToString:@"png"] && [[NSUUID alloc] initWithUUIDString:entry.stringByDeletingPathExtension])
            [materials addObject:entry.stringByDeletingPathExtension];
    }
    return materials;
}
+ (UIImage *)materialForIdentifier:(NSString *)identifier {
    NSString *path = MTWatermarkPath(identifier);
    return path ? MTWatermarkLoad([NSURL fileURLWithPath:path]) : nil;
}
+ (NSString *)importURL:(NSURL *)url error:(NSError **)error {
    if (!url.isFileURL) { MTWatermarkError(error, @"请选择本地图片"); return nil; }
    UIImage *image = MTWatermarkLoad(url);
    if (!image) { MTWatermarkError(error, @"请选择 40MB 以内的静态图片，透明 PNG 可保留透明背景"); return nil; }
    NSData *data = UIImagePNGRepresentation(image);
    if (!data) { MTWatermarkError(error, @"水印素材编码失败"); return nil; }
    NSString *identifier = NSUUID.UUID.UUIDString;
    @synchronized(self) {
        if (self.materials.count >= 32) { MTWatermarkError(error, @"最多保存 32 个素材，请先删除不用的素材"); return nil; }
        if (![NSFileManager.defaultManager createDirectoryAtPath:MTWatermarkRoot() withIntermediateDirectories:YES attributes:nil error:error] ||
            ![data writeToFile:MTWatermarkPath(identifier) options:NSDataWritingAtomic error:error]) return nil;
    }
    return identifier;
}
+ (BOOL)removeMaterial:(NSString *)identifier error:(NSError **)error {
    NSString *path = MTWatermarkPath(identifier);
    return path && [NSFileManager.defaultManager removeItemAtPath:path error:error];
}
+ (UIImage *)renderImage:(UIImage *)image configuration:(MTWatermarkConfiguration *)style framed:(BOOL)framed {
    if (![style appliesToFramedImage:framed]) return image;
    UIImage *material = [self materialForIdentifier:style.materialIdentifier];
    if (!image.CGImage || !material.CGImage) return nil;
    CGRect rect = [style rectForCanvas:image.size material:material.size];
    if (CGRectIsEmpty(rect)) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
    format.scale = image.scale;
    format.opaque = NO;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    @try {
        return [[[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format]
            imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [image drawAtPoint:CGPointZero];
                [material drawInRect:rect blendMode:kCGBlendModeNormal alpha:style.opacity];
            }];
    } @catch (NSException *exception) {
        return nil;
    }
}
@end
