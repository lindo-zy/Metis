#import "MTSettingsStyle.h"

@implementation MTSettingsStyle

+ (UIColor *)tileColorForName:(nullable NSString *)name {
    // 设计稿瓦片色映射：首页五分类与全局/新建动作页共用一套 token。
    if ([name isEqualToString:@"blue"]) return [UIColor systemBlueColor];
    if ([name isEqualToString:@"green"]) return [UIColor systemGreenColor];
    if ([name isEqualToString:@"purple"]) return [UIColor systemPurpleColor];
    if ([name isEqualToString:@"orange"]) return [UIColor systemOrangeColor];
    if ([name isEqualToString:@"yellow"]) return [UIColor systemYellowColor];
    if ([name isEqualToString:@"indigo"]) return [UIColor systemIndigoColor];
    if ([name isEqualToString:@"teal"]) return [UIColor systemTealColor];
    return [UIColor systemGrayColor];
}

+ (nullable UIImage *)symbolPreferred:(NSString *)preferred fallback:(nullable NSString *)fallback {
    UIImage *image = [UIImage systemImageNamed:preferred];
    if (image) return image;
    return fallback.length ? [UIImage systemImageNamed:fallback] : nil;
}

+ (CGFloat)tileSide { return 29.0; }
+ (CGFloat)tileCornerRadius { return 6.5; }
+ (CGFloat)tileIconPointSize { return 16.0; }

@end
