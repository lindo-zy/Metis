//
//  MTSwipeUpHooks.m
//  Mt
//

#define CHUseSubstrate

#import "MTClipboardHelperHookInstaller.h"
#import "MTClipboardHelperRuntime.h"
#import "MTSwipeUpGestureRecognizer.h"

#import <CaptainHook/CaptainHook.h>
#import <HBLog.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

CHDeclareClass(UIInputSetHostView);
CHDeclareClass(_UIHostedWindow);
CHDeclareClass(UIViewController);

static char mtSwipeUpGestureRecognizerKey;
static char mtSwipeUpGestureHandlerKey;
static char mtManualSwipeUpActiveKey;

static CGFloat const kMTSwipeUpAdditionalBottomSafetyInset = 0.0;
static NSString *const kMTSpotlightBundleIdentifier = @"com.apple.Spotlight";

static BOOL mtKeyboardExtensionSwipeUpSpotlightOnly = NO;
static NSString *mtKeyboardExtensionHostApplicationBundleIdentifier = nil;
static NSString *mtLoggedKeyboardExtensionHostApplicationBundleIdentifier = nil;

@interface UIGestureRecognizer (MTManualTouchDelivery)
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
@end

@interface UIInputSetHostView : UIView
@end

@interface _UIHostedWindow : UIWindow
@end

@interface UIViewController (MTHostApplication)
- (void)_setHostApplicationBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface UIApplication (MTPrivateTouches)
- (void)_cancelAllTouches;
@end

#pragma mark - Swipe Region

static BOOL mtPointIsInsideAllowedSwipeRegion(UIView *view, CGPoint point) {
    UIEdgeInsets safeAreaInsets = view.safeAreaInsets;
    safeAreaInsets.bottom += kMTSwipeUpAdditionalBottomSafetyInset;
    CGRect allowedBounds = UIEdgeInsetsInsetRect(view.bounds, safeAreaInsets);
    if (CGRectGetWidth(allowedBounds) <= 0 || CGRectGetHeight(allowedBounds) <= 0) {
        return NO;
    }
    if (CGRectIsNull(allowedBounds)) {
        return NO;
    }

    return CGRectContainsPoint(allowedBounds, point);
}

static void mtDiscardSwipeUpGestureRecognizer(UIView *view);
static void mtSetManualSwipeUpActive(UIWindow *window, BOOL active);

NS_ASSUME_NONNULL_BEGIN

@interface MTSwipeUpGestureHandler : NSObject <UIGestureRecognizerDelegate>

#pragma mark - Lifecycle

- (instancetype)initWithView:(UIView *)view keyboardExtension:(BOOL)keyboardExtension;

#pragma mark - Actions

- (void)handleSwipeUpGesture:(UIGestureRecognizer *)recognizer;
@end

@interface MTSwipeUpGestureHandler ()

#pragma mark - State

@property(nonatomic, weak, readonly) UIView *view;
@property(nonatomic, assign, readonly, getter=isKeyboardExtension) BOOL keyboardExtension;
@end

NS_ASSUME_NONNULL_END

@implementation MTSwipeUpGestureHandler

#pragma mark - Lifecycle

- (instancetype)initWithView:(UIView *)view keyboardExtension:(BOOL)keyboardExtension {
    self = [super init];
    if (self) {
        _view = view;
        _keyboardExtension = keyboardExtension;
    }
    return self;
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *view = self.view;
    if (!view || gestureRecognizer != objc_getAssociatedObject(view, &mtSwipeUpGestureRecognizerKey)) {
        return YES;
    }

    return mtPointIsInsideAllowedSwipeRegion(view, [touch locationInView:view]);
}

#pragma mark - Actions

- (void)handleSwipeUpGesture:(UIGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    if (self.isKeyboardExtension) {
        HBLogDebug(@"Mt: manual-feed swipe recognizer action state=%ld", (long)recognizer.state);
        UIWindow *window = (UIWindow *)recognizer.view;
        if ([window isKindOfClass:[UIWindow class]]) {
            mtSetManualSwipeUpActive(window, NO);
            mtDiscardSwipeUpGestureRecognizer(window);
            HBLogDebug(@"Mt: discarded manual-feed swipe recognizer after recognition");
        }
    }

    if ([[MTClipboardHelperRuntime sharedRuntime] activateMtAfterCapturingCurrentFocus]) {
        UIApplication *application = [UIApplication sharedApplication];
        if (![application respondsToSelector:@selector(_cancelAllTouches)]) {
            return;
        }

        [application _cancelAllTouches];
    }
}

