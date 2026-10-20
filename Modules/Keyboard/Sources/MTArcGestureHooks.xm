// 屏幕底角划弧手势（Arc-X 风格）：把自定义 UIPanGestureRecognizer 注册进
// SBSystemGestureManager 的系统手势窗口，只有触点起点落在角点扇形区内
// 才接受会话，普通点击与区域外触摸立即 fail，不影响 App 触摸派发。
// 注册、门控与动作分发的结构沿用 MTEdgeGestureHooks.xm。
#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <notify.h>
#import "MTArcGestures.h"
#import "MTArcDebugOverlay.h"
#import "MTArcGesturePolicy.h"
#import "MTPanelRegistry.h"
#import "MTGlobalPanel.h"
#import "MTGlobalPanelPolicy.h"
#import "MTGlobalActionExecutor.h"
#import "common.h"

@interface SBSystemGestureManager : NSObject
- (void)addGestureRecognizer:(UIGestureRecognizer *)recognizer withType:(unsigned long long)type;
- (void)removeGestureRecognizer:(UIGestureRecognizer *)recognizer;
@end

// Own namespace: must not collide with Triggr, MTEdge or Apple's gesture types.
static const unsigned long long MTArcGestureTypeBase = 0x6d746100;
static SBSystemGestureManager *MTArcManager;
static void MTUpdateArcGestures(void);

static UIInterfaceOrientation MTArcOrientation(void) {
    // SpringBoard's active orientation follows the display, including apps
    // that do not rotate the device's physical orientation.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIInterfaceOrientation orientation = UIApplication.sharedApplication.statusBarOrientation;
#pragma clang diagnostic pop
    return orientation == UIInterfaceOrientationUnknown ? UIInterfaceOrientationPortrait : orientation;
}
static BOOL MTArcLandscape(void) { return UIInterfaceOrientationIsLandscape(MTArcOrientation()); }
static NSString *MTArcConfiguredSelector(NSString *slot) {
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    if (!manager.preferencesAvailable || !MTArcGestureEnabled(manager.prefs, NO, kEnabledkey)) return nil;
    NSString *selector = MTArcGestureSelector(manager.prefs, slot);
    if (MTPanelAllowed(manager.prefs, selector, MTPanelGestureKind)) return selector;
    return MTGlobalCustomActionSupported(MTPanelActionDefinition(manager.prefs, selector)) ? selector : nil;
}
static NSString *MTArcAvailableSelector(NSString *slot) {
    if (!MTArcGestureEnabled(MTPrefsManager.sharedInstance.prefs, MTArcLandscape(), kEnabledkey) ||
        ![MTGlobalPanel deviceUnlocked] || [MTGlobalPanel.sharedInstance isVisible]) return nil;
    return MTArcConfiguredSelector(slot);
}

@interface MTArcRecognizer : UIPanGestureRecognizer
@property(nonatomic, copy) NSString *slot;
@property(nonatomic, copy) NSString *configuredSelector;
@property(nonatomic, copy) NSString *sessionSelector;
@property(nonatomic) double configuredRadius;
@property(nonatomic) BOOL fired;
@property(nonatomic) UIInterfaceOrientation sessionOrientation;
@end
@implementation MTArcRecognizer
- (void)reset {
    [super reset];
    self.fired = NO;
    self.sessionSelector = nil;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    NSUInteger active = 0;
    for (UITouch *touch in event.allTouches)
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) active++;
    NSString *selector = MTArcAvailableSelector(self.slot);
    if (active > 1 || ![selector isEqual:self.configuredSelector] ||
        MTArcGestureRadius(MTPrefsManager.sharedInstance.prefs, self.slot) != self.configuredRadius ||
        (self.sessionSelector && ![self.sessionSelector isEqual:selector])) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    CGSize fixed = UIScreen.mainScreen.fixedCoordinateSpace.bounds.size;
    UIInterfaceOrientation orientation = MTArcOrientation();
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation);
    for (UITouch *touch in touches) {
        // Normal UIKit touches provide their window. System-routed touches
        // without one already report display-oriented coordinates.
        UIWindow *window = touch.window ?: self.view.window;
        CGPoint point = [touch locationInView:window];
        CGPoint origin = point;
        if (window) {
            CGPoint physical = [window convertPoint:point toCoordinateSpace:UIScreen.mainScreen.fixedCoordinateSpace];
            origin = MTArcPointFromFixed(physical.x, physical.y, fixed.width, fixed.height, orientation);
        }
        if (!MTArcZoneContains(origin.x, origin.y, landscape ? fixed.height : fixed.width,
                               landscape ? fixed.width : fixed.height,
                               [self.slot isEqual:@"bottomLeft"], self.configuredRadius)) {
            self.state = UIGestureRecognizerStateFailed;
            return;
        }
    }
    if (!self.sessionSelector) {
        self.sessionSelector = selector;
        self.sessionOrientation = orientation;
    }
    [super touchesBegan:touches withEvent:event];
}
@end

