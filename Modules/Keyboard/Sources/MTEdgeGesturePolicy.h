#pragma once
#import <Foundation/Foundation.h>
#include <math.h>

#define kMTEdgeGesturesEnabled @"screenedgegesturesBOOL"
#define kMTEdgeGesturesLandscape @"screenedgegesturesLandscapeBOOL"
#define kMTEdgeGestureBindings @"screenedgegesturebindings"

static inline NSArray<NSString *> *MTEdgeGestureSlots(void) { return @[@"left", @"right", @"left2", @"right2"]; }
static inline BOOL MTEdgeGestureSlotValid(id slot) {
    return [slot isKindOfClass:NSString.class] && [MTEdgeGestureSlots() containsObject:slot];
}
static inline BOOL MTEdgeGestureFlag(id value) { return [value isKindOfClass:NSNumber.class] && [value boolValue]; }
static inline NSDictionary *MTEdgeGestureBinding(NSDictionary *preferences, NSString *slot) {
    if (![preferences isKindOfClass:NSDictionary.class] || !MTEdgeGestureSlotValid(slot)) return @{};
    id bindings = preferences[kMTEdgeGestureBindings];
    id entry = [bindings isKindOfClass:NSDictionary.class] ? bindings[slot] : nil;
    return [entry isKindOfClass:NSDictionary.class] ? entry : @{};
}
static inline NSString *MTEdgeGestureSelector(NSDictionary *preferences, NSString *slot) {
    NSDictionary *entry = MTEdgeGestureBinding(preferences, slot);
    id selector = entry[@"selector"];
    return MTEdgeGestureFlag(entry[@"enabled"]) && [selector isKindOfClass:NSString.class] &&
        [selector length] > 0 && [selector length] <= 256 ? selector : nil;
}
static inline BOOL MTEdgeGestureEnabled(NSDictionary *preferences, BOOL landscape, NSString *masterKey) {
    if (![preferences isKindOfClass:NSDictionary.class]) return NO;
    id master = preferences[masterKey];
    return (!master || MTEdgeGestureFlag(master)) && MTEdgeGestureFlag(preferences[kMTEdgeGesturesEnabled]) &&
        (!landscape || MTEdgeGestureFlag(preferences[kMTEdgeGesturesLandscape]));
}
static inline BOOL MTEdgeGestureCompletes(BOOL left, double dx, double dy) {
    double inward = left ? dx : -dx;
    return isfinite(dx) && isfinite(dy) && inward >= 60 && fabs(dy) <= inward;
}
static inline void MTEdgeGestureRemoveActionReferences(NSMutableDictionary *preferences, NSString *selector) {
    id stored = preferences[kMTEdgeGestureBindings];
    if (![stored isKindOfClass:NSDictionary.class] || !selector.length) return;
    NSMutableDictionary *bindings = [stored mutableCopy];
    for (NSString *slot in bindings.allKeys) {
        id value = bindings[slot];
        if (![value isKindOfClass:NSDictionary.class] || ![value[@"selector"] isEqual:selector]) continue;
        NSMutableDictionary *entry = [value mutableCopy];
        [entry removeObjectForKey:@"selector"];
        entry[@"enabled"] = @NO;
        bindings[slot] = entry;
    }
    preferences[kMTEdgeGestureBindings] = bindings;
}
