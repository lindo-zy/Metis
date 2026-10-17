#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <string.h>
#include <math.h>

static inline BOOL DXDockPanelViewVisible(UIView *view, UIWindow *window) {
    if (!view || view.window != window) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview)
        if (ancestor.hidden || ancestor.alpha < 0.01) return NO;
    return YES;
}

static inline BOOL DXDockPanelIsIconView(UIView *view) {
    Class iconClass = NSClassFromString(@"SBIconView");
    return iconClass ? [view isKindOfClass:iconClass] : [NSStringFromClass(view.class) hasSuffix:@"IconView"];
}

static inline UIView *DXDockPanelIconImageView(UIView *icon) {
    SEL selector = NSSelectorFromString(@"iconImageView");
    if ([icon respondsToSelector:selector]) {
        @try {
            NSMethodSignature *signature = [icon methodSignatureForSelector:selector];
            if (signature.numberOfArguments == 2 && !strcmp(signature.methodReturnType, @encode(id))) {
                id image = ((id (*)(id, SEL))objc_msgSend)(icon, selector);
                if ([image isKindOfClass:UIView.class] && image != icon && [image isDescendantOfView:icon]) return image;
            }
        } @catch (__unused NSException *exception) { }
    }
    // Some systems expose the image only in the view hierarchy. Never use a
    // badge/label UIImageView or assume a fixed icon size for custom layouts.
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithArray:icon.subviews];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if ([NSStringFromClass(view.class) containsString:@"IconImageView"]) return view;
        [pending addObjectsFromArray:view.subviews];
    }
    return nil;
}

// SpringBoard may hit-test blank padding to SBIconView. Protect the visible
// image, rather than rejecting its entire expanded touch target. If image
// geometry is unavailable, conservatively protect the full icon bounds.
static inline BOOL DXDockPanelTouchIsBackground(UIView *dock, UIView *hitView, CGPoint point) {
    UIWindow *window = dock.window;
    if (!window || hitView.window != window || !isfinite(point.x) || !isfinite(point.y)) return NO;
    UIView *hitIcon = nil;
    BOOL control = NO;
    for (UIView *view = hitView; view && view != dock && view != window; view = view.superview) {
        if (DXDockPanelIsIconView(view)) { hitIcon = view; break; }
        if ([view isKindOfClass:UIControl.class]) control = YES;
    }
    if (hitIcon && ![hitIcon isDescendantOfView:dock]) return NO;
    if (control && !hitIcon) return NO;
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:dock];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if (!DXDockPanelViewVisible(view, window)) continue;
        if (DXDockPanelIsIconView(view)) {
            UIView *image = DXDockPanelIconImageView(view);
            UIView *protectedView = DXDockPanelViewVisible(image, window) && !CGRectIsEmpty(image.bounds) ? image : view;
            CGRect frame = [protectedView convertRect:protectedView.bounds toView:window];
            if (CGRectIsNull(frame) || CGRectIsInfinite(frame) || CGRectIsEmpty(frame) ||
                !isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
                !isfinite(frame.size.width) || !isfinite(frame.size.height)) return NO;
            if (CGRectContainsPoint(frame, point)) return NO;
        } else [pending addObjectsFromArray:view.subviews];
    }
    return YES;
}
