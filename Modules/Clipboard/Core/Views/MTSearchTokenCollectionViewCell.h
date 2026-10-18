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
@end

NS_ASSUME_NONNULL_END
