#import "MTStatusBarGestures.h"
#import "MTStatusBarGesturePolicy.h"
#import "MTSystemOpenBroker.h"
#import "MTGlobalPanel.h"
#import "MTGlobalPanelPolicy.h"
#import "MTKeyboardPanelPreferences.h"
#import "MTPanelRegistry.h"
#import "common.h"
#import <objc/runtime.h>
#import <notify.h>

static char MTStatusHandlerKey, MTStatusApertureHandlerKey, MTStatusKindKey, MTStatusSessionKey;
static NSHashTable *MTStatusHandlers;
static void MTTryStatusHooks(void);
static void MTInstallStatusGestures(UIView *view);

static BOOL MTIsStatusView(UIView *view) {
    // iOS 17's system status bar uses SystemStatusUI classes that are siblings
    // of the UIKit implementations, rather than subclasses of them.
    for (NSString *name in @[@"UIStatusBar", @"UIStatusBar_Modern", @"_UIStatusBar",
                            @"STUIStatusBar_Wrapper", @"STUIStatusBar"]) {
        Class cls = NSClassFromString(name);
        if (cls && [cls isSubclassOfClass:UIView.class] && [view isKindOfClass:cls]) return YES;
    }
    return NO;
}
// SquidGesturePro installs on _UIStatusBar itself in initWithStyle:.
// A Wrapper is only a fallback when it contains no concrete status bar.
static BOOL MTIsStatusCore(UIView *view) {
    for (NSString *name in @[@"_UIStatusBar", @"STUIStatusBar"]) {
        Class cls = NSClassFromString(name);
        if (cls && [cls isSubclassOfClass:UIView.class] && [view isKindOfClass:cls]) return YES;
    }
    return NO;
}
static BOOL MTInstallStatusCoresBelow(UIView *view) {
    BOOL found = NO;
    for (UIView *child in view.subviews) {
        if (MTIsStatusCore(child)) { MTInstallStatusGestures(child); found = YES; }
        else found |= MTInstallStatusCoresBelow(child);
    }
    return found;
}
static BOOL MTIsApertureView(UIView *view) {
    if (![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return NO;
    Class cls = NSClassFromString(@"SBSystemApertureContainerView");
    return cls && [cls isSubclassOfClass:UIView.class] && [view isKindOfClass:cls];
}
static BOOL MTIsStatusActionRecognizer(UIGestureRecognizer *gesture) {
    for (NSString *name in @[@"_UIStatusBarActionGestureRecognizer", @"STUIStatusBarActionGestureRecognizer"]) {
        Class cls = NSClassFromString(name);
        if (cls && [cls isSubclassOfClass:UIGestureRecognizer.class] && [gesture isKindOfClass:cls]) return YES;
    }
    return NO;
}
static BOOL MTStatusReceiverVisible(UIView *view, UIWindow *window) {
    if (!view || view.window != window) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview)
        if (ancestor.hidden || ancestor.alpha < 0.01) return NO;
    CGRect frame = [view convertRect:view.bounds toView:window];
    return !CGRectIsEmpty(frame) && !CGRectIsEmpty(CGRectIntersection(frame, window.bounds));
}

// Recognizers ride the status-bar view itself, so the bar instance owns their
// whole lifetime: replacement re-runs the system construction path, re-parent
// moves the set along, and nothing but the per-touch gates survives a touch.
// Only the island keeps its window-hosted set, because its install-time
// container may be released while the window still serves touches.
@interface MTStatusGestureSession : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) UIView *receiver;
@property(nonatomic, weak) UIView *touchView;
@property(nonatomic, copy) NSDictionary *preferences;
@property(nonatomic, copy) NSString *region;
@property(nonatomic, copy) NSString *horizontalDirection;
@property(nonatomic) CGRect frame;
@property(nonatomic) BOOL dispatched;
@end
@implementation MTStatusGestureSession @end

