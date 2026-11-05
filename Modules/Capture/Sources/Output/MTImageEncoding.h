#import <UIKit/UIKit.h>

/// 透明套壳位图不能经过 JPEG；opaque renderer 的普通结果沿用原有 JPEG 路径。
static inline BOOL MTImageRequiresPNG(UIImage *image) {
    if (!image.CGImage) return NO;
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo(image.CGImage);
    return alpha == kCGImageAlphaFirst || alpha == kCGImageAlphaLast ||
        alpha == kCGImageAlphaPremultipliedFirst || alpha == kCGImageAlphaPremultipliedLast || alpha == kCGImageAlphaOnly;
}
