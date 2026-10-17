//
//  MTTagTableViewCell.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTTag;

NS_ASSUME_NONNULL_BEGIN

@interface MTTagTableViewCell : UITableViewCell

- (void)configureWithTag:(MTTag *)tag editing:(BOOL)editing;

@end

NS_ASSUME_NONNULL_END
