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

@interface MTChargingRuntime : NSObject
@property(nonatomic, weak) UIViewController *host;
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
@property(nonatomic) double ampsEMA;
@property(nonatomic) int displayToken;
@property(nonatomic) int lockToken;
+ (instancetype)shared;
- (void)refresh;
- (void)layout;
- (void)stop;
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
    }
    self.lastProbeTime = 0;
    [self refresh];
}
- (void)batteryChanged:(NSNotification *)notification {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.lastProbeTime = 0; [self refresh]; });
    } else { self.lastProbeTime = 0; [self refresh]; }
}
- (BOOL)canShow {
    UIView *view = self.host.viewIfLoaded;
    return self.enabled && self.appeared && self.displayOn && view.window && !view.hidden &&
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
    self.ampsEMA = 0;
}
- (void)refresh {
    if (![self canShow]) { [self stop]; return; }
    UIDeviceBatteryState state = UIDevice.currentDevice.batteryState;
    if (self.sampling) return;
    NSTimeInterval probeTime = NSProcessInfo.processInfo.systemUptime;
    if (probeTime - self.lastProbeTime < 0.8) return;
    self.lastProbeTime = probeTime;
    self.sampling = YES;
    NSUInteger generation = self.generation;
    double level = UIDevice.currentDevice.batteryLevel;
    BOOL charging = state == UIDeviceBatteryStateCharging;
    BOOL connected = charging || state == UIDeviceBatteryStateFull;
    dispatch_async(self.samplingQueue, ^{
        MTChargingSnapshot *snapshot = [MTChargingSnapshot snapshotWithProperties:MTChargingReadBattery()
            fallbackLevel:level connected:connected charging:charging];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.sampling = NO;
            if (generation != self.generation || ![self canShow]) return;
            if (!snapshot.connected) { [self stop]; return; }
            // Smooth the charging current before deriving the ETA: a single noisy
            // sample would otherwise rewrite the estimate every second.
            if (snapshot.charging && isfinite(snapshot.amps) && snapshot.amps > 0) {
                self.ampsEMA = self.ampsEMA > 0 ? self.ampsEMA * 0.85 + snapshot.amps * 0.15 : snapshot.amps;
                snapshot.minutesToFull = [MTChargingSnapshot minutesToFullForRemainingMilliampHours:
                    snapshot.remainingMilliampHours currentMilliamp:self.ampsEMA * 1000.0];
            } else self.ampsEMA = 0;
            if (!self.timer) {
                __weak typeof(self) weakSelf = self;
                self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
                self.timer.tolerance = 0.15;
                [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
            }
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
    CGFloat width = MIN(host.bounds.size.width - 32, 430);
    CGFloat height = width * MTChargingCardDesignHeight / MTChargingCardDesignWidth;
    CGFloat bottom = host.bounds.size.height - host.safeAreaInsets.bottom - 86;
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
