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

// 触发区上移量：扇形锚点从窗口几何底角抬起 bottomInset 个点。App 内屏幕底部
// 20pt 左右是 Home 指示条系统手势区、34pt 起通常是 Tab bar，扇形压在这两段上
// 会让手指的起手点落进系统/原生控件的争夺范围。上移后扇形主体进入内容区，
// 锚点以下保留一条贴边起手容错带，供习惯从更靠下的地方划上来的手势使用。
#define kMTCornerGestureBottomInsetKey @"cornergestureBottomInset"
#define kMTCornerGestureBottomInsetDefault 34.0
#define kMTCornerGestureBottomInsetMin 0.0
#define kMTCornerGestureBottomInsetMax 100.0
// 起手容错带横向宽度 = 半径 × 该系数，随扇形一起缩放。
#define kMTCornerGestureLiftBandRatio 0.5

// 灵敏度档位：0 标准（沿用早期固定阈值），1 灵敏（默认），2 极灵敏。
// 只影响完成位移门槛、上滑方向比与快速甩动兜底，不改变命中几何。
#define kMTCornerGestureSensitivityKey @"cornergestureSensitivity"
#define kMTCornerGestureSensitivityDefault 1
#define kMTCornerGestureSensitivityMin 0
#define kMTCornerGestureSensitivityMax 2

// 二维扇形的命中条件同时约束横向与纵向两个维度，手指必须落在角落附近的更小
// 一片区域里，这是「App 内难触发」的第二个成因（第一个是进程层级）。这里按
// SquidGesture 的通行做法补一条一维模型：只看起点到侧边的横向距离，纵向不设限
// 制。命中区划分三个层级，越靠边的层级优先且可以各自绑定不同动作。
//   zone 0（标准）/ 1（宽）/ 2（更宽）整体缩放三档宽度。
#define kMTCornerGestureZoneKey @"cornergestureZone"
#define kMTCornerGestureZoneStandard 0
#define kMTCornerGestureZoneWide 1
#define kMTCornerGestureZoneWidest 2
#define kMTCornerGestureZoneDefault kMTCornerGestureZoneStandard
#define kMTCornerGestureZoneMin 0
#define kMTCornerGestureZoneMax 2
// 每侧三个层级，宽度按屏幕宽度的比例给出，再由 zone 档位整体缩放。
#define kMTCornerZoneLevelCount 3
#define kMTCornerZoneScaleStandard 1.0
#define kMTCornerZoneScaleWide 1.28
#define kMTCornerZoneScaleWidest 1.58
// 单侧最多占用屏幕宽度的一半，避免两侧区域在中线重叠；相邻层级至少差 8pt。
#define kMTCornerZoneMaxSpanRatio 0.48
#define kMTCornerZoneStepFloor 8.0

// 手势通道。system：SpringBoard 内挂钩系统自己的 Home 手势管线（默认，跨 App
// 一致，不与 App 的控件争抢触摸）。legacy：App 进程内自建 pan（0.5.6 及更早的
// 行为，保留作降级后路）。两者互不并存，避免一次上滑触发两次动作。
#define kMTCornerGestureSystemChannelKey @"cornergestureSystemChannel"
#define kMTCornerGestureSystemChannelDefault YES
#define kMTCornerGestureLegacyChannelKey @"cornergestureLegacyChannel"
#define kMTCornerGestureLegacyChannelDefault NO

typedef struct {
    double travel;   // 完成所需的最小向上位移（正值）
    double ratio;    // 上滑方向比：-dy >= |dx| × ratio 才视为向上
    double velocity; // 快速甩动兜底的速度门槛（pt/s，0 表示关闭）
} MTCornerGestureMetrics;

