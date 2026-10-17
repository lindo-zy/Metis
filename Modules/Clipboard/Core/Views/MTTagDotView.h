//
//  MTTagDotView.h
//  Mt
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTTagDotView : UIView

@property(nonatomic, assign) CGFloat dotDiameter;
@property(nonatomic, assign) CGFloat borderWidth;

- (void)configureWithFillColor:(nullable UIColor *)fillColor borderColor:(nullable UIColor *)borderColor;
- (void)configureNoTagWithTintColor:(UIColor *)tintColor;

@end

NS_ASSUME_NONNULL_END
