//
//  KayokoCustomJumpTableViewCell.h
//  Kayoko
//

#import <UIKit/UIKit.h>

@class KayokoCustomJump;

NS_ASSUME_NONNULL_BEGIN

@interface KayokoCustomJumpTableViewCell : UITableViewCell

- (void)configureWithJump:(KayokoCustomJump *)jump editing:(BOOL)editing;

@end

NS_ASSUME_NONNULL_END
