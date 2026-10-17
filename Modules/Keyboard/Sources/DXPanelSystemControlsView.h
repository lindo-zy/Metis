#import <UIKit/UIKit.h>
#import "DXPanelControlLayout.h"

@interface DXPanelSystemControlsView : UIView
@property(nonatomic, copy) void (^actionHandler)(NSString *action, NSNumber *value);
@property(nonatomic, readonly) BOOL showsToggleRow;
@property(nonatomic, readonly) BOOL showsSliderRow;
- (void)configureWithPreferences:(NSDictionary *)preferences preview:(BOOL)preview;
- (CGFloat)preferredHeightForWidth:(CGFloat)width;
- (void)configureDark:(BOOL)dark preview:(BOOL)preview;
- (void)applyState:(NSDictionary *)state busy:(BOOL)busy;
- (void)showMessage:(NSString *)message;
@end
