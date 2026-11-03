#import "MTChargingRuntime.h"
#import "MTChargingCardView.h"
#import "MTChargingSnapshot.h"
#import "MTChargingPreferences.h"
#import "MTLog.h"
#import <IOKit/IOKitLib.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <notify.h>
#include <math.h>
#include <string.h>

static NSDictionary *MTChargingReadBattery(void) {
    // Probe battery services only. Registry reads happen only on the serial
    // sampling queue, never during SpringBoard's layout or lock transition.
    for (NSString *name in @[@"AppleSmartBattery", @"AppleARMPMUPowerSource", @"IOPMPowerSource"]) {
        io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching(name.UTF8String));
        if (!service) continue;
        CFMutableDictionaryRef properties = NULL;
        kern_return_t result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0);
        IOObjectRelease(service);
        NSDictionary *values = CFBridgingRelease(properties);
        if (result == KERN_SUCCESS && [values isKindOfClass:NSDictionary.class] &&
            (values[@"ExternalConnected"] || values[@"CurrentCapacity"] || values[@"Voltage"])) return values;
    }
    return @{};
}

static BOOL MTChargingDeviceLocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    SEL shared = NSSelectorFromString(@"sharedInstance"), locked = NSSelectorFromString(@"isUILocked");
    NSMethodSignature *factory = [cls methodSignatureForSelector:shared];
    if (factory.numberOfArguments != 2 || strcmp(factory.methodReturnType, "@")) return NO;
    @try {
        id manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        NSMethodSignature *signature = [manager methodSignatureForSelector:locked];
        if (signature.numberOfArguments != 2 ||
            (strcmp(signature.methodReturnType, "B") && strcmp(signature.methodReturnType, "c"))) return NO;
        return ((BOOL (*)(id, SEL))objc_msgSend)(manager, locked);
    } @catch (__unused NSException *exception) { return NO; }
}

static BOOL MTChargingBool(id object, NSString *name, BOOL fallback) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 ||
        (strcmp(signature.methodReturnType, "B") && strcmp(signature.methodReturnType, "c"))) return fallback;
    @try { return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return fallback; }
}

static NSString *MTChargeViewChain(UIView *view) {
    // Bounded class-name chain: enough to tell which cover sheet container the
    // card used to land in, short enough to stay on one syslog line.
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UIView *node = view; node && names.count < 6; node = node.superview)
        [names addObject:NSStringFromClass(node.class)];
    return [names componentsJoinedByString:@"<"];
}

// Only actual notification cells/content count. NCNotificationListView is a
// layout container rather than notification content. 1.5.7 device logs show
// it winning the scan and the card being removed on every sampling tick.
static BOOL MTChargingNotificationContentClass(NSString *name) {
    static NSSet<NSString *> *classes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ classes = [NSSet setWithArray:@[@"NCNotificationListCell",
        @"NCNotificationShortLookView", @"NCNotificationLongLookView",
        @"NotificationShortLookView", @"NotificationLongLookView"]]; });
    return [classes containsObject:name];
}
typedef enum {
    MTChargingYieldNone = 0,
    MTChargingYieldNotifications,
    MTChargingYieldPasscode,
} MTChargingYieldReason;

typedef struct {
    MTChargingYieldReason reason;
    NSUInteger passcodeHits, notificationHits;
    CGRect notificationFrame; // window coords of the first visible stack view; CGRectNull if none
} MTChargingYieldResult;

