#import <Foundation/Foundation.h>
#import "MTKeyboardPanelPreferences.h"
#import "MTGlobalPanelPolicy.h"

#define kMTDockGestureBindings @"dockgesturebindings"
#define kMTDockLeftSwipeEnabled @"dockleftswipeBOOL"
#define kMTDockRightSwipeEnabled @"dockrightswipeBOOL"

static inline NSArray<NSString *> *MTDockGestureDirections(void) { return @[@"up", @"left", @"right"]; }
static inline NSString *MTDockGestureEnabledKey(NSString *direction) {
    if ([direction isEqual:@"up"]) return kMTPanelDockSwipeEnabled;
    if ([direction isEqual:@"left"]) return kMTDockLeftSwipeEnabled;
    if ([direction isEqual:@"right"]) return kMTDockRightSwipeEnabled;
    return nil;
}
static inline BOOL MTDockGestureEnabled(NSDictionary *preferences, NSString *direction) {
    NSString *key = MTDockGestureEnabledKey(direction);
    return key && [preferences isKindOfClass:NSDictionary.class] &&
        MTKeyboardPanelBool(preferences, key, [direction isEqual:@"up"]);
}
// Every direction requires an explicit binding. Legacy defaults are resolved
// once by panel migration; cleared or malformed bindings never restore them.
static inline NSString *MTDockGestureConfiguredSelector(NSDictionary *preferences, NSString *direction) {
    if (!MTDockGestureEnabledKey(direction) || ![preferences isKindOfClass:NSDictionary.class]) return nil;
    id bindings = preferences[kMTDockGestureBindings];
    if (bindings && ![bindings isKindOfClass:NSDictionary.class]) return nil;
    id selector = bindings[direction];
    return [selector isKindOfClass:NSString.class] && [selector length] ? selector : nil;
}
static inline NSString *MTDockGestureSelector(NSDictionary *preferences, NSString *direction) {
    return MTDockGestureEnabled(preferences, direction) ? MTDockGestureConfiguredSelector(preferences, direction) : nil;
}
static inline NSDictionary *MTDockGestureDefinition(NSDictionary *preferences, NSString *selector, NSString *definitionsKey) {
    if (![preferences isKindOfClass:NSDictionary.class] || ![selector isKindOfClass:NSString.class] ||
        !selector.length || ![definitionsKey isKindOfClass:NSString.class] || !definitionsKey.length) return nil;
    id definitions = preferences[definitionsKey];
    if (![definitions isKindOfClass:NSArray.class]) return nil;
    for (id entry in definitions)
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return entry;
    return nil;
}
static inline NSString *MTDockGestureDirection(double dx, double dy) {
    if (!isfinite(dx) || !isfinite(dy)) return nil;
    if (dy < 0 && -dy >= fabs(dx) * 1.5) return @"up";
    if (dx != 0 && fabs(dx) >= fabs(dy) * 1.5) return dx < 0 ? @"left" : @"right";
    return nil;
}
static inline BOOL MTDockGestureCompletes(NSString *direction, double dx, double dy) {
    if (![MTDockGestureDirection(dx, dy) isEqual:direction]) return NO;
    return [direction isEqual:@"up"] ? MTDockPanelSwipeCompletes(dx, dy) : fabs(dx) >= 48;
}
static inline void MTDockGestureRemoveActionReferences(NSMutableDictionary *preferences, NSString *selector) {
    id stored = preferences[kMTDockGestureBindings];
    if (![stored isKindOfClass:NSDictionary.class] || !selector.length) return;
    NSMutableDictionary *bindings = [stored mutableCopy];
    for (NSString *direction in MTDockGestureDirections()) {
        if (![bindings[direction] isEqual:selector]) continue;
        bindings[direction] = @"";
        preferences[MTDockGestureEnabledKey(direction)] = @NO;
    }
    preferences[kMTDockGestureBindings] = bindings;
}