@interface MTStatusGestureHandler : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *anchor;
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic) BOOL aperture;
@property(nonatomic, strong) NSArray<UIGestureRecognizer *> *recognizers;
@property(nonatomic, copy) NSString *lastRejection;
@property(nonatomic, copy) NSString *lastConfiguration;
- (UIWindow *)touchWindow;
- (void)refresh;
- (void)invalidate;
- (BOOL)available;
- (BOOL)reject:(NSString *)reason;
- (BOOL)hasAction:(NSString *)kind region:(NSString *)region preferences:(NSDictionary *)preferences;
- (BOOL)sessionIsCurrent:(MTStatusGestureSession *)session;
- (void)recognized:(UIGestureRecognizer *)gesture;
@end

@implementation MTStatusGestureHandler
- (UIWindow *)touchWindow {
    // The island is gated by its install-time window; a detached container
    // must not retire a set the window still serves. Bars resolve everything
    // through their current window instead.
    return self.aperture ? self.window : self.anchor.window;
}
- (BOOL)reject:(NSString *)reason {
    if (![self.lastRejection isEqual:reason])
        NSLog(@"[MetisKeyboard][StatusBarGesture] rejected host=%@ gate=%@", NSProcessInfo.processInfo.processName, reason);
    self.lastRejection = reason;
    return NO;
}
- (void)dealloc {
    NSArray *recognizers = _recognizers;
    if (NSThread.isMainThread) { for (UIGestureRecognizer *gesture in recognizers) gesture.enabled = NO; }
    else dispatch_async(dispatch_get_main_queue(), ^{ for (UIGestureRecognizer *gesture in recognizers) gesture.enabled = NO; });
}
- (void)invalidate {
    if (!NSThread.isMainThread) return;
    UIView *anchor = self.anchor;
    for (UIGestureRecognizer *gesture in self.recognizers) {
        gesture.enabled = NO;
        gesture.delegate = nil;
        objc_setAssociatedObject(gesture, &MTStatusSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [anchor removeGestureRecognizer:gesture];
    }
    self.recognizers = @[];
    self.window = nil;
}
- (BOOL)available {
    if (!NSThread.isMainThread) return NO;
    UIWindow *window = self.touchWindow;
    if (!window || window.hidden) return [self reject:@"window"];
    BOOL springBoard = [NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"];
    if (springBoard) {
        if (![MTGlobalPanel deviceUnlocked] || [MTGlobalPanel.sharedInstance isVisible]) return [self reject:@"lock/panel"];
    } else if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return [self reject:@"inactive-app"];
    if (!self.aperture)
        for (UIView *view = self.anchor; view; view = view.superview) if (view.hidden || view.alpha < 0.01) return [self reject:@"hidden-anchor"];
    UIWindowScene *scene = window.windowScene;
    if (scene && scene.activationState != UISceneActivationStateForegroundActive) return [self reject:@"inactive-scene"];
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    if (!manager.preferencesAvailable) [manager reload];
    if (!manager.preferencesAvailable || !MTKeyboardPanelBool(manager.prefs, kEnabledkey, YES) || !MTStatusBarFlag(manager.prefs[kMTStatusBarEnabled])) return [self reject:@"preferences/enabled"];
    UIInterfaceOrientation orientation = window.windowScene.interfaceOrientation;
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation) ||
        (orientation == UIInterfaceOrientationUnknown && window.bounds.size.width > window.bounds.size.height);
    if (landscape && !MTStatusBarFlag(manager.prefs[kMTStatusBarLandscape])) return [self reject:@"landscape-disabled"];
    if (!self.aperture) {
        CGRect frame = [self.anchor convertRect:self.anchor.bounds toView:window];
        if (CGRectIsEmpty(frame) || CGRectIsEmpty(CGRectIntersection(frame, window.bounds))) return [self reject:@"geometry"];
    }
    return YES;
}
- (BOOL)hasAction:(NSString *)kind region:(NSString *)region preferences:(NSDictionary *)preferences {
    NSString *selector = MTStatusBarSelector(preferences, MTStatusBarSlot(region, kind));
    if (!selector) return NO;
    // 手势面板恒定启用（原 kMTPanelGlobalEnabled 开关入口已移除）：绑定到手势面板即视为有效动作。
    if (MTPanelAllowed(preferences, selector, MTPanelGestureKind)) return YES;
    id definitions = preferences[kLinkActionskey];
    if (![definitions isKindOfClass:NSArray.class]) return NO;
    for (id entry in definitions)
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return MTGlobalCustomActionSupported(entry);
    return NO;
}
- (void)refresh {
    if (!NSThread.isMainThread) return;
    NSDictionary *preferences = MTPrefsManager.sharedInstance.prefs;
    NSArray *regions = self.aperture ? @[@"middle"] : MTStatusBarRegions();
    NSArray *kinds = self.aperture ? @[@"tap"] : MTStatusBarGestures();
    NSUInteger configured = 0;
    for (NSString *region in regions) for (NSString *kind in kinds)
        if ([self hasAction:kind region:region preferences:preferences]) configured++;
    NSString *summary = [NSString stringWithFormat:@"%d/%d/%lu", MTPrefsManager.sharedInstance.preferencesAvailable,
        MTStatusBarFlag(preferences[kMTStatusBarEnabled]), (unsigned long)configured];
    if (![self.lastConfiguration isEqual:summary]) {
        self.lastConfiguration = summary;
        NSLog(@"[MetisKeyboard][StatusBarGesture] config host=%@ available=%d enabled=%d slots=%lu", NSProcessInfo.processInfo.processName,
            MTPrefsManager.sharedInstance.preferencesAvailable, MTStatusBarFlag(preferences[kMTStatusBarEnabled]), (unsigned long)configured);
    }
    for (UIGestureRecognizer *gesture in self.recognizers) {
        gesture.enabled = NO;
        objc_setAssociatedObject(gesture, &MTStatusSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *kind = objc_getAssociatedObject(gesture, &MTStatusKindKey);
        BOOL active = NO;
        for (NSString *region in regions) {
            active |= [kind isEqual:@"horizontal"] ? ([self hasAction:@"leftswipe" region:region preferences:preferences] ||
                [self hasAction:@"rightswipe" region:region preferences:preferences]) : [self hasAction:kind region:region preferences:preferences];
        }
        // Visibility/lock/panel gates are evaluated for each touch. Keeping
        // these separate lets gestures work again after a panel closes.
        gesture.enabled = active && MTPrefsManager.sharedInstance.preferencesAvailable &&
            MTKeyboardPanelBool(preferences, kEnabledkey, YES) && MTStatusBarFlag(preferences[kMTStatusBarEnabled]);
    }
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    MTStatusGestureSession *previous = objc_getAssociatedObject(gesture, &MTStatusSessionKey);
    objc_setAssociatedObject(gesture, &MTStatusSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (![self available]) return NO;
    UIWindow *host = self.touchWindow;
    if (touch.window != host) return [self reject:@"window-mismatch"];
    NSString *kind = objc_getAssociatedObject(gesture, &MTStatusKindKey);
    // SpringBoard swaps island container instances between presentation modes.
    // The receiver is resolved per touch; binding to the install-time anchor
    // let an earlier instance's window gesture silently reject later ones.
    UIView *receiver = self.anchor;
    BOOL apertureTap = NO;
    if (self.aperture && [kind isEqual:@"tap"])
        for (UIView *view = touch.view; view && view != host; view = view.superview)
            if (MTIsApertureView(view)) { apertureTap = YES; receiver = view; }
    if (self.aperture && !apertureTap) return [self reject:@"aperture-container"];
    if (!MTStatusReceiverVisible(receiver, self.aperture ? host : receiver.window)) return [self reject:@"hidden-receiver"];
    // Only a control strictly below the bar defers to its own native action;
    // a view-hosted set never sees touches outside the bar in the first place.
    for (UIView *view = touch.view; view && view != receiver; view = view.superview) {
        if (!apertureTap && ([view isKindOfClass:UIControl.class] || [NSStringFromClass(view.class) containsString:@"Aperture"])) return [self reject:@"native-control"];
    }
    NSString *region;
    if (self.aperture) {
        region = @"middle";
    } else {
        CGPoint point = [touch locationInView:self.anchor];
        CGRect bounds = self.anchor.bounds;
        region = MTStatusBarRegion(point.x - bounds.origin.x, point.y - bounds.origin.y, bounds.size.width, bounds.size.height);
    }
    if (!region) return NO;
    NSDictionary *preferences = MTPrefsManager.sharedInstance.prefs;
    BOOL enabled = [kind isEqual:@"horizontal"] ? ([self hasAction:@"leftswipe" region:region preferences:preferences] ||
        [self hasAction:@"rightswipe" region:region preferences:preferences]) : [self hasAction:kind region:region preferences:preferences];
    if (!enabled) return NO;
    self.lastRejection = nil;
    if ([kind isEqual:@"doubletap"] && touch.tapCount > 1 && previous &&
        (![previous.region isEqual:region] || ![previous.preferences isEqual:preferences])) return NO;
    MTStatusGestureSession *session = [MTStatusGestureSession new];
    session.region = region; session.window = host; session.receiver = receiver; session.touchView = touch.view; session.preferences = [preferences copy];
    session.frame = self.aperture ? touch.window.bounds : [self.anchor convertRect:self.anchor.bounds toView:host];
    objc_setAssociatedObject(gesture, &MTStatusSessionKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"[MetisKeyboard][StatusBarGesture] touch host=%@ slot=%@ view=%@ receiver=%@ window=%@", NSProcessInfo.processInfo.processName,
        MTStatusBarSlot(region, kind) ?: [region stringByAppendingString:@".horizontal"], NSStringFromClass(touch.view.class),
        NSStringFromClass(receiver.class), NSStringFromClass(touch.window.class));
    return YES;
}
- (BOOL)sessionIsCurrent:(MTStatusGestureSession *)session {
    if (!session || session.dispatched) return NO;
    UIWindow *host = self.touchWindow;
    return [self available] && session.window == host &&
        MTStatusReceiverVisible(session.receiver, self.aperture ? host : session.receiver.window) &&
        session.touchView.window == session.receiver.window &&
        [session.preferences isEqual:MTPrefsManager.sharedInstance.prefs] &&
        // A new touch resolves the current island container. An in-flight
        // touch must keep its receiver attached, without pinning its frame.
        (self.aperture || CGRectEqualToRect(session.frame, [self.anchor convertRect:self.anchor.bounds toView:host]));
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)other {
    NSString *kind = objc_getAssociatedObject(gesture, &MTStatusKindKey);
    NSString *otherKind = objc_getAssociatedObject(other, &MTStatusKindKey);
    if (![kind isEqual:@"tap"] || ![otherKind isEqual:@"doubletap"] || other.delegate != self) return NO;
    MTStatusGestureSession *session = objc_getAssociatedObject(gesture, &MTStatusSessionKey);
    return [self sessionIsCurrent:session] && [self hasAction:@"doubletap" region:session.region preferences:session.preferences];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    NSString *kind = objc_getAssociatedObject(gesture, &MTStatusKindKey);
    if (!gesture.enabled || !kind || objc_getAssociatedObject(other, &MTStatusKindKey) || !other.enabled) return NO;
    BOOL nativeAction = !self.aperture && MTIsStatusActionRecognizer(other);
    if (!nativeAction) {
        if (![@[@"tap", @"doubletap"] containsObject:kind] || ![other isKindOfClass:UITapGestureRecognizer.class]) return NO;
        UITapGestureRecognizer *native = (UITapGestureRecognizer *)other;
        if (native.numberOfTapsRequired != 1 || native.numberOfTouchesRequired != 1) return NO;
    }
    MTStatusGestureSession *session = objc_getAssociatedObject(gesture, &MTStatusSessionKey);
    if (![self sessionIsCurrent:session]) return NO;
    UIView *view = other.view;
    UIView *touchReceiver = session.receiver;
    if (!view || !(view == self.touchWindow || view.window == self.touchWindow) ||
        !(view == touchReceiver || [view isDescendantOfView:touchReceiver] || [touchReceiver isDescendantOfView:view])) return NO;
    BOOL configured = [kind isEqual:@"horizontal"] ?
        ([self hasAction:@"leftswipe" region:session.region preferences:session.preferences] ||
         [self hasAction:@"rightswipe" region:session.region preferences:session.preferences]) :
        [self hasAction:kind region:session.region preferences:session.preferences];
    if (!configured) return NO;
    // UIKit evaluates this per touch, including descendant taps and recognizers
    // installed after ours. Unconfigured/native-control touches never get here.
    NSLog(@"[MetisKeyboard][StatusBarGesture] priority host=%@ slot=%@ native=%@", NSProcessInfo.processInfo.processName,
        MTStatusBarSlot(session.region, kind) ?: [session.region stringByAppendingString:@".horizontal"], NSStringFromClass(other.class));
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (![self available]) return NO;
    if (![gesture isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    MTStatusGestureSession *session = objc_getAssociatedObject(gesture, &MTStatusSessionKey);
    CGPoint delta = [(UIPanGestureRecognizer *)gesture translationInView:self.touchWindow];
    if (!isfinite(delta.x) || !isfinite(delta.y) || fabs(delta.x) < fabs(delta.y) * 1.5 || delta.x == 0) return NO;
    NSString *direction = delta.x < 0 ? @"leftswipe" : @"rightswipe";
    if (!session || ![self hasAction:direction region:session.region preferences:session.preferences]) return NO;
    session.horizontalDirection = direction;
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    if (![objc_getAssociatedObject(gesture, &MTStatusKindKey) isEqual:@"horizontal"] ||
        objc_getAssociatedObject(other, &MTStatusKindKey) || ![other isKindOfClass:UIPanGestureRecognizer.class]) return NO;
    MTStatusGestureSession *session = objc_getAssociatedObject(gesture, &MTStatusSessionKey);
    CGPoint delta = [(UIPanGestureRecognizer *)gesture translationInView:self.touchWindow];
    return session && [self available] && isfinite(delta.x) && isfinite(delta.y) && delta.x != 0 &&
        fabs(delta.x) >= fabs(delta.y) * 1.5 && [self hasAction:delta.x < 0 ? @"leftswipe" : @"rightswipe"
            region:session.region preferences:session.preferences];
}
- (void)recognized:(UIGestureRecognizer *)gesture {
    NSString *kind = objc_getAssociatedObject(gesture, &MTStatusKindKey);
    if ([kind isEqual:@"longpress"] ? gesture.state != UIGestureRecognizerStateBegan : gesture.state != UIGestureRecognizerStateEnded) return;
    MTStatusGestureSession *session = objc_getAssociatedObject(gesture, &MTStatusSessionKey);
    if (![self sessionIsCurrent:session]) return;
    if ([kind isEqual:@"horizontal"]) {
        CGPoint delta = [(UIPanGestureRecognizer *)gesture translationInView:self.touchWindow];
        if (!isfinite(delta.x) || !isfinite(delta.y) || fabs(delta.x) < 28 || fabs(delta.x) < fabs(delta.y) * 1.5) return;
        kind = delta.x < 0 ? @"leftswipe" : @"rightswipe";
        if (![session.horizontalDirection isEqual:kind]) return;
    }
    if (![self hasAction:kind region:session.region preferences:session.preferences]) return;
    session.dispatched = YES;
    NSString *slot = MTStatusBarSlot(session.region, kind);
    NSString *selector = MTStatusBarSelector(session.preferences, slot);
    NSLog(@"[MetisKeyboard][StatusBarGesture] trigger host=%@ slot=%@", NSProcessInfo.processInfo.processName, slot);
    if (MTKeyboardPanelBool(session.preferences, kEnabledHaptickey, YES)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
    }
    UIWindow *window = self.touchWindow;
    UIInterfaceOrientation orientation = window.windowScene.interfaceOrientation;
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation) ||
        (orientation == UIInterfaceOrientationUnknown && window.bounds.size.width > window.bounds.size.height);
    MTRequestStatusBarGesture(slot, selector, landscape, ^(MTSystemOpenResult result) {
        NSLog(@"[MetisKeyboard][StatusBarGesture] result host=%@ slot=%@ status=%llu", NSProcessInfo.processInfo.processName, slot, (unsigned long long)result);
    });
}
@end

static void MTInstallStatusGestures(UIView *view) {
    if (!NSThread.isMainThread || (!MTIsStatusView(view) && !MTIsApertureView(view))) return;
    if (!MTStatusHandlers) MTStatusHandlers = [NSHashTable weakObjectsHashTable];
    BOOL aperture = MTIsApertureView(view);
    UIView *anchor = view;
    if (!aperture && MTIsStatusCore(view)) {
        // A newly constructed/reparented core supersedes any wrapper fallback.
        // Keep the recognizers on the native action receiver, even when an
        // enclosing wrapper enters the window after the core.
        for (UIView *parent = view.superview; parent; parent = parent.superview) {
            MTStatusGestureHandler *fallback = objc_getAssociatedObject(parent, &MTStatusHandlerKey);
            if (fallback && !MTIsStatusCore(parent)) {
                [fallback invalidate];
                objc_setAssociatedObject(parent, &MTStatusHandlerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    } else {
        for (UIView *parent = view.superview; parent; parent = parent.superview)
            if (aperture ? MTIsApertureView(parent) : MTIsStatusView(parent)) anchor = parent;
        if (!aperture && MTInstallStatusCoresBelow(anchor)) return;
        if (!aperture) for (MTStatusGestureHandler *existing in MTStatusHandlers.allObjects) {
            UIView *oldAnchor = existing.anchor;
            if (!existing.aperture && oldAnchor != anchor && [oldAnchor isDescendantOfView:anchor]) {
                [existing invalidate];
                objc_setAssociatedObject(oldAnchor, &MTStatusHandlerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
    // View-owned recognizers can be installed before UIKit assigns a window.
    // Touch-time availability still rejects detached/hidden receivers. The
    // island's distinct window-owned path requires a window as before.
    if (aperture && !anchor.window) return;
    id owner = aperture ? (id)anchor.window : (id)anchor;
    const void *key = aperture ? &MTStatusApertureHandlerKey : &MTStatusHandlerKey;
    MTStatusGestureHandler *handler = objc_getAssociatedObject(owner, key);
    // Bars bind recognizers to the view itself, so an existing handler already
    // survived every window move; only a first install creates the set.
    if (handler) { [handler refresh]; return; }
    handler = [MTStatusGestureHandler new]; handler.anchor = anchor; handler.window = anchor.window;
    handler.aperture = aperture;
    NSMutableArray *recognizers = [NSMutableArray array];
    for (NSString *kind in aperture ? @[@"tap"] : @[@"tap", @"doubletap", @"longpress", @"horizontal"]) {
        UIGestureRecognizer *gesture;
        if ([kind isEqual:@"longpress"]) {
            UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:handler action:@selector(recognized:)];
            press.minimumPressDuration = 0.5; press.allowableMovement = 10; gesture = press;
        } else if ([kind isEqual:@"horizontal"]) {
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:handler action:@selector(recognized:)];
            pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1; gesture = pan;
        } else {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:handler action:@selector(recognized:)];
            tap.numberOfTapsRequired = [kind isEqual:@"doubletap"] ? 2 : 1;
            tap.numberOfTouchesRequired = 1;
            tap.delaysTouchesEnded = YES; gesture = tap;
        }
        gesture.delegate = handler; gesture.cancelsTouchesInView = YES;
        gesture.delaysTouchesBegan = [kind isEqual:@"tap"] || [kind isEqual:@"doubletap"];
        objc_setAssociatedObject(gesture, &MTStatusKindKey, kind, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [recognizers addObject:gesture];
    }
    handler.recognizers = recognizers;
    objc_setAssociatedObject(owner, key, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [MTStatusHandlers addObject:handler];
    UIView *gestureHost = aperture ? (UIView *)anchor.window : anchor;
    for (UIGestureRecognizer *gesture in recognizers) [gestureHost addGestureRecognizer:gesture];
    [handler refresh];
    NSLog(@"[MetisKeyboard][StatusBarGesture] installed host=%@ view=%@ window=%@", NSProcessInfo.processInfo.processName,
        NSStringFromClass(anchor.class), NSStringFromClass(anchor.window.class));
}

static void MTScanStatusViews(UIView *view) {
    if (MTIsStatusView(view) || MTIsApertureView(view)) MTInstallStatusGestures(view);
    for (UIView *child in view.subviews) MTScanStatusViews(child);
}

static BOOL MTStatusConstructionSupported(Class cls) {
    if (![cls isSubclassOfClass:UIView.class]) return NO;
    Method method = class_getInstanceMethod(cls, @selector(initWithStyle:));
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    return signature.numberOfArguments == 3 && signature.methodReturnType[0] == '@' &&
        !strcmp([signature getArgumentTypeAtIndex:2], @encode(long long));
}

%group TypeXStatusBarWrapper
%hook UIStatusBar
- (void)didMoveToWindow {
    %orig;
    MTInstallStatusGestures((UIView *)self);
}
%end
%end
%group TypeXStatusBarCore
%hook _UIStatusBar
- (void)didMoveToWindow {
    %orig;
    MTInstallStatusGestures((UIView *)self);
}
%end
%end
%group TypeXStatusBarModern
%hook UIStatusBar_Modern
- (void)didMoveToWindow {
    %orig;
    MTInstallStatusGestures((UIView *)self);
}
%end
%end
%group TypeXSystemStatusBarWrapper
%hook STUIStatusBar_Wrapper
- (void)didMoveToWindow {
    %orig;
    MTInstallStatusGestures((UIView *)self);
}
%end
%end
%group TypeXSystemStatusBarCore
%hook STUIStatusBar
- (void)didMoveToWindow {
    %orig;
    MTInstallStatusGestures((UIView *)self);
}
%end
%end
%group TypeXStatusBarCoreConstruction
%hook _UIStatusBar
- (id)initWithStyle:(long long)style {
    id result = %orig;
    MTInstallStatusGestures(result);
    return result;
}
%end
%end
%group TypeXSystemStatusBarCoreConstruction
%hook STUIStatusBar
- (id)initWithStyle:(long long)style {
    id result = %orig;
    MTInstallStatusGestures(result);
    return result;
}
%end
%end
%group TypeXStatusBarAperture
%hook SBSystemApertureContainerView
- (void)didMoveToWindow {
    %orig;
    MTInstallStatusGestures((UIView *)self);
}
%end
%end

static void MTTryStatusHooks(void) {
    if (!NSThread.isMainThread) return;
    if (!MTPrefsManager.sharedInstance.preferencesAvailable) [MTPrefsManager.sharedInstance reload];
    static BOOL wrapperInstalled = NO, coreInstalled = NO, modernInstalled = NO, apertureInstalled = NO, loggedUnavailable = NO;
    static BOOL systemWrapperInstalled = NO, systemCoreInstalled = NO;
    static BOOL coreConstructionInstalled = NO, systemCoreConstructionInstalled = NO;
    Class wrapper = NSClassFromString(@"UIStatusBar") ?: NSClassFromString(@"UIStatusBar_Modern");
    Class core = NSClassFromString(@"_UIStatusBar");
    Class modern = NSClassFromString(@"UIStatusBar_Modern");
    Class systemWrapper = NSClassFromString(@"STUIStatusBar_Wrapper");
    Class systemCore = NSClassFromString(@"STUIStatusBar");
    Class aperture = [NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"] ? NSClassFromString(@"SBSystemApertureContainerView") : Nil;
    SEL selector = @selector(didMoveToWindow);
    for (Class cls in @[wrapper ?: NSObject.class, core ?: NSObject.class, modern ?: NSObject.class,
                       systemWrapper ?: NSObject.class, systemCore ?: NSObject.class, aperture ?: NSObject.class]) {
        if (![cls isSubclassOfClass:UIView.class]) continue;
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) continue;
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, @encode(void))) continue;
        if (cls == wrapper && !wrapperInstalled) {
            %init(TypeXStatusBarWrapper, UIStatusBar = wrapper); wrapperInstalled = YES;
            NSLog(@"[MetisKeyboard][StatusBarGesture] hook host=%@ class=%@", NSProcessInfo.processInfo.processName, NSStringFromClass(cls));
        }
        if (cls == core && !coreInstalled) {
            %init(TypeXStatusBarCore, _UIStatusBar = core); coreInstalled = YES;
            NSLog(@"[MetisKeyboard][StatusBarGesture] hook host=%@ class=%@", NSProcessInfo.processInfo.processName, NSStringFromClass(cls));
        }
        if (cls == modern && modern != wrapper && !modernInstalled) {
            %init(TypeXStatusBarModern, UIStatusBar_Modern = modern); modernInstalled = YES;
            NSLog(@"[MetisKeyboard][StatusBarGesture] hook host=%@ class=%@", NSProcessInfo.processInfo.processName, NSStringFromClass(cls));
        }
        if (cls == systemWrapper && !systemWrapperInstalled) {
            %init(TypeXSystemStatusBarWrapper, STUIStatusBar_Wrapper = systemWrapper); systemWrapperInstalled = YES;
            NSLog(@"[MetisKeyboard][StatusBarGesture] hook host=%@ class=%@", NSProcessInfo.processInfo.processName, NSStringFromClass(cls));
        }
        if (cls == systemCore && !systemCoreInstalled) {
            %init(TypeXSystemStatusBarCore, STUIStatusBar = systemCore); systemCoreInstalled = YES;
            NSLog(@"[MetisKeyboard][StatusBarGesture] hook host=%@ class=%@", NSProcessInfo.processInfo.processName, NSStringFromClass(cls));
        }
        if (cls == aperture && !apertureInstalled) { %init(TypeXStatusBarAperture, SBSystemApertureContainerView = aperture); apertureInstalled = YES; }
    }
    // Keep construction hooks independent of didMoveToWindow availability.
    // Only register the exact object-returning, signed 64-bit style ABI.
    for (Class cls in @[core ?: NSObject.class, systemCore ?: NSObject.class]) {
        if (!MTStatusConstructionSupported(cls)) continue;
        if (cls == core && !coreConstructionInstalled) {
            %init(TypeXStatusBarCoreConstruction, _UIStatusBar = core); coreConstructionInstalled = YES;
            NSLog(@"[MetisKeyboard][StatusBarGesture] construction hook class=%@", NSStringFromClass(cls));
        }
        if (cls == systemCore && !systemCoreConstructionInstalled) {
            %init(TypeXSystemStatusBarCoreConstruction, STUIStatusBar = systemCore); systemCoreConstructionInstalled = YES;
            NSLog(@"[MetisKeyboard][StatusBarGesture] construction hook class=%@", NSStringFromClass(cls));
        }
    }
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows) MTScanStatusViews(window);
    #pragma clang diagnostic pop
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) MTScanStatusViews(window);
    for (MTStatusGestureHandler *handler in MTStatusHandlers.allObjects) [handler refresh];
    if (!wrapperInstalled && !coreInstalled && !modernInstalled && !systemWrapperInstalled && !systemCoreInstalled && !loggedUnavailable) {
        loggedUnavailable = YES;
        NSLog(@"[MetisKeyboard][StatusBarGesture] unavailable: status-bar classes missing");
    }
}

void MTStartStatusBarGestures(void) {
    if (!MTStatusBarHostAllowed(NSProcessInfo.processInfo.processName, NSBundle.mainBundle.bundleURL.pathExtension)) return;
    void (^start)(void) = ^{
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            if (!MTStatusHandlers) MTStatusHandlers = [NSHashTable weakObjectsHashTable];
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            for (NSString *name in @[UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeKeyNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    // System bars may load late or re-parent between windows;
                    // scans recover instances the didMoveToWindow hooks missed.
                    MTTryStatusHooks();
                    if ([note.object isKindOfClass:UIWindow.class]) MTScanStatusViews(note.object);
                }];
            }
            for (NSString *name in @[UIApplicationDidFinishLaunchingNotification, UISceneWillConnectNotification, UISceneDidActivateNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { MTTryStatusHooks(); }];
            }
            [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                [MTPrefsManager.sharedInstance reload];
                MTTryStatusHooks();
            }];
            for (NSString *name in @[UIApplicationWillResignActiveNotification, UISceneWillDeactivateNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    for (MTStatusGestureHandler *handler in MTStatusHandlers.allObjects) [handler refresh];
                }];
            }
            [center addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                for (MTStatusGestureHandler *handler in MTStatusHandlers.allObjects) [handler refresh];
            }];
            for (NSString *name in @[kPrefsChangedIdentifier, @"com.apple.springboard.lockstate", @"com.apple.springboard.frontmostapplicationchanged"]) {
                int token = NOTIFY_TOKEN_INVALID;
                uint32_t result = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(__unused int delivered) {
                    [MTPrefsManager.sharedInstance reload];
                    MTTryStatusHooks();
                });
                if (result != NOTIFY_STATUS_OK) NSLog(@"[MetisKeyboard][StatusBarGesture] notification registration failed status=%u", result);
            }
            MTTryStatusHooks();
        });
    };
    if (NSThread.isMainThread) start();
    else dispatch_async(dispatch_get_main_queue(), start);
}