@interface MTArcTarget : NSObject
- (void)slid:(MTArcRecognizer *)recognizer;
@end
@implementation MTArcTarget
- (void)slid:(MTArcRecognizer *)recognizer {
    if (recognizer.fired || (recognizer.state != UIGestureRecognizerStateChanged && recognizer.state != UIGestureRecognizerStateEnded)) return;
    CGPoint translation = [recognizer translationInView:nil];
    if (!MTArcGestureCompletes([recognizer.slot isEqual:@"bottomLeft"], translation.x, translation.y)) return;
    recognizer.fired = YES;
    // Resolve the current shared definition, and reject a stale/rebound touch.
    NSString *expected = recognizer.sessionSelector;
    [MTPrefsManager.sharedInstance reload];
    if (!expected.length || recognizer.sessionOrientation != MTArcOrientation() ||
        MTArcGestureRadius(MTPrefsManager.sharedInstance.prefs, recognizer.slot) != recognizer.configuredRadius ||
        ![expected isEqual:MTArcAvailableSelector(recognizer.slot)]) return;
    NSDictionary *preferences = MTPrefsManager.sharedInstance.prefs;
    NSLog(@"[MetisKeyboard][ArcGesture] trigger slot=%@", recognizer.slot);
    if (MTPanelAllowed(preferences, expected, MTPanelGestureKind)) {
        [MTGlobalPanel.sharedInstance presentPanelSelector:expected fromWindow:nil origin:@"cornerarc"];
    } else {
        MTExecuteGlobalCustomAction(MTPanelActionDefinition(preferences, expected), ^(MTSystemOpenResult result) {
            NSLog(@"[MetisKeyboard][ArcGesture] result slot=%@ status=%llu", recognizer.slot, (unsigned long long)result);
        });
    }
}
@end