@end

#pragma mark - Gesture Recognizer Management

static MTSwipeUpGestureRecognizer *mtEnsureSwipeUpGestureRecognizer(UIView *view, BOOL keyboardExtension) {
    MTSwipeUpGestureRecognizer *recognizer = objc_getAssociatedObject(view, &mtSwipeUpGestureRecognizerKey);
    if (recognizer) {
        return recognizer;
    }

    MTSwipeUpGestureHandler *handler = objc_getAssociatedObject(view, &mtSwipeUpGestureHandlerKey);
    if (!handler) {
        handler = [[MTSwipeUpGestureHandler alloc] initWithView:view keyboardExtension:keyboardExtension];
        objc_setAssociatedObject(view, &mtSwipeUpGestureHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    recognizer = [[MTSwipeUpGestureRecognizer alloc] initWithTarget:handler
                                                                 action:@selector(handleSwipeUpGesture:)];
    recognizer.cancelsTouchesInView = NO;
    recognizer.delegate = handler;
    [view addGestureRecognizer:recognizer];
    objc_setAssociatedObject(view, &mtSwipeUpGestureRecognizerKey, recognizer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return recognizer;
}

static void mtDiscardSwipeUpGestureRecognizer(UIView *view) {
    UIGestureRecognizer *recognizer = objc_getAssociatedObject(view, &mtSwipeUpGestureRecognizerKey);
    if (!recognizer) {
        return;
    }

    [view removeGestureRecognizer:recognizer];
    objc_setAssociatedObject(view, &mtSwipeUpGestureRecognizerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &mtSwipeUpGestureHandlerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Manual Touch State

static BOOL mtManualSwipeUpIsActive(UIWindow *window) {
    NSNumber *active = objc_getAssociatedObject(window, &mtManualSwipeUpActiveKey);
    return [active boolValue];
}

static void mtSetManualSwipeUpActive(UIWindow *window, BOOL active) {
    objc_setAssociatedObject(window, &mtManualSwipeUpActiveKey, @(active), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSSet<UITouch *> *mtTouchesForWindowWithPhase(UIWindow *window, UIEvent *event, UITouchPhase phase) {
    NSMutableSet<UITouch *> *touches = [NSMutableSet set];
    for (UITouch *touch in [event allTouches]) {
        if (touch.window == window && touch.phase == phase) {
            [touches addObject:touch];
        }
    }
    return touches;
}

#pragma mark - Keyboard Extension Hooks

CHOptimizedMethod1(self, void, _UIHostedWindow, sendEvent, UIEvent *, event) {
    if (event.type != UIEventTypeTouches) {
        CHSuper1(_UIHostedWindow, sendEvent, event);
        return;
    }

    if (mtKeyboardExtensionSwipeUpSpotlightOnly &&
        ![mtKeyboardExtensionHostApplicationBundleIdentifier isEqualToString:kMTSpotlightBundleIdentifier]) {
        CHSuper1(_UIHostedWindow, sendEvent, event);
        return;
    }

    NSMutableSet<UITouch *> *windowTouches = [NSMutableSet set];
    for (UITouch *touch in [event allTouches]) {
        if (touch.window == self) {
            [windowTouches addObject:touch];
        }
    }

    if (windowTouches.count > 1) {
        if (mtManualSwipeUpIsActive(self)) {
            UIGestureRecognizer *recognizer = objc_getAssociatedObject(self, &mtSwipeUpGestureRecognizerKey);
            [recognizer touchesCancelled:windowTouches withEvent:event];
            mtSetManualSwipeUpActive(self, NO);
            mtDiscardSwipeUpGestureRecognizer(self);
        }
        CHSuper1(_UIHostedWindow, sendEvent, event);
        return;
    }

    NSSet<UITouch *> *beganTouches = mtTouchesForWindowWithPhase(self, event, UITouchPhaseBegan);
    if (beganTouches.count > 0) {
        UITouch *touch = [beganTouches anyObject];
        BOOL active =
            beganTouches.count == 1 && mtPointIsInsideAllowedSwipeRegion(self, [touch locationInView:self]);
        mtSetManualSwipeUpActive(self, active);
        HBLogDebug(@"Mt: manual swipe recognizer began active=%@", active ? @"YES" : @"NO");
        if (active) {
            mtDiscardSwipeUpGestureRecognizer(self);
            UIGestureRecognizer *recognizer = mtEnsureSwipeUpGestureRecognizer(self, YES);
            HBLogDebug(@"Mt: installed manual-feed swipe recognizer on _UIHostedWindow from began");
            [recognizer touchesBegan:beganTouches withEvent:event];
        }
        CHSuper1(_UIHostedWindow, sendEvent, event);
        return;
    }

    if (!mtManualSwipeUpIsActive(self)) {
        CHSuper1(_UIHostedWindow, sendEvent, event);
        return;
    }

    UIGestureRecognizer *recognizer = objc_getAssociatedObject(self, &mtSwipeUpGestureRecognizerKey);
    if (!recognizer) {
        mtSetManualSwipeUpActive(self, NO);
        CHSuper1(_UIHostedWindow, sendEvent, event);
        return;
    }

    NSSet<UITouch *> *movedTouches = mtTouchesForWindowWithPhase(self, event, UITouchPhaseMoved);
    if (movedTouches.count > 0) {
        [recognizer touchesMoved:movedTouches withEvent:event];
    }

    NSSet<UITouch *> *endedTouches = mtTouchesForWindowWithPhase(self, event, UITouchPhaseEnded);
    if (endedTouches.count > 0) {
        [recognizer touchesEnded:endedTouches withEvent:event];
        mtSetManualSwipeUpActive(self, NO);
        mtDiscardSwipeUpGestureRecognizer(self);
    }

    NSSet<UITouch *> *cancelledTouches = mtTouchesForWindowWithPhase(self, event, UITouchPhaseCancelled);
    if (cancelledTouches.count > 0) {
        [recognizer touchesCancelled:cancelledTouches withEvent:event];
        mtSetManualSwipeUpActive(self, NO);
        mtDiscardSwipeUpGestureRecognizer(self);
    }

    CHSuper1(_UIHostedWindow, sendEvent, event);
}

CHOptimizedMethod1(self, void, UIViewController, _setHostApplicationBundleIdentifier, NSString *, bundleIdentifier) {
    CHSuper1(UIViewController, _setHostApplicationBundleIdentifier, bundleIdentifier);

    if (![bundleIdentifier isKindOfClass:[NSString class]]) {
        return;
    }

    mtKeyboardExtensionHostApplicationBundleIdentifier = [bundleIdentifier copy];
    if ([mtLoggedKeyboardExtensionHostApplicationBundleIdentifier isEqualToString:bundleIdentifier]) {
        return;
    }

    mtLoggedKeyboardExtensionHostApplicationBundleIdentifier = [bundleIdentifier copy];
    HBLogDebug(@"Mt: keyboard extension host application bundle identifier=%@", bundleIdentifier);
}

#pragma mark - Keyboard Host Hooks

CHOptimizedMethod0(self, void, UIInputSetHostView, didMoveToWindow) {
    CHSuper0(UIInputSetHostView, didMoveToWindow);

    if (!self.window) {
        return;
    }

    mtEnsureSwipeUpGestureRecognizer(self, NO);
}

@implementation MTClipboardHelperHookInstaller (SwipeUp)

#pragma mark - Hook Installation

+ (void)installSwipeUpHooks {
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
      CHLoadClass_(&UIInputSetHostView$, NSClassFromString(@"UIInputSetHostView"));

      CHHook0(UIInputSetHostView, didMoveToWindow);
    });
}

+ (void)installKeyboardExtensionSwipeUpHooksForSpotlightOnly:(BOOL)spotlightOnly {
    static dispatch_once_t sOnceToken;
    mtKeyboardExtensionSwipeUpSpotlightOnly = spotlightOnly;
    dispatch_once(&sOnceToken, ^{
      CHLoadClass(UIViewController);
      if ([CHClass(UIViewController) instancesRespondToSelector:@selector(_setHostApplicationBundleIdentifier:)]) {
          CHHook1(UIViewController, _setHostApplicationBundleIdentifier);
      }

      CHLoadClass_(&_UIHostedWindow$, NSClassFromString(@"_UIHostedWindow"));

      CHHook1(_UIHostedWindow, sendEvent);
    });
}

@end
