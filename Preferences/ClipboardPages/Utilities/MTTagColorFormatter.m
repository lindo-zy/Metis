//
//  MTTagColorFormatter.m
//  Mt
//

#import "MTTagColorFormatter.h"

#import <math.h>

@implementation MTTagColorFormatter

// 标签功能移除后自包含实现：把 #RRGGBBAA（8 位，可省略 #）规范化为大写
// #RRGGBBAA；无法解析时返回 nil（调用方回退默认色）。
+ (NSString *)normalizedHexColorFromString:(NSString *)hexColor {
    if (![hexColor isKindOfClass:NSString.class]) {
        return nil;
    }
    NSString *trimmed = [hexColor stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed hasPrefix:@"#"]) {
        trimmed = [trimmed substringFromIndex:1];
    }
    if ([trimmed length] != 8) {
        return nil;
    }
    NSCharacterSet *hexCharacters = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (NSUInteger index = 0; index < [trimmed length]; index++) {
        if (![hexCharacters characterIsMember:[trimmed characterAtIndex:index]]) {
            return nil;
        }
    }
    return [NSString stringWithFormat:@"#%@", trimmed.uppercaseString];
}

+ (UIColor *)colorFromHexColor:(NSString *)hexColor {
    NSString *candidate = [self normalizedHexColorFromString:hexColor] ?: @"#00000000";
    NSString *valueString = [candidate substringFromIndex:1];
    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:valueString];
    [scanner scanHexLongLong:&value];

    CGFloat red = (CGFloat)((value >> 24) & 0xFF) / 255.0;
    CGFloat green = (CGFloat)((value >> 16) & 0xFF) / 255.0;
    CGFloat blue = (CGFloat)((value >> 8) & 0xFF) / 255.0;
    CGFloat alpha = (CGFloat)(value & 0xFF) / 255.0;
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

+ (UIColor *)visibleColorFromHexColor:(NSString *)hexColor {
    UIColor *color = [self colorFromHexColor:hexColor];
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha] || alpha < 0.08) {
        return [UIColor tertiaryLabelColor];
    }
    return [UIColor colorWithRed:red green:green blue:blue alpha:MAX(alpha, 0.78)];
}

+ (UIColor *)borderColorFromHexColor:(NSString *)hexColor {
    UIColor *color = [self visibleColorFromHexColor:hexColor];
    CGFloat hue = 0.0;
    CGFloat saturation = 0.0;
    CGFloat brightness = 0.0;
    CGFloat alpha = 0.0;
    if (![color getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) {
        return [[UIColor labelColor] colorWithAlphaComponent:0.18];
    }

    CGFloat borderBrightness = saturation < 0.05 ? brightness * 0.87 : brightness * 0.94;
    return [UIColor colorWithHue:hue
                      saturation:MIN(saturation + 0.10, 1.0)
                      brightness:MAX(MIN(borderBrightness, 1.0), 0.0)
                           alpha:MAX(alpha, 0.86)];
}

+ (NSString *)hexColorFromColor:(UIColor *)color {
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;
    if (!color || ![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return @"#00000000";
    }

    NSInteger redValue = (NSInteger)lrint(MAX(0.0, MIN(1.0, red)) * 255.0);
    NSInteger greenValue = (NSInteger)lrint(MAX(0.0, MIN(1.0, green)) * 255.0);
    NSInteger blueValue = (NSInteger)lrint(MAX(0.0, MIN(1.0, blue)) * 255.0);
    NSInteger alphaValue = (NSInteger)lrint(MAX(0.0, MIN(1.0, alpha)) * 255.0);
    return [NSString
        stringWithFormat:@"#%02lX%02lX%02lX%02lX", (long)redValue, (long)greenValue, (long)blueValue, (long)alphaValue];
}

@end