static void MTChargingScanNode(UIView *node, NSUInteger depth, NSUInteger *budget, UIView *windowRoot, BOOL inHostTree,
    UIView *hostView, MTChargingYieldResult *result, UIView **passcodeHit, UIView **notificationHit) {
    if (*budget == 0 || depth > 16) return;
    if (node.hidden || node.alpha < 0.01f) return; // an invisible parent hides its whole subtree
    if (result->passcodeHits && !CGRectIsNull(result->notificationFrame)) return; // both already found
    (*budget)--;
    if (node == hostView) inHostTree = YES;
    BOOL passcodeMatch = NO, notificationMatch = NO;
    for (Class cls = node.class; cls && !(passcodeMatch && notificationMatch); cls = class_getSuperclass(cls)) {
        NSString *name = NSStringFromClass(cls);
        if (!passcodeMatch && [name containsString:@"Passcode"]) passcodeMatch = YES;
        if (!notificationMatch && MTChargingNotificationContentClass(name)) notificationMatch = YES;
    }
    if (passcodeMatch || notificationMatch) {
        CGRect frame = [node convertRect:node.bounds toView:windowRoot];
        if (frame.size.width > 8 && frame.size.height > 8 && CGRectIntersectsRect(frame, windowRoot.bounds)) {
            if (passcodeMatch) {
                if (result->passcodeHits == 0) *passcodeHit = node;
                result->passcodeHits++;
            }
            // Notification content only counts inside the cover sheet subtree,
            // so notification-named views parked elsewhere in the window
            // (home screen layers, tweak panels) can never trigger it. The
            // frame tracked is the topmost hit so the card clears the stack.
            if (notificationMatch && inHostTree) {
                if (CGRectIsNull(result->notificationFrame) ||
                    CGRectGetMinY(frame) < CGRectGetMinY(result->notificationFrame)) {
                    *notificationHit = node; result->notificationFrame = frame;
                }
                result->notificationHits++;
            }
        }
    }
    for (UIView *child in node.subviews)
        MTChargingScanNode(child, depth + 1, budget, windowRoot, inHostTree, hostView, result, passcodeHit, notificationHit);
}

static MTChargingYieldResult MTChargingCoverSheetYield(UIViewController *host) {
    MTChargingYieldResult result = {MTChargingYieldNone, 0, 0, CGRectNull};
    UIView *hostView = host.viewIfLoaded;
    UIView *window = hostView.window;
    if (!window) return result;
    UIView *passcodeHit = nil, *notificationHit = nil;
    NSUInteger budget = 1200;
    for (UIView *child in window.subviews)
        MTChargingScanNode(child, 1, &budget, window, NO, hostView, &result, &passcodeHit, &notificationHit);
    result.reason = result.passcodeHits ? MTChargingYieldPasscode :
        (result.notificationHits ? MTChargingYieldNotifications : MTChargingYieldNone);
    // The first evaluation always logs (a false positive that exists from
    // launch never produces a flip), later ones only on state flips.
    static MTChargingYieldReason lastLogged = -1;
    static BOOL loggedOnce = NO;
    if (!loggedOnce) {
        loggedOnce = YES;
        MTLogInfo(@"charging", @"state=yield-init reason=%ld notif=%lu pass=%lu chain=%@", (long)result.reason,
            (unsigned long)result.notificationHits, (unsigned long)result.passcodeHits,
            notificationHit ? MTChargeViewChain(notificationHit) : (passcodeHit ? MTChargeViewChain(passcodeHit) : @"-"));
    } else if (result.reason != lastLogged) {
        if (result.reason == MTChargingYieldNone) MTLogInfo(@"charging", @"state=yield-clear");
        else MTLogInfo(@"charging", @"state=yield reason=%ld chain=%@", (long)result.reason,
            MTChargeViewChain(result.reason == MTChargingYieldPasscode ? passcodeHit : notificationHit));
    }
    lastLogged = result.reason;
    return result;
}

@interface MTChargingRuntime : NSObject
@property(nonatomic, weak) UIViewController *host;
@property(nonatomic, weak) UIViewController *passcodeController;
@property(nonatomic, strong) MTChargingCardView *card;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) id gateObserver;
@property(nonatomic, strong) dispatch_queue_t samplingQueue;
@property(nonatomic) BOOL appeared;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL displayOn;
@property(nonatomic) BOOL sampling;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSTimeInterval lastProbeTime;
@property(nonatomic, strong) MTChargingEstimator *estimator;
@property(nonatomic) NSUInteger etaSource;
@property(nonatomic) NSInteger etaMinutes;
@property(nonatomic) BOOL etaLoggedOnce;
@property(nonatomic) NSUInteger configurationGeneration;
@property(nonatomic) BOOL sessionProbePending;
@property(nonatomic) int displayToken;
@property(nonatomic) int lockToken;
+ (instancetype)shared;
- (void)refresh;
- (void)layout;
- (void)stop;
- (void)sampleBattery;
@end

