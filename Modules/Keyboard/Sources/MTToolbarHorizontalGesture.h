#import <UIKit/UIKit.h>

@interface MTToolbarHorizontalGesture : UIGestureRecognizer
@property(nonatomic, weak, readonly) UIButton *sourceButton;
@property(nonatomic, copy, readonly) NSString *sourceIdentifier;
@property(nonatomic, weak, readonly) UIWindow *sourceWindow;
@property(nonatomic, assign, readonly) NSInteger result;
@end
