#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// 屏幕左下/右下角落上滑手势：扇形触发区锚定在全屏常规窗口 bounds 的底角，
// 半径与张角可调（设置页实时预览）。只支持上滑一种手势，slot 形如 bottomleft.up。
#define kMTCornerGesturesEnabled @"cornergesturesBOOL"
#define kMTCornerGestureBindings @"cornergesturebindings"
#define kMTCornerGestureRadiusKey @"cornergestureRadius"
#define kMTCornerGestureAngleKey @"cornergestureAngle"

#define kMTCornerGestureRadiusDefault 120.0
#define kMTCornerGestureRadiusMin 60.0
#define kMTCornerGestureRadiusMax 240.0
#define kMTCornerGestureAngleDefault 90.0
#define kMTCornerGestureAngleMin 30.0
#define kMTCornerGestureAngleMax 120.0

static inline NSArray<NSString *> *MTCornerGestureRegions(void) { return @[@"bottomleft", @"bottomright"]; }
static inline NSArray<NSString *> *MTCornerGestureKinds(void) { return @[@"up"]; }
static inline NSString *MTCornerGestureSlot(NSString *region) {
    if (![region isKindOfClass:NSString.class] || ![MTCornerGestureRegions() containsObject:region]) return nil;
    return [NSString stringWithFormat:@"%@.up", region];
}
static inline BOOL MTCornerGestureSlotValid(id slot) {
    return [slot isKindOfClass:NSString.class] && [MTCornerGestureSlot(slot) isEqual:slot];
}
static inline BOOL MTCornerGestureFlag(id value) { return [value isKindOfClass:NSNumber.class] && [value boolValue]; }
// 总开关缺省开：不绑定动作时手势本就不生效，无需强制用户先开开关。
static inline BOOL MTCornerGestureMasterEnabled(NSDictionary *preferences) {
    if (![preferences isKindOfClass:NSDictionary.class]) return NO;
    id value = preferences[kMTCornerGesturesEnabled];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}
static inline NSDictionary *MTCornerGestureBinding(NSDictionary *preferences, NSString *slot) {
    if (![preferences isKindOfClass:NSDictionary.class] || !MTCornerGestureSlotValid(slot)) return @{};
    id bindings = preferences[kMTCornerGestureBindings];
    id value = [bindings isKindOfClass:NSDictionary.class] ? bindings[slot] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static inline NSString *MTCornerGestureSelector(NSDictionary *preferences, NSString *slot) {
    NSDictionary *entry = MTCornerGestureBinding(preferences, slot);
    id selector = entry[@"selector"];
    // enabled 缺省视为开：与状态栏手势一致的宽松缺省，绑定即生效。
    id enabled = entry[@"enabled"];
    if (([enabled isKindOfClass:NSNumber.class] && ![enabled boolValue]) ||
        ![selector isKindOfClass:NSString.class] || ![(NSString *)selector length]) return nil;
    return selector;
}
static inline double MTCornerGestureClamp(double value, double min, double max, double fallback) {
    return isfinite(value) && value >= min && value <= max ? value : fallback;
}
static inline double MTCornerGestureRadius(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:NSDictionary.class] ? preferences[kMTCornerGestureRadiusKey] : nil;
    return MTCornerGestureClamp([value isKindOfClass:NSNumber.class] ? [value doubleValue] : NAN,
        kMTCornerGestureRadiusMin, kMTCornerGestureRadiusMax, kMTCornerGestureRadiusDefault);
}
static inline double MTCornerGestureAngle(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:NSDictionary.class] ? preferences[kMTCornerGestureAngleKey] : nil;
    return MTCornerGestureClamp([value isKindOfClass:NSNumber.class] ? [value doubleValue] : NAN,
        kMTCornerGestureAngleMin, kMTCornerGestureAngleMax, kMTCornerGestureAngleDefault);
}

