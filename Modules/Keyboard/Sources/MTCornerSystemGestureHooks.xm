#import "MTCornerGestures.h"
#import "MTCornerGesturePolicy.h"
#import "MTStatusBarGesturePolicy.h"
#import "MTSystemOpenBroker.h"
#import "MTGlobalPanel.h"
#import "MTGlobalPanelPolicy.h"
#import "MTKeyboardPanelPreferences.h"
#import "MTPanelRegistry.h"
#import "common.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>

// 屏幕角落上滑的 SpringBoard 主通道。
//
// 设计来源：与 SquidGesturePro 2.7.6 同一思路——不在 App 进程里自建识别器，而是
// 挂钩 SpringBoard 自己的 Home 手势管线（grabberTongue* 系列回调），按「起点到
// 侧边的横向距离」决定是否接管这次手势。这样 App 的 Tab bar、按钮、滚动容器都
// 不在判定链路上，App 内与桌面的触发难度一致。
//
// 为什么不在源码里写类名：SquidGesture 的做法是运行时 objc_getClass(解密串)，
// 因为 SpringBoard 私有类的名字在 iOS 版本之间会变；本地反汇编里这些类名是加密
// 的，无法静态取得明文。与其猜名字再在真机上一版一版试，不如运行时按「方法签名
// 特征」自发现：遍历 witnesses 的类，挑出实现了目标 selector、参数个数与返回类型
// 都对得上的 SB/FB 类，再替换实现。猜错的表现是「不生效」，而不是崩溃。
//
// 三重保险：① 每个候选方法都校验 numberOfArguments 与返回类型；② 首次回调时校验
// 关键参数是否真的是 UIGestureRecognizer，不是就整体回滚还原；③ 所有回调体 @try
// 包裹，任何异常都不让它越过 SpringBoard。hook 不到目标类时静默降级，用户在设置
// 页可切回 legacy 通道。
static NSString *const MTCornerSystemLog = @"[MetisKeyboard][CornerSystem]";

typedef NS_ENUM(NSInteger, MTCornerSystemStage) {
    MTCornerSystemStageBegin = 0,
    MTCornerSystemStageUpdate,
    MTCornerSystemStageEnd,
    MTCornerSystemStageCancel,
};

@interface MTCornerSystemSession : NSObject
@property(nonatomic, copy) NSString *slot;
@property(nonatomic, copy) NSString *selector;
@property(nonatomic, assign) NSInteger level;
@property(nonatomic, assign) MTCornerGestureMetrics metrics;
@property(nonatomic, assign) BOOL haptic;
@property(nonatomic, assign) BOOL consumable;
@property(nonatomic, assign) BOOL dispatched;
@end
@implementation MTCornerSystemSession @end

// 原始实现按「类名|方法名」留存，供替换后回调正主；runtime hook 不用 trampoline，
// 保存的 IMP 指针指向替换前的机器码，直接调用不会重新走消息查找，因此也不会递归。
static NSMutableDictionary<NSString *, NSValue *> *MTCornerSystemOriginals;
// 会话以手势对象指针为 key：NSValue 不持有对象，不会在 SpringBoard 里延长系统手势的寿命。
static NSMutableDictionary<NSValue *, MTCornerSystemSession *> *MTCornerSystemSessions;
static BOOL MTCornerSystemOperational;
static NSInteger MTCornerSystemRejectStreak;

static void MTCornerSystemUninstall(void);

static NSString *MTCornerSystemKey(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%@|%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
}

// 沿 superclass 链找原始实现：替换若落在子类上，其obeisa Shak Eventsews`.
static IMP MTCornerSystemOriginalFor(id instance, SEL sel) {
    Class cls = object_getClass(instance);
    for (Class cursor = cls; cursor; cursor = class_getSuperclass(cursor)) {
        NSValue *value = MTCornerSystemOriginals[MTCornerSystemKey(cursor, sel)];
        if (value) return (IMP)value.pointerValue;
    }
    return NULL;
}

// ===== 可用性 =====
static BOOL MTCornerSystemAvailable(void) {
    if (!NSThread.isMainThread || !MTCornerSystemOperational) return NO;
    // SpringBoard 侧的守卫与 status bar 手势同源：锁屏与面板打开时不接受角落手势。
    if (![MTGlobalPanel deviceUnlocked] || [MTGlobalPanel.sharedInstance isVisible]) return NO;
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    if (!manager.preferencesAvailable) [manager reload];
    NSDictionary *preferences = manager.prefs;
    if (!manager.preferencesAvailable || !MTKeyboardPanelBool(preferences, kEnabledkey, YES) ||
        !MTCornerGestureMasterEnabled(preferences) || !MTCornerGestureSystemChannel(preferences)) return NO;
    return MTCornerZoneConfigured(preferences);
}

