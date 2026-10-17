//
//  MTHeaderCell.h
//  Mt
//

#import <Preferences/PSSpecifier.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTHeaderCell : PSTableCell
@property(nonatomic, strong) UIImageView *iconImageView;
@property(nonatomic, strong) UILabel *headerTitleLabel;
@property(nonatomic, strong) UILabel *subtitleLabel;
@end

NS_ASSUME_NONNULL_END
