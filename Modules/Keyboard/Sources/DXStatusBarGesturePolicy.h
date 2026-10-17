#import <Foundation/Foundation.h>
#include <math.h>

#define kDXStatusBarEnabled @"statusbargesturesBOOL"
#define kDXStatusBarLandscape @"statusbargesturesLandscapeBOOL"
#define kDXStatusBarBindings @"statusbargesturebindings"

static inline NSArray<NSString *> *DXStatusBarRegions(void) { return @[@"left", @"middle", @"right"]; }
static inline NSArray<NSString *> *DXStatusBarGestures(void) { return @[@"tap", @"doubletap", @"longpress", @"leftswipe", @"rightswipe"]; }
static inline NSString *DXStatusBarSlot(NSString *region, NSString *gesture) {
    if (![region isKindOfClass:NSString.class] || ![gesture isKindOfClass:NSString.class]) return nil;
    if (![DXStatusBarRegions() containsObject:region] || ![DXStatusBarGestures() containsObject:gesture]) return nil;
    return [NSString stringWithFormat:@"%@.%@", region, gesture];
}
static inline BOOL DXStatusBarSlotValid(id slot) {
    if (![slot isKindOfClass:NSString.class]) return NO;
    NSArray *parts = [slot componentsSeparatedByString:@"."];
    return parts.count == 2 && [DXStatusBarSlot(parts[0], parts[1]) isEqual:slot];
}
static inline BOOL DXStatusBarHostAllowed(NSString *process, NSString *bundleExtension) {
    return [process isEqual:@"SpringBoard"] || [bundleExtension.lowercaseString isEqual:@"app"];
}
static inline BOOL DXStatusBarFlag(id value) { return [value isKindOfClass:NSNumber.class] && [value boolValue]; }
static inline NSDictionary *DXStatusBarBinding(NSDictionary *preferences, NSString *slot) {
    if (![preferences isKindOfClass:NSDictionary.class]) return @{};
    id bindings = preferences[kDXStatusBarBindings];
    id value = [bindings isKindOfClass:NSDictionary.class] && slot.length ? bindings[slot] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static inline NSString *DXStatusBarSelector(NSDictionary *preferences, NSString *slot) {
    NSDictionary *entry = DXStatusBarBinding(preferences, slot);
    id selector = entry[@"selector"];
    return DXStatusBarFlag(entry[@"enabled"]) && [selector isKindOfClass:NSString.class] && [selector length] ? selector : nil;
}
// Relay only a configured slot and the selector the touch observed. Never
// accept a caller-supplied definition or resolve a changed binding later.
static inline BOOL DXStatusBarRequestValid(id request) {
    if (![request isKindOfClass:NSDictionary.class] || [request count] != 3 || !DXStatusBarSlotValid(request[@"slot"])) return NO;
    id selector = request[@"selector"], landscape = request[@"landscape"];
    return [selector isKindOfClass:NSString.class] && [selector length] > 0 && [selector length] <= 256 &&
        [landscape isKindOfClass:NSNumber.class] && ([landscape doubleValue] == 0 || [landscape doubleValue] == 1);
}
static inline NSString *DXStatusBarRequestSelector(NSDictionary *preferences, id request, NSString *masterKey) {
    if (![preferences isKindOfClass:NSDictionary.class] || !DXStatusBarRequestValid(request)) return nil;
    id master = preferences[masterKey];
    if ((master && !DXStatusBarFlag(master)) || !DXStatusBarFlag(preferences[kDXStatusBarEnabled]) ||
        ([request[@"landscape"] boolValue] && !DXStatusBarFlag(preferences[kDXStatusBarLandscape]))) return nil;
    NSString *selector = DXStatusBarSelector(preferences, request[@"slot"]);
    return [selector isEqual:request[@"selector"]] ? selector : nil;
}
// Coordinates are local to the actual status-bar view, never to a fixed screen strip.
static inline NSString *DXStatusBarRegion(double x, double y, double width, double height) {
    if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) ||
        width <= 0 || height <= 0 || x < 0 || x >= width || y < 0 || y >= height) return nil;
    return x < width / 3 ? @"left" : (x < width * 2 / 3 ? @"middle" : @"right");
}
static inline void DXStatusBarRemoveActionReferences(NSMutableDictionary *preferences, NSString *selector) {
    id stored = preferences[kDXStatusBarBindings];
    if (![stored isKindOfClass:NSDictionary.class] || !selector.length) return;
    NSMutableDictionary *bindings = [stored mutableCopy];
    for (NSString *slot in [bindings.allKeys copy]) {
        id value = bindings[slot];
        if (![value isKindOfClass:NSDictionary.class] || ![value[@"selector"] isEqual:selector]) continue;
        NSMutableDictionary *entry = [value mutableCopy];
        [entry removeObjectForKey:@"selector"];
        entry[@"enabled"] = @NO;
        bindings[slot] = entry;
    }
    preferences[kDXStatusBarBindings] = bindings;
}
