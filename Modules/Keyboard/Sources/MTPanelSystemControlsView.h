#import <UIKit/UIKit.h>
#import "MTPanelControlLayout.h"

@interface MTPanelSystemControlsView : UIView
@property(nonatomic, copy) void (^actionHandler)(NSString *action, NSNumber *value);
@property(nonatomic, readonly) BOOL showsToggleRow;
@property(nonatomic, readonly) BOOL showsSliderRow;
- (void)configureWithPreferences:(NSDictionary *)preferences preview:(BOOL)preview;
- (CGFloat)preferredHeightForWidth:(CGFloat)width;
- (void)configurePreview:(BOOL)preview;
- (void)applyState:(NSDictionary *)state busy:(BOOL)busy;
- (void)showMessage:(NSString *)message;
@end
