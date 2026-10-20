#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

#define kMTArcGesturesEnabled @"arcgesturesBOOL"
#define kMTArcGesturesLandscape @"arcgesturesLandscapeBOOL"
#define kMTArcGestureBindings @"arcgesturebindings"

static inline NSArray<NSString *> *MTArcGestureSlots(void) { return @[@"bottomLeft", @"bottomRight"]; }
static inline BOOL MTArcGestureSlotValid(id slot) {
    return [slot isKindOfClass:NSString.class] && [MTArcGestureSlots() containsObject:slot];
}
static inline BOOL MTArcGestureFlag(id value) {
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}
static inline NSDictionary *MTArcGestureBinding(NSDictionary *preferences, NSString *slot) {
    if (![preferences isKindOfClass:NSDictionary.class] || !MTArcGestureSlotValid(slot)) return @{};
    id bindings = preferences[kMTArcGestureBindings];
    id entry = [bindings isKindOfClass:NSDictionary.class] ? bindings[slot] : nil;
    return [entry isKindOfClass:NSDictionary.class] ? entry : @{};
}
static inline NSString *MTArcGestureSelector(NSDictionary *preferences, NSString *slot) {
    NSDictionary *entry = MTArcGestureBinding(preferences, slot);
    id selector = entry[@"selector"];
    return MTArcGestureFlag(entry[@"enabled"]) && [selector isKindOfClass:NSString.class] &&
        [selector length] > 0 && [selector length] <= 256 ? selector : nil;
}
// 角点扇形触发半径（pt）：默认 40，收敛到 [8, 300]，与设置页滑杆一致。
static inline double MTArcGestureRadius(NSDictionary *preferences, NSString *slot) {
    id stored = MTArcGestureBinding(preferences, slot)[@"radius"];
    double radius = [stored isKindOfClass:NSNumber.class] ? [stored doubleValue] : 40;
    if (!isfinite(radius)) radius = 40;
    return round(fmin(300, fmax(8, radius)));
}
static inline BOOL MTArcGestureEnabled(NSDictionary *preferences, BOOL landscape, NSString *masterKey) {
    if (![preferences isKindOfClass:NSDictionary.class]) return NO;
    id master = preferences[masterKey];
    return (!master || MTArcGestureFlag(master)) && MTArcGestureFlag(preferences[kMTArcGesturesEnabled]) &&
        (!landscape || MTArcGestureFlag(preferences[kMTArcGesturesLandscape]));
}
// UIKit interface-orientation values: portrait=1, upside-down=2,
// landscape-left=3, landscape-right=4. Fixed screen space is portrait based.
static inline CGPoint MTArcPointFromFixed(double x, double y, double width, double height, NSInteger orientation) {
    if (orientation == 2) return CGPointMake(width - x, height - y);
    if (orientation == 3) return CGPointMake(y, width - x);
    if (orientation == 4) return CGPointMake(height - y, x);
    return CGPointMake(x, y);
}
// 触点落在以屏幕底角为圆心的四分之一圆内（按显示方向计算）。
static inline BOOL MTArcZoneContains(double x, double y, double width, double height, BOOL left, double radius) {
    if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) || width <= 0 || height <= 0) return NO;
    double dx = left ? x : width - x;   // 距角点向屏幕内的横向距离
    double dy = height - y;             // 距底边向上的距离
    return dx >= 0 && dy >= 0 && hypot(dx, dy) <= radius;
}
// 从角点向屏幕内划出：位移指向远离角点的四分之一方向，且划出足够距离。
static inline BOOL MTArcGestureCompletes(BOOL left, double dx, double dy) {
    if (!isfinite(dx) || !isfinite(dy)) return NO;
    double inward = left ? dx : -dx;
    double lift = -dy;
    return inward >= 0 && lift >= 0 && hypot(inward, lift) >= 60;
}
static inline void MTArcGestureRemoveActionReferences(NSMutableDictionary *preferences, NSString *selector) {
    id stored = preferences[kMTArcGestureBindings];
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
    preferences[kMTArcGestureBindings] = bindings;
}
