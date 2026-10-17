//
//  MTCustomJumpTableViewCell.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTCustomJump;

NS_ASSUME_NONNULL_BEGIN

@interface MTCustomJumpTableViewCell : UITableViewCell

- (void)configureWithJump:(MTCustomJump *)jump editing:(BOOL)editing;

@end

NS_ASSUME_NONNULL_END
