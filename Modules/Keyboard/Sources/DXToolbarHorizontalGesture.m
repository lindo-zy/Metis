#import "DXToolbarHorizontalGesture.h"
#import "DXToolbarGesturePolicy.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

@interface DXToolbarHorizontalGesture ()
@property(nonatomic, weak, readwrite) UIButton *sourceButton;
@property(nonatomic, copy, readwrite) NSString *sourceIdentifier;
@property(nonatomic, weak, readwrite) UIWindow *sourceWindow;
@property(nonatomic, assign, readwrite) NSInteger result;
@property(nonatomic, assign) CGPoint origin;
@property(nonatomic, assign) CGRect buttonRect;
@property(nonatomic, assign) BOOL stayedInButton;
@end

@implementation DXToolbarHorizontalGesture
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (self.state == UIGestureRecognizerStateFailed || self.state == UIGestureRecognizerStateCancelled || self.state == UIGestureRecognizerStateEnded) return;
    if (touches.count != 1 || event.allTouches.count != 1) {
        self.state = self.state == UIGestureRecognizerStatePossible ? UIGestureRecognizerStateFailed : UIGestureRecognizerStateCancelled;
        return;
    }
    UITouch *touch = touches.anyObject;
    self.origin = [touch locationInView:self.view];
    UIView *view = touch.view;
    while (view && view != self.view && ![view isKindOfClass:UIButton.class]) view = view.superview;
    self.sourceButton = [view isKindOfClass:UIButton.class] ? (UIButton *)view : nil;
    self.sourceIdentifier = self.sourceButton.accessibilityIdentifier;
    self.sourceWindow = self.view.window;
    self.buttonRect = self.sourceButton ? [self.sourceButton convertRect:self.sourceButton.bounds toView:self.view] : CGRectZero;
    self.stayedInButton = self.sourceButton != nil;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    if (self.state == UIGestureRecognizerStateFailed || self.state == UIGestureRecognizerStateCancelled || self.state == UIGestureRecognizerStateEnded) return;
    if (!self.view.window || self.view.window != self.sourceWindow) {
        self.state = self.state == UIGestureRecognizerStatePossible ? UIGestureRecognizerStateFailed : UIGestureRecognizerStateCancelled;
        return;
    }
    CGPoint point = [touches.anyObject locationInView:self.view];
    self.stayedInButton = self.stayedInButton && CGRectContainsPoint(self.buttonRect, point);
    CGFloat dx = point.x - self.origin.x, dy = point.y - self.origin.y;
    if (self.state == UIGestureRecognizerStatePossible) {
        if (fabs(dy) >= 8 && fabs(dy) > fabs(dx)) self.state = UIGestureRecognizerStateFailed;
        else if (fabs(dx) >= 8 && fabs(dx) >= fabs(dy) * 1.5) self.state = UIGestureRecognizerStateBegan;
    } else if (self.state == UIGestureRecognizerStateBegan || self.state == UIGestureRecognizerStateChanged) {
        self.state = UIGestureRecognizerStateChanged;
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (self.state == UIGestureRecognizerStateFailed || self.state == UIGestureRecognizerStateCancelled || self.state == UIGestureRecognizerStateEnded) return;
    if (self.state != UIGestureRecognizerStateBegan && self.state != UIGestureRecognizerStateChanged) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    CGPoint point = [touches.anyObject locationInView:self.view];
    self.stayedInButton = self.stayedInButton && CGRectContainsPoint(self.buttonRect, point);
    self.result = DXToolbarHorizontalResult(point.x - self.origin.x, point.y - self.origin.y,
        CGRectGetWidth(self.view.bounds), CGRectGetWidth(self.buttonRect), self.sourceButton != nil, self.stayedInButton);
    self.state = UIGestureRecognizerStateEnded;
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    if (self.state == UIGestureRecognizerStateFailed || self.state == UIGestureRecognizerStateCancelled || self.state == UIGestureRecognizerStateEnded) return;
    self.state = self.state == UIGestureRecognizerStatePossible ? UIGestureRecognizerStateFailed : UIGestureRecognizerStateCancelled;
}
- (void)reset {
    [super reset];
    self.sourceButton = nil;
    self.sourceIdentifier = nil;
    self.sourceWindow = nil;
    self.result = 0;
    self.stayedInButton = NO;
}
@end