static inline NSArray<NSString *> *MTCornerGestureRegions(void) { return @[@"bottomleft", @"bottomright"]; }
static inline NSArray<NSString *> *MTCornerGestureKinds(void) { return @[@"up"]; }
static inline NSString *MTCornerGestureSlot(NSString *region) {
    if (![region isKindOfClass:NSString.class] || ![MTCornerGestureRegions() containsObject:region]) return nil;
    return [NSString stringWithFormat:@"%@.up", region];
}
// 一维模型下每个角落有三个层级（level 0 最贴边）：每个层级都是独立 slot，可以各
// 自绑定动作。level 0 沿用既有的 @"<region>.up"，其余为 @"<region>.up.zoneN"。
static inline NSString *MTCornerZoneSlot(NSString *region, NSInteger level) {
    NSString *base = MTCornerGestureSlot(region);
    if (!base || level < 0 || level >= kMTCornerZoneLevelCount) return nil;
    return level == 0 ? base : [NSString stringWithFormat:@"%@.zone%ld", base, (long)(level + 1)];
}
static inline NSArray<NSString *> *MTCornerZoneSlots(NSString *region) {
    NSMutableArray *slots = [NSMutableArray array];
    for (NSInteger level = 0; level < kMTCornerZoneLevelCount; level++) {
        NSString *slot = MTCornerZoneSlot(region, level);
        if (slot) [slots addObject:slot];
    }
    return slots;
}
static inline NSArray<NSString *> *MTCornerAllSlots(void) {
    NSMutableArray *slots = [NSMutableArray array];
    for (NSString *region in MTCornerGestureRegions()) [slots addObjectsFromArray:MTCornerZoneSlots(region)];
    return slots;
}
static inline BOOL MTCornerGestureSlotValid(id slot) {
    if (![slot isKindOfClass:NSString.class]) return NO;
    for (NSString *region in MTCornerGestureRegions())
        for (NSInteger level = 0; level < kMTCornerZoneLevelCount; level++)
            if ([MTCornerZoneSlot(region, level) isEqual:slot]) return YES;
    return NO;
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
// 设置页保留关闭角落的已选动作；运行端另行检查 enabled。
static inline NSString *MTCornerGestureConfiguredSelector(NSDictionary *preferences, NSString *slot) {
    NSDictionary *entry = MTCornerGestureBinding(preferences, slot);
    id selector = entry[@"selector"];
    return [selector isKindOfClass:NSString.class] && [(NSString *)selector length] ? selector : nil;
}
static inline NSString *MTCornerGestureSelector(NSDictionary *preferences, NSString *slot) {
    NSDictionary *entry = MTCornerGestureBinding(preferences, slot);
    // enabled 缺省视为开：与状态栏手势一致的宽松缺省，绑定即生效。
    id enabled = entry[@"enabled"];
    if ([enabled isKindOfClass:NSNumber.class] && ![enabled boolValue]) return nil;
    return MTCornerGestureConfiguredSelector(preferences, slot);
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
static inline double MTCornerGestureBottomInset(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:NSDictionary.class] ? preferences[kMTCornerGestureBottomInsetKey] : nil;
    return MTCornerGestureClamp([value isKindOfClass:NSNumber.class] ? [value doubleValue] : NAN,
        kMTCornerGestureBottomInsetMin, kMTCornerGestureBottomInsetMax, kMTCornerGestureBottomInsetDefault);
}
static inline BOOL MTCornerGestureSystemChannel(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:NSDictionary.class] ? preferences[kMTCornerGestureSystemChannelKey] : nil;
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : kMTCornerGestureSystemChannelDefault;
}
static inline BOOL MTCornerGestureLegacyChannel(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:NSDictionary.class] ? preferences[kMTCornerGestureLegacyChannelKey] : nil;
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : kMTCornerGestureLegacyChannelDefault;
}
// App 进程内的自建识别器（legacy 通道）是否允许安装。两条通道互斥：一次上滑只
// 应被一条通道消费。SpringBoard 上 system 通道开启时不装本地识别器，避免桌面上
// 同一次上滑既走系统管线又走 window pan，触发两次动作。
static inline BOOL MTCornerGestureLocalRecognizerAllowed(NSDictionary *preferences, NSString *host) {
    BOOL springBoard = [host isEqual:@"SpringBoard"];
    return springBoard ? !MTCornerGestureSystemChannel(preferences) : MTCornerGestureLegacyChannel(preferences);
}
static inline NSInteger MTCornerGestureZone(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:NSDictionary.class] ? preferences[kMTCornerGestureZoneKey] : nil;
    double zone = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : NAN;
    return (NSInteger)MTCornerGestureClamp(zone, kMTCornerGestureZoneMin, kMTCornerGestureZoneMax, kMTCornerGestureZoneDefault);
}
static inline NSInteger MTCornerGestureSensitivity(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:NSDictionary.class] ? preferences[kMTCornerGestureSensitivityKey] : nil;
    double level = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : NAN;
    return (NSInteger)MTCornerGestureClamp(level, kMTCornerGestureSensitivityMin, kMTCornerGestureSensitivityMax,
        kMTCornerGestureSensitivityDefault);
}
// 锚点纵坐标：上移量不得把锚点抬出窗口，短窗口（iPad 分屏/浮层）自动收敛到底边。
static inline double MTCornerGestureAnchorY(double height, double inset) {
    if (!isfinite(height) || height <= 0 || !isfinite(inset) || inset <= 0) return MAX(0, height);
    return MAX(0, height - MIN(inset, height));
}
static inline MTCornerGestureMetrics MTCornerGestureMetricsForLevel(NSInteger level) {
    MTCornerGestureMetrics metrics = { 36.0, 0.75, 0.0 };
    if (level == 1) { metrics.travel = 28.0; metrics.ratio = 0.60; metrics.velocity = 900.0; }
    else if (level >= 2) { metrics.travel = 20.0; metrics.ratio = 0.45; metrics.velocity = 650.0; }
    return metrics;
}
static inline MTCornerGestureMetrics MTCornerGestureMetricsForPreferences(NSDictionary *preferences) {
    return MTCornerGestureMetricsForLevel(MTCornerGestureSensitivity(preferences));
}

