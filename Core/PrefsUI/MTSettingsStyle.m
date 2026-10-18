#import "MTSettingsStyle.h"

@implementation MTSettingsStyle

+ (nullable UIImage *)symbolPreferred:(NSString *)preferred fallback:(nullable NSString *)fallback {
    UIImage *image = [UIImage systemImageNamed:preferred];
    if (image) return image;
    return fallback.length ? [UIImage systemImageNamed:fallback] : nil;
}

+ (nullable UIImage *)settingsSymbolImageNamed:(nullable NSString *)name {
    if (!name.length) return nil;
    if (@available(iOS 13.0, *)) {
        UIImage *symbol = [UIImage systemImageNamed:name];
        if (!symbol) return nil;
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:[self tileIconPointSize]];
        UIImage *configured = [symbol imageByApplyingSymbolConfiguration:configuration];
        // 统一 AlwaysTemplate：条目 imageView 的蓝色 tint 才能生效且尺寸对齐。
        return [configured ?: symbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return [UIImage systemImageNamed:name];
}

+ (CGFloat)contentInset { return 16.0; }
+ (CGFloat)tileSide { return 29.0; }
+ (CGFloat)tileIconPointSize { return 22.0; }
+ (CGFloat)tileTextGap { return 12.0; }
+ (CGFloat)rowVerticalPadding { return 12.0; }

@end
