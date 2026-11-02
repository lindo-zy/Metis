#import <UIKit/UIKit.h>
@class MTChargingSnapshot;

@interface MTChargingCardView : UIView
- (void)updateSnapshot:(MTChargingSnapshot *)snapshot history:(NSArray<NSDictionary *> *)history time:(NSTimeInterval)time;
@end
