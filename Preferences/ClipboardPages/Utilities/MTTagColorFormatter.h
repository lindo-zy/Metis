//
//  MTTagColorFormatter.h
//  Mt
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTTagColorFormatter : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

+ (UIColor *)colorFromHexColor:(nullable NSString *)hexColor;
+ (UIColor *)visibleColorFromHexColor:(nullable NSString *)hexColor;
+ (UIColor *)borderColorFromHexColor:(nullable NSString *)hexColor;
+ (NSString *)hexColorFromColor:(nullable UIColor *)color;

@end

NS_ASSUME_NONNULL_END