static BOOL MTCornerSystemSupportsSelector(NSDictionary *preferences, NSString *selector) {
    if (![selector length]) return NO;
    // 手势面板恒定启用：绑定到手势面板即视为有效动作（与状态栏/Dock 一致）。
    if (MTPanelAllowed(preferences, selector, MTPanelGestureKind)) return YES;
    for (id entry in [preferences[kLinkActionskey] isKindOfClass:NSArray.class] ? preferences[kLinkActionskey] : @[])
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector])
            return MTGlobalCustomActionSupported(entry);
    return NO;
}

// ===== 手势处理 =====
static CGSize MTCornerSystemScreenSize(void) {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGRect bounds = UIScreen.mainScreen.bounds;
    #pragma clang diagnostic pop
    return isfinite(bounds.size.width) && bounds.size.width > 0 ? bounds.size : CGSizeZero;
}

static void MTCornerSystemSessionEnd(NSValue *key) {
    if (key) [MTCornerSystemSessions removeObjectForKey:key];
}

// 触发：同一时刻只允许一次，重复的上滑到此为止。consumable 为真时同步取消系统的
// 这次手势，避免执行 Metis 动作的同时还把 App 收回主屏（Application Gestures 会
// 一并触发）——这一步依赖设备确认，日志会记录取消是否成功。
static void MTCornerSystemFire(NSValue *key, MTCornerSystemSession *session, UIGestureRecognizer *gesture) {
    if (!session || session.dispatched) return;
    session.dispatched = YES;
    NSString *slot = session.slot;
    NSString *selector = session.selector;
    NSLog(@"%@ trigger slot=%@ level=%ld", MTCornerSystemLog, slot, (long)session.level);
    if (session.haptic) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
    }
    if (session.consumable && [gesture isKindOfClass:UIGestureRecognizer.class]) {
        @try {
            gesture.enabled = NO;
            gesture.enabled = YES;
            NSLog(@"%@ consumed system gesture state=%ld", MTCornerSystemLog, (long)gesture.state);
        } @catch (NSException *exception) {
            NSLog(@"%@ consume failed %@", MTCornerSystemLog, exception.reason);
        }
    }
    MTCornerSystemSessionEnd(key);
    MTRequestCornerGesture(slot, selector, ^(MTSystemOpenResult result) {
        NSLog(@"%@ result slot=%@ status=%llu", MTCornerSystemLog, slot, (unsigned long long)result);
    });
}

static void MTCornerSystemHandle(id gestureObject, MTCornerSystemStage stage, double distance) {
    if (!NSThread.isMainThread) return;
    @try {
        if (![gestureObject isKindOfClass:UIGestureRecognizer.class]) {
            // 自发现猜错了方法：趁早回滚，避免长期留在错误的钩子上。
            if (++MTCornerSystemRejectStreak > 8) {
                NSLog(@"%@ sanity check failed %ld times, uninstalling", MTCornerSystemLog, (long)MTCornerSystemRejectStreak);
                MTCornerSystemUninstall();
            }
            return;
        }
        MTCornerSystemRejectStreak = 0;
        UIGestureRecognizer *gesture = (UIGestureRecognizer *)gestureObject;
        NSValue *key = [NSValue valueWithPointer:(__bridge const void *)gesture];
        MTCornerSystemSession *session = MTCornerSystemSessions[key];
        if (stage == MTCornerSystemStageCancel || stage == MTCornerSystemStageEnd) {
            MTCornerSystemSessionEnd(key);
            return;
        }
        if (stage == MTCornerSystemStageBegin) {
            if (!MTCornerSystemAvailable()) return;
            NSDictionary *preferences = MTPrefsManager.sharedInstance.prefs;
            CGSize size = MTCornerSystemScreenSize();
            CGPoint origin = [gesture locationInView:nil];
            NSString *region = MTCornerZoneRegionAtX(origin.x, size.width);
            NSArray<NSNumber *> *widths = MTCornerZoneWidths(size.width, MTCornerGestureZone(preferences));
            NSInteger level = region ? MTCornerZoneLevelForDistance(MTCornerZoneEdgeDistance(origin.x, size.width), widths) : NSNotFound;
            if (level == NSNotFound) return;
            NSInteger resolved = MTCornerZoneResolvedLevel(preferences, region, level);
            if (resolved == NSNotFound) return;
            NSString *slot = MTCornerZoneSlot(region, resolved);
            NSString *selector = MTCornerGestureSelector(preferences, slot);
            if (!selector || !MTCornerSystemSupportsSelector(preferences, selector)) return;
            MTCornerSystemSession *created = [MTCornerSystemSession new];
            created.slot = slot;
            created.selector = selector;
            created.level = resolved;
            created.metrics = MTCornerGestureMetricsForPreferences(preferences);
            created.haptic = MTKeyboardPanelBool(preferences, kEnabledHaptickey, YES);
            // 触发的同时取消系统的这次手势，否则 Metis 动作会与「回到主屏」一起发生。
            created.consumable = YES;
            MTCornerSystemSessions[key] = created;
            NSLog(@"%@ start region=%@ level=%ld -> %@ x=%.0f distance0=%.1f",
                MTCornerSystemLog, region, (long)resolved, slot, origin.x, distance);
            return;
        }
        if (stage != MTCornerSystemStageUpdate || !session || session.dispatched) return;
        if (distance >= session.metrics.travel) MTCornerSystemFire(key, session, gesture);
    } @catch (NSException *exception) {
        NSLog(@"%@ exception stage=%ld %@", MTCornerSystemLog, (long)stage, exception.reason);
    }
}