// 扇形命中判定：point 为窗口 bounds 坐标，扇形锚点位于「底角抬高 inset」处、
// 角平分线指向屏幕内侧 45°（上-内对角线），张角以角平分线对称分布。inset = 0
// 时锚点即几何底角、锚点以下一律拒绝，与早期行为一致；inset > 0 时锚点以下到
// 屏幕底边保留一条贴侧边的窄列作为起手容错带，让习惯从靠下的位置开始上滑的
// 手势仍然能被接住。
static inline NSString *MTCornerRegionAtPointWithInset(CGPoint point, CGSize size, double radius, double angle, double inset) {
    if (!isfinite(point.x) || !isfinite(point.y) || !isfinite(radius) || !isfinite(angle) ||
        !isfinite(size.width) || !isfinite(size.height) || radius <= 0 || angle <= 0 || angle > 180 ||
        size.width <= 0 || size.height <= 0 || point.x < 0 || point.x > size.width ||
        point.y < 0 || point.y > size.height) return nil;
    BOOL left = point.x <= size.width / 2;
    NSString *region = left ? @"bottomleft" : @"bottomright";
    double dx = left ? point.x : point.x - size.width;
    double dy = point.y - MTCornerGestureAnchorY(size.height, inset);
    if (dy > 0) {
        // 锚点以下到屏幕底边的起手容错带：只认贴侧边的窄列，宽度随半径缩放。
        return fabs(dx) <= radius * kMTCornerGestureLiftBandRatio ? region : nil;
    }
    double length = hypot(dx, dy);
    if (length > radius) return nil;
    // bisector = (±cos45°, -sin45°)；点积 >= |v|·cos(半张角) 即落在扇形内。
    double cosHalf = cos(MTCornerGestureClamp(angle, 0, 180, 90) * M_PI / 180 / 2);
    if (length == 0) return region;
    double bisectorX = left ? M_SQRT1_2 : -M_SQRT1_2;
    if (dx * bisectorX + dy * -M_SQRT1_2 < length * cosHalf) return nil;
    return region;
}
// 上滑方向：主导向上即可（允许对角上滑），与 Dock 上滑的 1.5:1 相比放宽到 0.75:1。
static inline BOOL MTCornerGestureUpward(double dx, double dy) {
    return isfinite(dx) && isfinite(dy) && dy < 0 && -dy >= fabs(dx) * 0.75;
}
static inline BOOL MTCornerGestureUpwardWithRatio(double dx, double dy, double ratio) {
    if (!isfinite(dx) || !isfinite(dy) || !isfinite(ratio) || ratio <= 0) return NO;
    return dy < 0 && -dy >= fabs(dx) * ratio;
}
// 仅凭两点位移无法区分「想触发手势」和「想滚动内容」，快速甩动是更强的意图信号：
// 位移达到门槛一半且抬手速度超过该档阈值时提前放行。
static inline BOOL MTCornerGestureCompletesWithMetrics(double dx, double dy, double velocity, MTCornerGestureMetrics metrics) {
    if (!MTCornerGestureUpwardWithRatio(dx, dy, metrics.ratio)) return NO;
    if (dy <= -metrics.travel) return YES;
    return metrics.velocity > 0 && isfinite(velocity) && velocity <= -metrics.velocity &&
        dy <= -metrics.travel * 0.5;
}
// ===== 一维命中模型（system 通道使用） =====
// 只看起点到屏幕侧边的横向距离：手指从底边任意高度起手都算，纵向交给 travel
// 门槛把关。相比扇形少一个维度的约束，命中率与 App 内底部的控件分布无关。
static inline NSArray<NSNumber *> *MTCornerZoneWidths(double width, NSInteger zone) {
    if (!isfinite(width) || width <= 0) return @[];
    double scale = zone == kMTCornerGestureZoneWide ? kMTCornerZoneScaleWide :
        (zone == kMTCornerGestureZoneWidest ? kMTCornerZoneScaleWidest : kMTCornerZoneScaleStandard);
    double ceiling = width * kMTCornerZoneMaxSpanRatio;
    NSMutableArray *widths = [NSMutableArray array];
    double previous = 0;
    for (NSInteger level = 0; level < kMTCornerZoneLevelCount; level++) {
        double span = MIN(width * (0.20 + 0.09 * level) * scale, ceiling);
        span = MAX(span, previous + kMTCornerZoneStepFloor);
        [widths addObject:@(span)];
        previous = span;
    }
    return widths;
}
static inline NSString *MTCornerZoneRegionAtX(double x, double width) {
    if (!isfinite(x) || !isfinite(width) || width <= 0 || x < 0 || x > width) return nil;
    return x <= width / 2 ? @"bottomleft" : @"bottomright";
}
static inline double MTCornerZoneEdgeDistance(double x, double width) {
    return x <= width / 2 ? x : width - x;
}
static inline NSInteger MTCornerZoneLevelForDistance(double distance, NSArray<NSNumber *> *widths) {
    for (NSInteger level = 0; level < (NSInteger)widths.count; level++)
        if (distance <= [widths[level] doubleValue]) return level;
    return NSNotFound;
}
// 命中层级未绑动作时顺延到更外侧的层级；都没有则本次上滑不归角落手势。
static inline NSInteger MTCornerZoneResolvedLevel(NSDictionary *preferences, NSString *region, NSInteger level) {
    if (!MTCornerGestureSlotValid(MTCornerZoneSlot(region, level))) return NSNotFound;
    for (NSInteger index = level; index < kMTCornerZoneLevelCount; index++)
        if (MTCornerGestureSelector(preferences, MTCornerZoneSlot(region, index))) return index;
    return NSNotFound;
}
static inline BOOL MTCornerZoneConfigured(NSDictionary *preferences) {
    for (NSString *region in MTCornerGestureRegions())
        for (NSInteger level = 0; level < kMTCornerZoneLevelCount; level++)
            if (MTCornerGestureConfiguredSelector(preferences, MTCornerZoneSlot(region, level))) return YES;
    return NO;
}

