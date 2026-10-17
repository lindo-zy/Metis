#import "MTSettingsStyle.h"

@implementation MTSettingsStyle

+ (nullable UIImage *)symbolPreferred:(NSString *)preferred fallback:(nullable NSString *)fallback {
    UIImage *image = [UIImage systemImageNamed:preferred];
    if (image) return image;
    return fallback.length ? [UIImage systemImageNamed:fallback] : nil;
}

+ (CGFloat)contentInset { return 16.0; }
+ (CGFloat)tileSide { return 29.0; }
+ (CGFloat)tileIconPointSize { return 22.0; }
+ (CGFloat)tileTextGap { return 12.0; }

@end