// ===== 安装 =====
// 只认 SpringBoard/FrontBoard 的类，按返回类型与参数个数挑出目标实现。
// 同一个 IMP 可能来自超类，去重后只替一次，避免重复计数。
static NSArray<NSValue *> *MTCornerSystemClassesForSelector(SEL sel, char returnCode, unsigned argumentCount) {
    NSMutableArray<NSValue *> *result = [NSMutableArray array];
    NSMutableSet<NSValue *> *seen = [NSMutableSet set];
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int index = 0; index < count; index++) {
        Class cls = classes[index];
        NSString *name = NSStringFromClass(cls);
        if (![name hasPrefix:@"SB"] && ![name hasPrefix:@"FB"]) continue;
        Method method = class_getInstanceMethod(cls, sel);
        if (!method || method_getNumberOfArguments(method) != argumentCount) continue;
        char returnType[16] = { 0 };
        method_getReturnType(method, returnType, sizeof(returnType));
        if (returnType[0] != returnCode) continue;
        IMP implementation = method_getImplementation(method);
        NSValue *unique = [NSValue valueWithPointer:(const void *)implementation];
        if ([seen containsObject:unique]) continue;
        [seen addObject:unique];
        [result addObject:[NSValue valueWithPointer:(__bridge const void *)cls]];
    }
    free(classes);
    return result;
}

static BOOL MTCornerSystemInstall(Class cls, SEL sel, IMP replacement) {
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return NO;
    IMP original = method_getImplementation(method);
    if (!original || original == replacement) return NO;
    const char *types = method_getTypeEncoding(method);
    IMP previous = class_replaceMethod(cls, sel, replacement, types);
    MTCornerSystemOriginals[MTCornerSystemKey(cls, sel)] = [NSValue valueWithPointer:(const void *)(previous ?: original)];
    NSLog(@"%@ hooked %@ %@", MTCornerSystemLog, NSStringFromClass(cls), NSStringFromSelector(sel));
    return YES;
}

static void MTCornerSystemUninstall(void) {
    if (!MTCornerSystemOperational) return;
    MTCornerSystemOperational = NO;
    [MTCornerSystemSessions removeAllObjects];
    [MTCornerSystemOriginals enumerateKeysAndObjectsUsingBlock:^(NSString *key, __unused NSValue *value, __unused BOOL *stop) {
        NSArray<NSString *> *parts = [key componentsSeparatedByString:@"|"];
        if (parts.count != 2) return;
        Class cls = NSClassFromString(parts[0]);
        SEL sel = NSSelectorFromString(parts[1]);
        Method current = cls ? class_getInstanceMethod(cls, sel) : NULL;
        if (current) class_replaceMethod(cls, sel, (IMP)value.pointerValue, method_getTypeEncoding(current));
    }];
    NSLog(@"%@ uninstalled", MTCornerSystemLog);
}

