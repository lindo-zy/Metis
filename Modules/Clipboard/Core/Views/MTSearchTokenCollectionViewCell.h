//
//  MTSearchTokenCollectionViewCell.h
//  Mt
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTSearchTokenCollectionViewCell : UICollectionViewCell
+ (NSString *)reuseIdentifier;
@property(nonatomic, assign, getter=isActiveFilterHighlighted) BOOL activeFilterHighlighted;
- (void)configureWithTitle:(NSString *)title icon:(nullable UIImage *)icon;
- (void)configureWithTitle:(NSString *)title
                      icon:(nullable UIImage *)icon
                  dotColor:(nullable UIColor *)dotColor
            dotBorderColor:(nullable UIColor *)dotBorderColor;
@end

NS_ASSUME_NONNULL_END
