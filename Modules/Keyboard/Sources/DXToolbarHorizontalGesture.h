#import <UIKit/UIKit.h>

@interface DXToolbarHorizontalGesture : UIGestureRecognizer
@property(nonatomic, weak, readonly) UIButton *sourceButton;
@property(nonatomic, copy, readonly) NSString *sourceIdentifier;
@property(nonatomic, weak, readonly) UIWindow *sourceWindow;
@property(nonatomic, assign, readonly) NSInteger result;
@end
