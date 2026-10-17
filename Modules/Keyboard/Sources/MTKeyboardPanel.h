#import <UIKit/UIKit.h>
@class MTCollectionView;

@interface MTKeyboardPanel : NSObject
+ (instancetype)sharedInstance;
- (void)registerToolbar:(MTCollectionView *)toolbar;
- (void)toolbarDetached:(MTCollectionView *)toolbar;
- (void)presentFromToolbar:(MTCollectionView *)toolbar panelSelector:(NSString *)selector;
- (void)dismiss;
@end
