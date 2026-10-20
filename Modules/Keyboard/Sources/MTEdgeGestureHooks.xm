// System-edge recognizer registration adapted from Triggr 1.x (GPL-3.0),
// Jond-ie/triggr, Tweak/Tweak.x, "Screen edges". Actions use Metis exclusively.
#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <notify.h>
#import "MTEdgeGestures.h"
#import "MTEdgeGesturePolicy.h"
#import "MTPanelRegistry.h"
#import "MTGlobalPanel.h"
#import "MTGlobalPanelPolicy.h"
#import "MTGlobalActionExecutor.h"
#import "common.h"

@interface SBSystemGestureManager : NSObject
- (void)addGestureRecognizer:(UIGestureRecognizer *)recognizer withType:(unsigned long long)type;
- (void)removeGestureRecognizer:(UIGestureRecognizer *)recognizer;
@end
@interface UIScreenEdgePanGestureRecognizer (MTEdgePrivate)
- (instancetype)initWithTarget:(id)target action:(SEL)action type:(long long)type options:(unsigned long long)options;
- (void)_setEdgeRegionSize:(double)size;
@end

// Own namespace: must not collide with Triggr or Apple's gesture types.
static const unsigned long long MTEdgeGestureTypeBase = 0x6d746500;
static SBSystemGestureManager *MTEdgeManager;
static void MTUpdateEdgeGestures(void);

static BOOL MTEdgeLandscape(void) {
    // SpringBoard's active orientation follows the display, including apps
    // that do not rotate the device's physical orientation.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIInterfaceOrientation orientation = UIApplication.sharedApplication.statusBarOrientation;
#pragma clang diagnostic pop
    return UIInterfaceOrientationIsLandscape(orientation);
}
static NSString *MTEdgeConfiguredSelector(NSString *slot) {
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    if (!manager.preferencesAvailable || !MTEdgeGestureEnabled(manager.prefs, NO, kEnabledkey)) return nil;
    NSString *selector = MTEdgeGestureSelector(manager.prefs, slot);
    if (MTPanelAllowed(manager.prefs, selector, MTPanelGestureKind)) return selector;
    return MTGlobalCustomActionSupported(MTPanelActionDefinition(manager.prefs, selector)) ? selector : nil;
}
static NSString *MTEdgeAvailableSelector(NSString *slot) {
    if (!MTEdgeGestureEnabled(MTPrefsManager.sharedInstance.prefs, MTEdgeLandscape(), kEnabledkey) ||
        ![MTGlobalPanel deviceUnlocked] || [MTGlobalPanel.sharedInstance isVisible]) return nil;
    return MTEdgeConfiguredSelector(slot);
}

@interface MTEdgeRecognizer : UIScreenEdgePanGestureRecognizer
@property(nonatomic, copy) NSString *slot;
@property(nonatomic, copy) NSString *configuredSelector;
@property(nonatomic, copy) NSString *sessionSelector;
@property(nonatomic) NSUInteger fingers;
@property(nonatomic) BOOL fired;
@property(nonatomic) BOOL sessionLandscape;
@end
@implementation MTEdgeRecognizer
- (void)reset {
    [super reset];
    self.fired = NO;
    self.sessionSelector = nil;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    NSUInteger active = 0;
    for (UITouch *touch in event.allTouches)
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) active++;
    NSString *selector = MTEdgeAvailableSelector(self.slot);
    if (active > self.fingers || ![selector isEqual:self.configuredSelector] ||
        (self.sessionSelector && ![self.sessionSelector isEqual:selector])) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    if (!self.sessionSelector) {
        self.sessionSelector = selector;
        self.sessionLandscape = MTEdgeLandscape();
    }
    [super touchesBegan:touches withEvent:event];
}
@end

@interface MTEdgeTarget : NSObject
- (void)slid:(MTEdgeRecognizer *)recognizer;
@end
@implementation MTEdgeTarget
- (void)slid:(MTEdgeRecognizer *)recognizer {
    if (recognizer.fired || (recognizer.state != UIGestureRecognizerStateChanged && recognizer.state != UIGestureRecognizerStateEnded)) return;
    CGPoint translation = [recognizer translationInView:nil];
    if (!MTEdgeGestureCompletes([recognizer.slot hasPrefix:@"left"], translation.x, translation.y)) return;
    recognizer.fired = YES;
    // Resolve the current shared definition, and reject a stale/rebound touch.
    NSString *expected = recognizer.sessionSelector;
    [MTPrefsManager.sharedInstance reload];
    if (!expected.length || recognizer.sessionLandscape != MTEdgeLandscape() ||
        ![expected isEqual:MTEdgeAvailableSelector(recognizer.slot)]) return;
    NSDictionary *preferences = MTPrefsManager.sharedInstance.prefs;
    NSLog(@"[MetisKeyboard][EdgeGesture] trigger slot=%@", recognizer.slot);
    if (MTPanelAllowed(preferences, expected, MTPanelGestureKind)) {
        [MTGlobalPanel.sharedInstance presentPanelSelector:expected fromWindow:nil origin:@"screenedge"];
    } else {
        MTExecuteGlobalCustomAction(MTPanelActionDefinition(preferences, expected), ^(MTSystemOpenResult result) {
            NSLog(@"[MetisKeyboard][EdgeGesture] result slot=%@ status=%llu", recognizer.slot, (unsigned long long)result);
        });
    }
}
@end

