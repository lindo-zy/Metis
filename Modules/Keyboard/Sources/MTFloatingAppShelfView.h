#import <UIKit/UIKit.h>

@interface MTFloatingAppShelfView : UIView
@property(nonatomic, copy) void (^contentChanged)(void);
@property(nonatomic, readonly) BOOL unlocked;
- (void)refresh;
@end