// 无上移量与标准档的等价入口：保持既有行为，供旧宿主测试与 Dock 复用。
static inline NSString *MTCornerRegionAtPoint(CGPoint point, CGSize size, double radius, double angle) {
    return MTCornerRegionAtPointWithInset(point, size, radius, angle, 0);
}
static inline BOOL MTCornerGestureCompletes(double dx, double dy) {
    return MTCornerGestureCompletesWithMetrics(dx, dy, 0, MTCornerGestureMetricsForLevel(0));
}
// Dock 手势互斥：命中已配置的角落扇形时，Dock 上滑放行给角落识别器。
static inline NSString *MTCornerGestureClaimedSlotWithInset(NSDictionary *preferences, CGSize size, CGPoint point, double inset) {
    if (!MTCornerGestureMasterEnabled(preferences)) return nil;
    NSString *region = MTCornerRegionAtPointWithInset(point, size, MTCornerGestureRadius(preferences),
        MTCornerGestureAngle(preferences), inset);
    NSString *slot = MTCornerGestureSlot(region);
    return MTCornerGestureSelector(preferences, slot) ? slot : nil;
}
static inline NSString *MTCornerGestureClaimedSlot(NSDictionary *preferences, CGSize size, CGPoint point) {
    return MTCornerGestureClaimedSlotWithInset(preferences, size, point, 0);
}
// 会话摘要：只收录「决定这一次触发是否成立」的字段——角落绑定、几何、灵敏度和
// 自定义动作支持状态。会话进行中的无关偏好变动（其它页面的编辑、剪切板历史等）
// 不再打断一次正在进行的滑动，而任何会让变异动作/区域的改动仍然使会话失效。
// 这不是放宽校验：broker 服务端依旧按 slot 重新解析并要求 selector 相等。
static inline NSString *MTCornerGestureSessionDigest(NSDictionary *preferences) {
    NSMutableString *digest = [NSMutableString string];
    for (NSString *slot in MTCornerAllSlots()) {
        NSString *selector = MTCornerGestureSelector(preferences, slot) ?: @"";
        [digest appendFormat:@"%@=%@;", slot, selector];
    }
    [digest appendFormat:@"inset=%0.1f;radius=%0.1f;angle=%0.1f;level=%ld;zone=%ld;",
        MTCornerGestureBottomInset(preferences), MTCornerGestureRadius(preferences),
        MTCornerGestureAngle(preferences), (long)MTCornerGestureSensitivity(preferences),
        (long)MTCornerGestureZone(preferences)];
    return digest;
}