static NSMutableDictionary<NSString *, MTEdgeRecognizer *> *MTEdgeRecognizers;
static void MTCancelEdgeSessions(void) {
    for (MTEdgeRecognizer *recognizer in MTEdgeRecognizers.allValues) {
        recognizer.enabled = NO;
        recognizer.enabled = YES;
    }
}
static void MTEdgeManagerDidInitialize(SBSystemGestureManager *manager) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ MTEdgeManagerDidInitialize(manager); });
        return;
    }
    if (!manager || MTEdgeManager == manager) return;
    for (MTEdgeRecognizer *recognizer in MTEdgeRecognizers.allValues) {
        recognizer.enabled = NO;
        [MTEdgeManager removeGestureRecognizer:recognizer];
    }
    [MTEdgeRecognizers removeAllObjects];
    MTEdgeManager = manager;
    dispatch_async(dispatch_get_main_queue(), ^{ MTUpdateEdgeGestures(); });
}
static void MTUpdateEdgeGestures(void) {
    if (!NSThread.isMainThread || ![MTEdgeManager respondsToSelector:@selector(addGestureRecognizer:withType:)] ||
        ![MTEdgeManager respondsToSelector:@selector(removeGestureRecognizer:)]) return;
    static MTEdgeTarget *target;
    if (!target) target = [MTEdgeTarget new];
    if (!MTEdgeRecognizers) MTEdgeRecognizers = [NSMutableDictionary dictionary];
    NSArray *slots = MTEdgeGestureSlots();
    for (NSUInteger index = 0; index < slots.count; index++) {
        NSString *slot = slots[index];
        // Register from configuration, not transient lock/panel/orientation
        // state. touchesBegan gates each attempt; closing a panel needs no
        // unrelated system notification to make the next gesture available.
        NSString *selector = MTEdgeConfiguredSelector(slot);
        MTEdgeRecognizer *existing = MTEdgeRecognizers[slot];
        if (existing && ![selector isEqual:existing.configuredSelector]) {
            existing.enabled = NO; // cancel an in-flight session before removal
            [MTEdgeManager removeGestureRecognizer:existing];
            [MTEdgeRecognizers removeObjectForKey:slot];
            existing = nil;
        }
        if (!selector || existing) continue;
        if (![MTEdgeRecognizer instancesRespondToSelector:@selector(initWithTarget:action:type:options:)]) continue;
        MTEdgeRecognizer *recognizer = [[MTEdgeRecognizer alloc] initWithTarget:target action:@selector(slid:) type:2 options:0];
        if (!recognizer) continue;
        recognizer.slot = slot;
        recognizer.configuredSelector = selector;
        recognizer.fingers = [slot hasSuffix:@"2"] ? 2 : 1;
        recognizer.edges = [slot hasPrefix:@"left"] ? UIRectEdgeLeft : UIRectEdgeRight;
        recognizer.minimumNumberOfTouches = recognizer.fingers;
        recognizer.maximumNumberOfTouches = recognizer.fingers;
        if ([recognizer respondsToSelector:@selector(_setEdgeRegionSize:)]) [recognizer _setEdgeRegionSize:20];
        [MTEdgeManager addGestureRecognizer:recognizer withType:MTEdgeGestureTypeBase + index];
        MTEdgeRecognizers[slot] = recognizer;
        NSLog(@"[MetisKeyboard][EdgeGesture] installed slot=%@ fingers=%lu", slot, (unsigned long)recognizer.fingers);
    }
}

%group MTEdgeSystemHooks
%hook SBMainDisplaySystemGestureManager
- (id)_init {
    id manager = %orig;
    // Never create mainDisplayManager before SpringBoard: iOS 17 aborts then.
    if (manager) {
        MTEdgeManagerDidInitialize(manager);
    }
    return manager;
}
%end
%hook SBSystemGestureManager
- (BOOL)_isGestureWithTypeAllowed:(unsigned long long)type {
    if (type >= MTEdgeGestureTypeBase && type < MTEdgeGestureTypeBase + 4) return YES;
    return %orig;
}
- (BOOL)_shouldEnableSystemGestureWithType:(unsigned long long)type {
    if (type >= MTEdgeGestureTypeBase && type < MTEdgeGestureTypeBase + 4) return YES;
    return %orig;
}
%end
%end

void MTStartEdgeGestures(void) {
    if (![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        %init(MTEdgeSystemHooks);
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSString *name in @[kPrefsChangedIdentifier, @"com.apple.springboard.lockstate",
                                     @"com.apple.springboard.frontmostapplicationchanged"]) {
                int token = NOTIFY_TOKEN_INVALID;
                uint32_t result = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(__unused int delivered) {
                    MTCancelEdgeSessions();
                    [MTPrefsManager.sharedInstance reload];
                    MTUpdateEdgeGestures();
                });
                if (result != NOTIFY_STATUS_OK) NSLog(@"[MetisKeyboard][EdgeGesture] notification unavailable name=%@ status=%u", name, result);
            }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            for (NSString *name in @[UIApplicationDidFinishLaunchingNotification, UIApplicationDidChangeStatusBarOrientationNotification])
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    MTCancelEdgeSessions();
                    [MTPrefsManager.sharedInstance reload];
                    MTUpdateEdgeGestures();
                }];
#pragma clang diagnostic pop
            [MTPrefsManager.sharedInstance reload];
            MTUpdateEdgeGestures();
        });
    });
}