static NSMutableDictionary<NSString *, MTArcRecognizer *> *MTArcRecognizers;
static void MTCancelArcSessions(void) {
    for (MTArcRecognizer *recognizer in MTArcRecognizers.allValues) {
        recognizer.enabled = NO;
        recognizer.enabled = YES;
    }
}
static void MTArcManagerDidInitialize(SBSystemGestureManager *manager) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ MTArcManagerDidInitialize(manager); });
        return;
    }
    if (!manager || MTArcManager == manager) return;
    for (MTArcRecognizer *recognizer in MTArcRecognizers.allValues) {
        recognizer.enabled = NO;
        [MTArcManager removeGestureRecognizer:recognizer];
    }
    [MTArcRecognizers removeAllObjects];
    MTArcManager = manager;
    dispatch_async(dispatch_get_main_queue(), ^{ MTUpdateArcGestures(); });
}
static void MTUpdateArcGestures(void) {
    if (!NSThread.isMainThread || ![MTArcManager respondsToSelector:@selector(addGestureRecognizer:withType:)] ||
        ![MTArcManager respondsToSelector:@selector(removeGestureRecognizer:)]) {
        if (NSThread.isMainThread) MTUpdateArcDebugOverlay(nil, @[], MTArcOrientation(), NO);
        return;
    }
    static MTArcTarget *target;
    if (!target) target = [MTArcTarget new];
    if (!MTArcRecognizers) MTArcRecognizers = [NSMutableDictionary dictionary];
    NSArray *slots = MTArcGestureSlots();
    for (NSUInteger index = 0; index < slots.count; index++) {
        NSString *slot = slots[index];
        // Register from configuration, not transient lock/panel/orientation
        // state. touchesBegan gates each attempt; closing a panel needs no
        // unrelated system notification to make the next gesture available.
        NSString *selector = MTArcConfiguredSelector(slot);
        double radius = MTArcGestureRadius(MTPrefsManager.sharedInstance.prefs, slot);
        MTArcRecognizer *existing = MTArcRecognizers[slot];
        if (existing && (![selector isEqual:existing.configuredSelector] || radius != existing.configuredRadius)) {
            existing.enabled = NO; // cancel an in-flight session before removal
            [MTArcManager removeGestureRecognizer:existing];
            [MTArcRecognizers removeObjectForKey:slot];
            existing = nil;
        }
        if (!selector || existing) continue;
        MTArcRecognizer *recognizer = [[MTArcRecognizer alloc] initWithTarget:target action:@selector(slid:)];
        if (!recognizer) continue;
        recognizer.slot = slot;
        recognizer.configuredSelector = selector;
        recognizer.configuredRadius = radius;
        recognizer.minimumNumberOfTouches = 1;
        recognizer.maximumNumberOfTouches = 1;
        [MTArcManager addGestureRecognizer:recognizer withType:MTArcGestureTypeBase + index];
        MTArcRecognizers[slot] = recognizer;
        NSLog(@"[MetisKeyboard][ArcGesture] installed slot=%@ radius=%.0f", slot, radius);
    }
    MTUpdateArcDebugOverlay(MTPrefsManager.sharedInstance.prefs, MTArcRecognizers.allKeys, MTArcOrientation(),
        MTPrefsManager.sharedInstance.preferencesAvailable &&
        MTArcGestureEnabled(MTPrefsManager.sharedInstance.prefs, MTArcLandscape(), kEnabledkey) && [MTGlobalPanel deviceUnlocked]);
}

%group MTArcSystemHooks
%hook SBMainDisplaySystemGestureManager
- (id)_init {
    id manager = %orig;
    // Never create mainDisplayManager before SpringBoard: iOS 17 aborts then.
    if (manager) {
        MTArcManagerDidInitialize(manager);
    }
    return manager;
}
%end
%hook SBSystemGestureManager
- (BOOL)_isGestureWithTypeAllowed:(unsigned long long)type {
    if (type >= MTArcGestureTypeBase && type < MTArcGestureTypeBase + 2) return YES;
    return %orig;
}
- (BOOL)_shouldEnableSystemGestureWithType:(unsigned long long)type {
    if (type >= MTArcGestureTypeBase && type < MTArcGestureTypeBase + 2) return YES;
    return %orig;
}
%end
%end

void MTStartArcGestures(void) {
    if (![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        %init(MTArcSystemHooks);
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSString *name in @[kPrefsChangedIdentifier, @"com.apple.springboard.lockstate",
                                     @"com.apple.springboard.frontmostapplicationchanged"]) {
                int token = NOTIFY_TOKEN_INVALID;
                uint32_t result = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(__unused int delivered) {
                    MTCancelArcSessions();
                    [MTPrefsManager.sharedInstance reload];
                    MTUpdateArcGestures();
                });
                if (result != NOTIFY_STATUS_OK) NSLog(@"[MetisKeyboard][ArcGesture] notification unavailable name=%@ status=%u", name, result);
            }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            for (NSString *name in @[UIApplicationDidFinishLaunchingNotification, UIApplicationDidChangeStatusBarOrientationNotification,
                                     UISceneDidActivateNotification])
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    MTCancelArcSessions();
                    [MTPrefsManager.sharedInstance reload];
                    MTUpdateArcGestures();
                }];
#pragma clang diagnostic pop
            [MTPrefsManager.sharedInstance reload];
            MTUpdateArcGestures();
        });
    });
}