@implementation MTChargingRuntime
+ (instancetype)shared {
    static MTChargingRuntime *runtime;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ runtime = [self new]; });
    return runtime;
}
- (instancetype)init {
    if ((self = [super init])) {
        _samplingQueue = dispatch_queue_create("com.lindo.metis.charging", DISPATCH_QUEUE_SERIAL);
        _estimator = [MTChargingEstimator new];
        _displayOn = YES; _displayToken = -1; _lockToken = -1;
        __weak typeof(self) weakSelf = self;
        _gateObserver = [MTModuleGate addObserver:dispatch_get_main_queue() block:^{ [weakSelf reloadConfiguration]; }];
        if (notify_register_dispatch("com.apple.iokit.hid.displayStatus", &_displayToken, dispatch_get_main_queue(), ^(int token) {
            uint64_t state = 0;
            if (notify_get_state(token, &state) == NOTIFY_STATUS_OK) weakSelf.displayOn = state != 0;
            [weakSelf refresh];
        }) == NOTIFY_STATUS_OK) {
            uint64_t state = 0;
            if (notify_get_state(_displayToken, &state) == NOTIFY_STATUS_OK) _displayOn = state != 0;
        } else _displayToken = -1;
        if (notify_register_dispatch("com.apple.springboard.lockstate", &_lockToken, dispatch_get_main_queue(), ^(int token) {
            [weakSelf refresh];
        }) != NOTIFY_STATUS_OK) _lockToken = -1;
        [self reloadConfiguration];
    }
    return self;
}
- (void)reloadConfiguration {
    CFPreferencesAppSynchronize((__bridge CFStringRef)MTConfigDomain);
    BOOL enabled = [MTModuleGate globalEnabled] && MTChargingDetailsEnabled();
    if (enabled != self.enabled) {
        self.configurationGeneration++;
        self.enabled = enabled;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center removeObserver:self name:UIDeviceBatteryStateDidChangeNotification object:nil];
        [center removeObserver:self name:UIDeviceBatteryLevelDidChangeNotification object:nil];
        if (enabled) {
            // Monitoring is process-wide. Do not turn it off beneath another
            // SpringBoard component when this feature is disabled.
            UIDevice.currentDevice.batteryMonitoringEnabled = YES;
            for (NSString *name in @[UIDeviceBatteryStateDidChangeNotification, UIDeviceBatteryLevelDidChangeNotification])
                [center addObserver:self selector:@selector(batteryChanged:) name:name object:nil];
        }
        MTLogInfo(@"charging", @"state=configuration enabled=%d", enabled);
        self.lastProbeTime = 0;
        if (enabled) [self sampleBattery];
        else [self stop];
        return;
    }
    self.lastProbeTime = 0;
    [self refresh];
}
- (void)batteryChanged:(NSNotification *)notification {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self batteryChanged:notification]; });
        return;
    }
    self.lastProbeTime = 0;
    [self sampleBattery];
}
- (BOOL)canShow {
    UIView *view = self.host.viewIfLoaded;
    return self.enabled && self.appeared && self.displayOn && !self.passcodeController && view.window && !view.hidden &&
        view.bounds.size.height > view.bounds.size.width && MTChargingDeviceLocked() &&
        MTChargingBool(self.host, @"_isMainPageShowing", NO) &&
        !MTChargingBool(self.host, @"_isPageContentHidden", YES) &&
        !MTChargingBool(self.host, @"hasContentAboveCoverSheet", YES) &&
        !MTChargingBool(self.host, @"_isPresentingPosterSwitcher", YES);
}
- (void)stop {
    self.generation++;
    [self.timer invalidate]; self.timer = nil;
    [self.card removeFromSuperview]; self.card = nil;
    [self.estimator reset];
}
- (void)ensureTimer {
    if (self.timer) return;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
    self.timer.tolerance = 0.15;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)refresh {
    if (![self canShow]) { [self stop]; return; }
    // Passcode keypad still takes the card down (polling stays alive so the
    // card returns once the keypad is gone). Notifications no longer hide the
    // card here — layout repositions it above the stack instead.
    if (MTChargingCoverSheetYield(self.host).reason == MTChargingYieldPasscode) {
        [self.card removeFromSuperview]; self.card = nil;
        [self ensureTimer];
        return;
    }
    if (self.sampling) return;
    NSTimeInterval probeTime = NSProcessInfo.processInfo.systemUptime;
    if (probeTime - self.lastProbeTime < 0.8) return;
    self.lastProbeTime = probeTime;
    [self sampleBattery];
}
- (void)sampleBattery {
    if (!self.enabled) return;
    // Battery events probe once even while the card is hidden so connection
    // boundaries are observed. No hidden-screen polling timer is introduced.
    if (self.sampling) { self.sessionProbePending = YES; return; }
    self.sampling = YES;
    NSUInteger generation = self.generation;
    NSUInteger configuration = self.configurationGeneration;
    UIDeviceBatteryState state = UIDevice.currentDevice.batteryState;
    double level = UIDevice.currentDevice.batteryLevel;
    BOOL charging = state == UIDeviceBatteryStateCharging;
    BOOL connected = charging || state == UIDeviceBatteryStateFull;
    dispatch_async(self.samplingQueue, ^{
        MTChargingSnapshot *snapshot = [MTChargingSnapshot snapshotWithProperties:MTChargingReadBattery()
            fallbackLevel:level connected:connected charging:charging];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.sampling = NO;
            BOOL pending = self.sessionProbePending;
            self.sessionProbePending = NO;
            if (pending && self.enabled) dispatch_async(dispatch_get_main_queue(), ^{ [self sampleBattery]; });
            if (!self.enabled || configuration != self.configurationGeneration) return;
            if (generation != self.generation || ![self canShow]) return;
            if (MTChargingCoverSheetYield(self.host).reason == MTChargingYieldPasscode) {
                [self.card removeFromSuperview]; self.card = nil;
                [self ensureTimer];
                return;
            }
            if (!snapshot.connected) { [self stop]; return; }
            [self.estimator updateSnapshot:snapshot atTime:NSProcessInfo.processInfo.systemUptime];
            // 首评必打，其后仅来源或分钟数变化时打：真机定位估时来源与
            // 兜底链路（source: 0 无 1 系统 2 滑动窗 3 瞬时估 4 保持上次）。
            NSUInteger etaSource = snapshot.etaSource;
            NSInteger etaMinutes = snapshot.minutesToFull;
            if (!self.etaLoggedOnce || etaSource != self.etaSource || etaMinutes != self.etaMinutes) {
                MTLogInfo(@"charging", @"state=eta-estimate source=%lu minutes=%ld remaining=%.0f ma=%.0f level=%.2f",
                    (unsigned long)etaSource, (long)etaMinutes, snapshot.remainingMilliampHours,
                    snapshot.amps * 1000.0, snapshot.level);
                self.etaLoggedOnce = YES;
                self.etaSource = etaSource;
                self.etaMinutes = etaMinutes;
            }
            [self ensureTimer];
            if (!self.card) {
                self.card = [[MTChargingCardView alloc] initWithFrame:CGRectZero];
                // Depth-effect lock screens composite the wallpaper subject above
                // the whole cover sheet stack, so anything inserted inside
                // CSCoverSheetViewController gets cut by the subject outline.
                // The window is the lowest level guaranteed to be above it; the
                // card ignores touches, so system controls stay reachable, and
                // no new UIWindow or list-inset changes are introduced.
                UIView *anchor = self.host.view.window ?: self.host.view;
                [anchor addSubview:self.card];
                MTLogInfo(@"charging", @"state=card-attached anchor=%@ chain=%@ telemetry=%d",
                    NSStringFromClass(anchor.class), MTChargeViewChain(self.host.view), isfinite(snapshot.watts));
            }
            [self layout];
            [self.card updateSnapshot:snapshot];
        });
    });
}
- (void)layout {
    UIView *host = self.host.viewIfLoaded;
    if (!host || !self.card) return;
    if (![self canShow]) { [self stop]; return; }
    MTChargingYieldResult yield = MTChargingCoverSheetYield(self.host);
    if (yield.reason == MTChargingYieldPasscode) {
        [self.card removeFromSuperview]; self.card = nil;
        return;
    }
    CGFloat width = MIN(host.bounds.size.width - 32, 430);
    CGFloat height = width * MTChargingCardDesignHeight / MTChargingCardDesignWidth;
    CGFloat bottom = host.bounds.size.height - host.safeAreaInsets.bottom - 86;
    if (yield.reason == MTChargingYieldNotifications && !CGRectIsNull(yield.notificationFrame)) {
        // Reposition above the notification stack instead of hiding. If the
        // stack leaves no room for the card, hide but keep polling (refresh's
        // passcode branch owns ensureTimer, so keep the same contract here by
        // relying on the sampling path to re-ensure the timer).
        CGRect stackInHost = host.window ? [host convertRect:yield.notificationFrame fromView:host.window]
                                         : yield.notificationFrame;
        CGFloat movedBottom = CGRectGetMinY(stackInHost) - 12;
        if (movedBottom - height >= host.bounds.size.height * 0.35) bottom = movedBottom;
        else { [self.card removeFromSuperview]; self.card = nil; return; }
    }
    if (width < 250 || bottom - height < host.bounds.size.height * 0.35) { [self stop]; return; }
    CGRect rect = CGRectMake((host.bounds.size.width - width) / 2, bottom - height, width, height);
    UIView *parent = self.card.superview;
    self.card.frame = parent && parent != host ? [host convertRect:rect toView:parent] : rect;
    // SpringBoard re-adds views to the window during lock transitions; keep the
    // card on top or the subject layer covers it again until the next reload.
    if (parent && parent.subviews.lastObject != self.card) [parent bringSubviewToFront:self.card];
}
- (void)dealloc {
    [_timer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [MTModuleGate removeObserver:_gateObserver];
    if (_displayToken >= 0) notify_cancel(_displayToken);
    if (_lockToken >= 0) notify_cancel(_lockToken);
}
@end

static void (*MTChargingOriginalAppear)(UIViewController *, SEL, BOOL);
static void (*MTChargingOriginalDisappear)(UIViewController *, SEL, BOOL);
static void (*MTChargingOriginalLayout)(UIViewController *, SEL);
static void (*MTChargingOriginalScreenOff)(UIViewController *, SEL, BOOL);
static void (*MTChargingOriginalContentAbove)(UIViewController *, SEL, BOOL);
static void (*MTChargingOriginalPageIndex)(UIViewController *, SEL, unsigned long long);
static void (*MTChargingOriginalPasscodeAppear)(UIViewController *, SEL, BOOL);
static void (*MTChargingOriginalPasscodeDisappear)(UIViewController *, SEL, BOOL);
static void MTChargingPasscodeAppear(UIViewController *controller, SEL selector, BOOL animated) {
    // Revoke pending samples BEFORE UIKit begins presenting the keypad. The
    // keypad may be in a different window; a cover-sheet subtree scan is late.
    MTChargingRuntime *runtime = MTChargingRuntime.shared;
    runtime.passcodeController = controller;
    [runtime stop];
    MTChargingOriginalPasscodeAppear(controller, selector, animated);
}
static void MTChargingPasscodeDisappear(UIViewController *controller, SEL selector, BOOL animated) {
    MTChargingOriginalPasscodeDisappear(controller, selector, animated);
    MTChargingRuntime *runtime = MTChargingRuntime.shared;
    if (runtime.passcodeController == controller) {
        runtime.passcodeController = nil;
        runtime.lastProbeTime = 0;
        [runtime refresh];
    }
}
static void MTChargingRefreshHost(UIViewController *controller) {
    MTChargingRuntime *runtime = MTChargingRuntime.shared;
    if (runtime.host == controller) { runtime.lastProbeTime = 0; [runtime refresh]; }
}
static void MTChargingScreenOff(UIViewController *controller, SEL selector, BOOL off) {
    MTChargingOriginalScreenOff(controller, selector, off);
    MTChargingRuntime.shared.displayOn = !off;
    MTChargingRefreshHost(controller);
}
static void MTChargingContentAbove(UIViewController *controller, SEL selector, BOOL above) {
    MTChargingOriginalContentAbove(controller, selector, above);
    MTChargingRefreshHost(controller);
}
static void MTChargingPageIndex(UIViewController *controller, SEL selector, unsigned long long index) {
    MTChargingOriginalPageIndex(controller, selector, index);
    MTChargingRefreshHost(controller);
}
static void MTChargingAppear(UIViewController *controller, SEL selector, BOOL animated) {
    MTChargingOriginalAppear(controller, selector, animated);
    MTChargingRuntime *runtime = MTChargingRuntime.shared;
    runtime.host = controller; runtime.appeared = YES; [runtime refresh];
}
static void MTChargingDisappear(UIViewController *controller, SEL selector, BOOL animated) {
    MTChargingRuntime *runtime = MTChargingRuntime.shared;
    if (runtime.host == controller) { runtime.appeared = NO; [runtime stop]; runtime.host = nil; }
    MTChargingOriginalDisappear(controller, selector, animated);
}
static void MTChargingLayout(UIViewController *controller, SEL selector) {
    MTChargingOriginalLayout(controller, selector);
    MTChargingRuntime *runtime = MTChargingRuntime.shared;
    if (runtime.host == controller) {
        [runtime layout];
        if (runtime.enabled && !runtime.timer) [runtime refresh];
    }
}
static BOOL MTChargingMethodSupported(Class cls, SEL selector, BOOL animated) {
    NSMethodSignature *signature = [cls instanceMethodSignatureForSelector:selector];
    if (!signature || strcmp(signature.methodReturnType, "v") || signature.numberOfArguments != (animated ? 3u : 2u)) return NO;
    if (!animated) return YES;
    const char *type = [signature getArgumentTypeAtIndex:2];
    return !strcmp(type, "B") || !strcmp(type, "c");
}
void MTChargingInstall(void) {
    Class passcode = NSClassFromString(@"CSPasscodeViewController");
    SEL passcodeAppear = @selector(viewWillAppear:), passcodeDisappear = @selector(viewDidDisappear:);
    if (MTChargingMethodSupported(passcode, passcodeAppear, YES) &&
        MTChargingMethodSupported(passcode, passcodeDisappear, YES)) {
        MSHookMessageEx(passcode, passcodeAppear, (IMP)MTChargingPasscodeAppear, (IMP *)&MTChargingOriginalPasscodeAppear);
        MSHookMessageEx(passcode, passcodeDisappear, (IMP)MTChargingPasscodeDisappear, (IMP *)&MTChargingOriginalPasscodeDisappear);
    } else MTLogWarn(@"charging", @"state=passcode-hooks-unavailable");
    Class cls = NSClassFromString(@"CSCoverSheetViewController");
    SEL appear = @selector(viewDidAppear:), disappear = @selector(viewWillDisappear:), layout = @selector(viewDidLayoutSubviews);
    if (!MTChargingMethodSupported(cls, appear, YES) || !MTChargingMethodSupported(cls, disappear, YES) ||
        !MTChargingMethodSupported(cls, layout, NO)) {
        MTLogWarn(@"charging", @"state=hooks-unavailable"); return;
    }
    MSHookMessageEx(cls, appear, (IMP)MTChargingAppear, (IMP *)&MTChargingOriginalAppear);
    MSHookMessageEx(cls, disappear, (IMP)MTChargingDisappear, (IMP *)&MTChargingOriginalDisappear);
    MSHookMessageEx(cls, layout, (IMP)MTChargingLayout, (IMP *)&MTChargingOriginalLayout);
    SEL screenOff = NSSelectorFromString(@"setInScreenOffMode:");
    if (MTChargingMethodSupported(cls, screenOff, YES))
        MSHookMessageEx(cls, screenOff, (IMP)MTChargingScreenOff, (IMP *)&MTChargingOriginalScreenOff);
    SEL contentAbove = NSSelectorFromString(@"_setHasContentAboveCoverSheet:");
    if (MTChargingMethodSupported(cls, contentAbove, YES))
        MSHookMessageEx(cls, contentAbove, (IMP)MTChargingContentAbove, (IMP *)&MTChargingOriginalContentAbove);
    SEL pageIndex = NSSelectorFromString(@"setLastSettledPageIndex:");
    NSMethodSignature *pageSignature = [cls instanceMethodSignatureForSelector:pageIndex];
    if (pageSignature.numberOfArguments == 3 && !strcmp(pageSignature.methodReturnType, "v") &&
        !strcmp([pageSignature getArgumentTypeAtIndex:2], "Q"))
        MSHookMessageEx(cls, pageIndex, (IMP)MTChargingPageIndex, (IMP *)&MTChargingOriginalPageIndex);
}