// 窗口必须覆盖当前 Scene；仅被屏幕包含的小窗口不能拥有“屏幕角落”。
static inline BOOL MTCornerGestureWindowMatchesBounds(CGRect frame, CGRect bounds, CGRect sceneBounds) {
    if (CGRectIsEmpty(frame) || CGRectIsEmpty(bounds) || CGRectIsEmpty(sceneBounds) ||
        !isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
        !isfinite(frame.size.width) || !isfinite(frame.size.height) ||
        !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
        !isfinite(bounds.size.width) || !isfinite(bounds.size.height) ||
        !isfinite(sceneBounds.origin.x) || !isfinite(sceneBounds.origin.y) ||
        !isfinite(sceneBounds.size.width) || !isfinite(sceneBounds.size.height)) return NO;
    return fabs(CGRectGetMinX(frame) - CGRectGetMinX(sceneBounds)) <= 2.5 &&
        fabs(CGRectGetMinY(frame) - CGRectGetMinY(sceneBounds)) <= 2.5 &&
        fabs(frame.size.width - sceneBounds.size.width) <= 2.5 &&
        fabs(frame.size.height - sceneBounds.size.height) <= 2.5 &&
        CGPointEqualToPoint(bounds.origin, CGPointZero) &&
        fabs(bounds.size.width - sceneBounds.size.width) <= 2.5 &&
        fabs(bounds.size.height - sceneBounds.size.height) <= 2.5;
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
    for (NSString *slot in MTCornerAllSlots()) {
        id entry = [bindings[slot] isKindOfClass:NSDictionary.class] ? bindings[slot] : nil;
        if (![entry[@"selector"] isEqual:selector]) continue;
        NSMutableDictionary *updated = [entry mutableCopy];
        [updated removeObjectForKey:@"selector"];
        updated[@"enabled"] = @NO;
        bindings[slot] = updated;
    }
    preferences[kMTCornerGestureBindings] = bindings;
}
