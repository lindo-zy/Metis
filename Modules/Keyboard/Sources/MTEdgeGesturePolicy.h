#pragma once
#import <Foundation/Foundation.h>
#include <math.h>

#define kMTEdgeGesturesEnabled @"screenedgegesturesBOOL"
#define kMTEdgeGesturesLandscape @"screenedgegesturesLandscapeBOOL"
#define kMTEdgeGestureBindings @"screenedgegesturebindings"
#define kMTEdgeGesturesDebug @"screenedgegesturesDebugBOOL"

typedef struct { double x, y, width, height; } MTEdgeRegion;
typedef struct { double x, y; } MTEdgePoint;
typedef struct { double startX, endX, y; MTEdgeRegion label; } MTEdgeDistanceGuide;
static inline double MTEdgeRangeNumber(id value, double fallback, double low, double high) {
    double number = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    if (!isfinite(number)) number = fallback;
    return round(fmin(high, fmax(low, number)));
}
static inline NSDictionary *MTEdgeNormalizedRange(id value) {
    NSDictionary *range = [value isKindOfClass:NSDictionary.class] ? value : @{};
    double top = MTEdgeRangeNumber(range[@"yStart"], 0, 0, 99);
    return @{@"width": @(MTEdgeRangeNumber(range[@"width"], 20, 1, 80)),
             @"yStart": @(top), @"yEnd": @(MTEdgeRangeNumber(range[@"yEnd"], 100, top + 1, 100)),
             @"distance": @(MTEdgeRangeNumber(range[@"distance"], 60, 20, 240))};
}

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
static inline NSDictionary *MTEdgeGestureRange(NSDictionary *preferences, NSString *slot) {
    return MTEdgeNormalizedRange(MTEdgeGestureBinding(preferences, slot)[@"range"]);
}
// Coordinates follow the displayed orientation. Persist vertical bounds as
// percentages so the same range remains meaningful across display sizes.
static inline MTEdgeRegion MTEdgeGestureRegion(NSDictionary *range, NSString *slot, double width, double height) {
    if (!MTEdgeGestureSlotValid(slot) || !isfinite(width) || !isfinite(height) || width <= 0 || height <= 0)
        return (MTEdgeRegion){0, 0, 0, 0};
    NSDictionary *normalized = MTEdgeNormalizedRange(range);
    double strip = fmin([normalized[@"width"] doubleValue], width / 2);
    double top = height * [normalized[@"yStart"] doubleValue] / 100;
    double bottom = height * [normalized[@"yEnd"] doubleValue] / 100;
    return (MTEdgeRegion){[slot hasPrefix:@"left"] ? 0 : width - strip, top, strip, bottom - top};
}
static inline BOOL MTEdgeGestureOriginAllowed(NSDictionary *range, NSString *slot, double x, double y, double width, double height) {
    MTEdgeRegion region = MTEdgeGestureRegion(range, slot, width, height);
    return isfinite(x) && isfinite(y) && region.width > 0 && region.height > 0 &&
        x >= region.x && x <= region.x + region.width && y >= region.y && y < region.y + region.height;
}
// UIKit interface-orientation values: portrait=1, upside-down=2,
// landscape-left=3, landscape-right=4. Fixed screen space is portrait based.
static inline MTEdgePoint MTEdgePointFromFixed(double x, double y, double width, double height, NSInteger orientation) {
    if (orientation == 2) return (MTEdgePoint){width - x, height - y};
    if (orientation == 3) return (MTEdgePoint){y, width - x};
    if (orientation == 4) return (MTEdgePoint){height - y, x};
    return (MTEdgePoint){x, y};
}
static inline MTEdgeRegion MTEdgeRegionToFixed(MTEdgeRegion region, double width, double height, NSInteger orientation) {
    if (orientation == 2) return (MTEdgeRegion){width - region.x - region.width, height - region.y - region.height, region.width, region.height};
    if (orientation == 3) return (MTEdgeRegion){width - region.y - region.height, region.x, region.height, region.width};
    if (orientation == 4) return (MTEdgeRegion){region.y, height - region.x - region.width, region.height, region.width};
    return region;
}
// A 1:1 pt ruler anchored at the screen edge, not centred: the swipe starts
// at the edge and travels this distance inward, so a centred bar would
// misreport where the finger must begin. Each assigned gesture gets a stable
// row, with an inward-pointing arrow.
static inline MTEdgeDistanceGuide MTEdgeDistanceGuideLayout(NSDictionary *range, NSString *slot,
    double width, double height, NSUInteger index, NSUInteger count) {
    double distance = [MTEdgeNormalizedRange(range)[@"distance"] doubleValue];
    if (!MTEdgeGestureSlotValid(slot) || !isfinite(width) || !isfinite(height) || count == 0 || count > 4 ||
        index >= count || width < distance + 24 || height < count * 52 + 16) return (MTEdgeDistanceGuide){0};
    double top = (height - ((count - 1) * 52 + 40)) / 2 + index * 52;
    BOOL fromLeft = [slot hasPrefix:@"left"];
    return (MTEdgeDistanceGuide){fromLeft ? 0 : width, fromLeft ? distance : width - distance,
        top + 34, {12, top, width - 24, 20}};
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
static inline BOOL MTEdgeGestureCompletesWithRange(NSDictionary *range, BOOL left, double dx, double dy) {
    double inward = left ? dx : -dx;
    return isfinite(dx) && isfinite(dy) && inward >= [MTEdgeNormalizedRange(range)[@"distance"] doubleValue] && fabs(dy) <= inward;
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
