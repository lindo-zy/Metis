#import <UIKit/UIKit.h>
@class DXCollectionView;

@interface DXKeyboardPanel : NSObject
+ (instancetype)sharedInstance;
- (void)registerToolbar:(DXCollectionView *)toolbar;
- (void)toolbarDetached:(DXCollectionView *)toolbar;
- (void)presentFromToolbar:(DXCollectionView *)toolbar panelSelector:(NSString *)selector;
- (void)dismiss;
@end