static id MTCornerSystemTongueBlock(MTCornerSystemStage stage) {
    return ^void(id selfRef, id tongue, double distance, CGPoint velocity, id gesture) {
        SEL sel = NULL;
        switch (stage) {
            case MTCornerSystemStageBegin: sel = @selector(grabberTongueBeganPulling:withDistance:andVelocity:andGesture:); break;
            case MTCornerSystemStageUpdate: sel = @selector(grabberTongueUpdatedPulling:withDistance:andVelocity:andGesture:); break;
            case MTCornerSystemStageEnd: sel = @selector(grabberTongueEndedPulling:withDistance:andVelocity:andGesture:); break;
            case MTCornerSystemStageCancel: sel = @selector(grabberTongueCanceledPulling:withDistance:andVelocity:andGesture:); break;
        }
        void (*original)(id, SEL, id, double, CGPoint, id) = (void (*)(id, SEL, id, double, CGPoint, id))MTCornerSystemOriginalFor(selfRef, sel);
        if (original) original(selfRef, sel, tongue, distance, velocity, gesture);
        MTCornerSystemHandle(gesture, stage, distance);
    };
}

static void MTInstallCornerSystemGestures(void) {
    if (!NSThread.isMainThread || MTCornerSystemOperational) return;
    if (![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return;
    NSDictionary *preferences = MTPrefsManager.sharedInstance.prefs;
    if (!MTCornerGestureSystemChannel(preferences)) {
        NSLog(@"%@ system channel disabled", MTCornerSystemLog);
        return;
    }
    MTCornerSystemOriginals = [NSMutableDictionary dictionary];
    MTCornerSystemSessions = [NSMutableDictionary dictionary];
    static const struct { const char *name; MTCornerSystemStage stage; } stages[] = {
        { "grabberTongueBeganPulling:withDistance:andVelocity:andGesture:", MTCornerSystemStageBegin },
        { "grabberTongueUpdatedPulling:withDistance:andVelocity:andGesture:", MTCornerSystemStageUpdate },
        { "grabberTongueEndedPulling:withDistance:andVelocity:andGesture:", MTCornerSystemStageEnd },
        { "grabberTongueCanceledPulling:withDistance:andVelocity:andGesture:", MTCornerSystemStageCancel },
    };
    NSUInteger installed = 0;
    for (size_t index = 0; index < sizeof(stages) / sizeof(stages[0]); index++) {
        SEL sel = sel_registerName(stages[index].name);
        IMP replacement = imp_implementationWithBlock(MTCornerSystemTongueBlock(stages[index].stage));
        for (NSValue *entry in MTCornerSystemClassesForSelector(sel, 'v', 6))
            if (MTCornerSystemInstall((Class)entry.pointerValue, sel, replacement)) installed++;
    }
    if (!installed) {
        NSLog(@"%@ no grabberTongue target found; falling back is up to the legacy switch", MTCornerSystemLog);
        return;
    }
    MTCornerSystemOperational = YES;
    NSLog(@"%@ installed %lu hooks (zone=%ld)", MTCornerSystemLog, (unsigned long)installed,
        (long)MTCornerGestureZone(preferences));
}

void MTStartCornerSystemGestures(void) {
    if (!MTStatusBarHostAllowed(NSProcessInfo.processInfo.processName, NSBundle.mainBundle.bundleURL.pathExtension)) return;
    void (^start)(void) = ^{
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            @try {
            // SpringBoard 自己的类库可能尚未加载，推迟到主线程空闲后再找一次，
            // 并在偏好刷新（通道开关切换）时重试。
            MTInstallCornerSystemGestures();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try { if (!MTCornerSystemOperational) MTInstallCornerSystemGestures(); }
                @catch (NSException *exception) { NSLog(@"%@ retry failed %@", MTCornerSystemLog, exception.reason); }
            });
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *note) {
                    [MTPrefsManager.sharedInstance reload];
                    if (!MTCornerSystemOperational) MTInstallCornerSystemGestures();
                    else if (!MTCornerGestureSystemChannel(MTPrefsManager.sharedInstance.prefs)) MTCornerSystemUninstall();
                }];
            for (NSString *name in @[kPrefsChangedIdentifier, @"com.apple.springboard.lockstate"]) {
                int token = NOTIFY_TOKEN_INVALID;
                notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(__unused int delivered) {
                    [MTPrefsManager.sharedInstance reload];
                    [MTCornerSystemSessions removeAllObjects];
                });
            }
            } @catch (NSException *exception) {
                NSLog(@"%@ install failed %@", MTCornerSystemLog, exception.reason);
                MTCornerSystemUninstall();
            }
        });
    };
    if (NSThread.isMainThread) start();
    else dispatch_async(dispatch_get_main_queue(), start);
}