// 扇形命中判定：point 为窗口 bounds 坐标，扇形锚点在窗口底角、角平分线指向
// 屏幕内侧 45°（上-内对角线），张角以角平分线对称分布。锚点允许 y == 底边
// （手指贴边上滑的常见起点），但绝不接受低于底边的点。
static inline NSString *MTCornerRegionAtPoint(CGPoint point, CGSize size, double radius, double angle) {
    if (!isfinite(point.x) || !isfinite(point.y) || !isfinite(radius) || !isfinite(angle) ||
        size.width <= 0 || size.height <= 0 || point.x < 0 || point.x > size.width ||
        point.y < 0 || point.y > size.height) return nil;
    double dx = point.x <= size.width / 2 ? point.x : point.x - size.width;
    double dy = point.y - size.height;
    if (dy > 0) return nil;
    double length = hypot(dx, dy);
    if (length > radius) return nil;
    // bisector = (±cos45°, -sin45°)；点积 >= |v|·cos(半张角) 即落在扇形内。
    double cosHalf = cos(MTCornerGestureClamp(angle, 0, 180, 90) * M_PI / 180 / 2);
    if (length == 0) return point.x <= size.width / 2 ? @"bottomleft" : @"bottomright";
    double bisectorX = point.x <= size.width / 2 ? M_SQRT1_2 : -M_SQRT1_2;
    if (dx * bisectorX + dy * -M_SQRT1_2 < length * cosHalf) return nil;
    return point.x <= size.width / 2 ? @"bottomleft" : @"bottomright";
}
// 上滑方向：主导向上即可（允许对角上滑），与 Dock 上滑的 1.5:1 相比放宽到 0.75:1。
static inline BOOL MTCornerGestureUpward(double dx, double dy) {
    return isfinite(dx) && isfinite(dy) && dy < 0 && -dy >= fabs(dx) * 0.75;
}
static inline BOOL MTCornerGestureCompletes(double dx, double dy) {
    return MTCornerGestureUpward(dx, dy) && dy <= -36;
}
// Dock 手势互斥：命中已配置的角落扇形时，Dock 上滑放行给角落识别器。
static inline NSString *MTCornerGestureClaimedSlot(NSDictionary *preferences, CGSize size, CGPoint point) {
    if (!MTCornerGestureMasterEnabled(preferences)) return nil;
    NSString *region = MTCornerRegionAtPoint(point, size, MTCornerGestureRadius(preferences), MTCornerGestureAngle(preferences));
    return region && MTCornerGestureSelector(preferences, MTCornerGestureSlot(region)) ? region : nil;
}

// Relay only a configured slot and the selector the touch observed. Never
// accept a caller-supplied definition or resolve a changed binding later.
static inline BOOL MTCornerGestureRequestValid(id request) {
    if (![request isKindOfClass:NSDictionary.class] || [request count] != 2 || !MTCornerGestureSlotValid(request[@"slot"])) return NO;
    id selector = request[@"selector"];
    return [selector isKindOfClass:NSString.class] && [selector length] > 0 && [selector length] <= 256;
}
static inline NSString *MTCornerGestureRequestSelector(NSDictionary *preferences, id request, NSString *masterKey) {
    if (![preferences isKindOfClass:NSDictionary.class] || !MTCornerGestureRequestValid(request)) return nil;
    id master = preferences[masterKey];
    if (master && !MTCornerGestureFlag(master)) return nil;
    if (!MTCornerGestureMasterEnabled(preferences)) return nil;
    NSString *selector = MTCornerGestureSelector(preferences, request[@"slot"]);
    return [selector isEqual:request[@"selector"]] ? selector : nil;
}
static inline void MTCornerGestureRemoveActionReferences(NSMutableDictionary *preferences, NSString *selector) {
    id stored = preferences[kMTCornerGestureBindings];
    if (![stored isKindOfClass:NSDictionary.class] || ![selector length]) return;
    NSMutableDictionary *bindings = [stored mutableCopy];
    for (NSString *region in MTCornerGestureRegions()) {
        NSString *slot = MTCornerGestureSlot(region);
        id entry = [bindings[slot] isKindOfClass:NSDictionary.class] ? bindings[slot] : nil;
        if (![entry[@"selector"] isEqual:selector]) continue;
        NSMutableDictionary *mutable = [entry mutableCopy];
        [mutable removeObjectForKey:@"selector"];
        mutable[@"enabled"] = @NO;
        bindings[slot] = mutable;
    }
    preferences[kMTCornerGestureBindings] = bindings;
}
