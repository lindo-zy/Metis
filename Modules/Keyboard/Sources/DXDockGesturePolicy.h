#import <Foundation/Foundation.h>
#import "DXKeyboardPanelPreferences.h"
#import "DXGlobalPanelPolicy.h"

#define kDXDockGestureBindings @"dockgesturebindings"
#define kDXDockLeftSwipeEnabled @"dockleftswipeBOOL"
#define kDXDockRightSwipeEnabled @"dockrightswipeBOOL"

static inline NSArray<NSString *> *DXDockGestureDirections(void) { return @[@"up", @"left", @"right"]; }
static inline NSString *DXDockGestureEnabledKey(NSString *direction) {
    if ([direction isEqual:@"up"]) return kDXPanelDockSwipeEnabled;
    if ([direction isEqual:@"left"]) return kDXDockLeftSwipeEnabled;
    if ([direction isEqual:@"right"]) return kDXDockRightSwipeEnabled;
    return nil;
}
static inline BOOL DXDockGestureEnabled(NSDictionary *preferences, NSString *direction) {
    NSString *key = DXDockGestureEnabledKey(direction);
    return key && [preferences isKindOfClass:NSDictionary.class] &&
        DXKeyboardPanelBool(preferences, key, [direction isEqual:@"up"]);
}
// Every direction requires an explicit binding. Legacy defaults are resolved
// once by panel migration; cleared or malformed bindings never restore them.
static inline NSString *DXDockGestureConfiguredSelector(NSDictionary *preferences, NSString *direction) {
    if (!DXDockGestureEnabledKey(direction) || ![preferences isKindOfClass:NSDictionary.class]) return nil;
    id bindings = preferences[kDXDockGestureBindings];
    if (bindings && ![bindings isKindOfClass:NSDictionary.class]) return nil;
    id selector = bindings[direction];
    return [selector isKindOfClass:NSString.class] && [selector length] ? selector : nil;
}
static inline NSString *DXDockGestureSelector(NSDictionary *preferences, NSString *direction) {
    return DXDockGestureEnabled(preferences, direction) ? DXDockGestureConfiguredSelector(preferences, direction) : nil;
}
static inline NSDictionary *DXDockGestureDefinition(NSDictionary *preferences, NSString *selector, NSString *definitionsKey) {
    if (![preferences isKindOfClass:NSDictionary.class] || ![selector isKindOfClass:NSString.class] ||
        !selector.length || ![definitionsKey isKindOfClass:NSString.class] || !definitionsKey.length) return nil;
    id definitions = preferences[definitionsKey];
    if (![definitions isKindOfClass:NSArray.class]) return nil;
    for (id entry in definitions)
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return entry;
    return nil;
}
static inline NSString *DXDockGestureDirection(double dx, double dy) {
    if (!isfinite(dx) || !isfinite(dy)) return nil;
    if (dy < 0 && -dy >= fabs(dx) * 1.5) return @"up";
    if (dx != 0 && fabs(dx) >= fabs(dy) * 1.5) return dx < 0 ? @"left" : @"right";
    return nil;
}
static inline BOOL DXDockGestureCompletes(NSString *direction, double dx, double dy) {
    if (![DXDockGestureDirection(dx, dy) isEqual:direction]) return NO;
    return [direction isEqual:@"up"] ? DXDockPanelSwipeCompletes(dx, dy) : fabs(dx) >= 48;
}
static inline void DXDockGestureRemoveActionReferences(NSMutableDictionary *preferences, NSString *selector) {
    id stored = preferences[kDXDockGestureBindings];
    if (![stored isKindOfClass:NSDictionary.class] || !selector.length) return;
    NSMutableDictionary *bindings = [stored mutableCopy];
    for (NSString *direction in DXDockGestureDirections()) {
        if (![bindings[direction] isEqual:selector]) continue;
        bindings[direction] = @"";
        preferences[DXDockGestureEnabledKey(direction)] = @NO;
    }
    preferences[kDXDockGestureBindings] = bindings;
}
