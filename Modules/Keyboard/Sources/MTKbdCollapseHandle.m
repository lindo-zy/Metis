// 键盘收起把手：解锁亮屏且键盘隐藏时显示；支持拖动、吸边和手动缩入边缘。
// 点按弹出 App 面板：配置了固定应用列表（kbdhandleapps）则展示配置项
// （显示名排序、容量按屏高限制），否则回退最近悬浮过的 App（固定 6 项）。
// 可选自动隐藏：静置超过设定秒数（0.5~10）把手滑入屏幕边缘只露一小截
// （与手动缩边同视觉，参照 PullOver-X 把手 nub；点按或向内拖出恢复），
// 只有键盘弹出/锁屏/息屏才整体隐藏。悬浮窗口本体复用 MTFloatingAppRuntime，
// 本文件只负责显隐状态机与把手/面板 UI。

#import "MTKbdCollapseHandle.h"
#import "MTKbdHandleLayout.h"
#import "MTQuickLauncherView.h"
#import "MTDarwinOpenChannel.h"
#import "MTSystemOpenBroker.h"
#import "MTGlobalPanel.h"
#import "MTHelper.h"
#import "common.h"
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <string.h>

// 键盘显隐通道：纯信号 + 一个状态字（1=键盘可见，0=已收起）。键盘进程写、
// SpringBoard 读；与 open/shelf 通道同风格，但不承载 payload。
static char const *const MTKbdVisibilityChangedName = "com.lindo.metis.keyboard/kbdvis";
static const uint64_t MTKbdVisibilityShownWord = 1;

#pragma mark - 键盘进程上报

static int MTKbdVisibilityToken = NOTIFY_TOKEN_INVALID;

static void MTKbdVisibilityPost(uint64_t word) {
    if (MTKbdVisibilityToken == NOTIFY_TOKEN_INVALID) return;
    if (notify_set_state(MTKbdVisibilityToken, word) != NOTIFY_STATUS_OK) return;
    if (notify_post(MTKbdVisibilityChangedName) != NOTIFY_STATUS_OK) return;
    static uint64_t lastPosted;
    if (word != lastPosted) {
        lastPosted = word;
        NSLog(@"[MetisKeyboard][KbdHandle] keyboard visibility word=%llu", (unsigned long long)word);
    }
}

@interface MTKbdVisibilityReporter : NSObject
- (void)keyboardWillShow:(NSNotification *)notification;
- (void)keyboardDidHide:(NSNotification *)notification;
@end

@implementation MTKbdVisibilityReporter
- (void)keyboardWillShow:(__unused NSNotification *)notification { MTKbdVisibilityPost(MTKbdVisibilityShownWord); }
- (void)keyboardDidHide:(__unused NSNotification *)notification { MTKbdVisibilityPost(0); }
@end

// iOS 9+ 通知中心对 selector 观察者持零化弱引用，块内局部引用会在安装完成后
// 立即释放并反注册，必须由进程级静态持有（同 topToolbarLifecycleObserver）。
static MTKbdVisibilityReporter *MTKbdVisibilityReporterInstance;

void MTStartKbdVisibilityReporter(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (notify_register_check(MTKbdVisibilityChangedName, &MTKbdVisibilityToken) != NOTIFY_STATUS_OK) return;
        MTKbdVisibilityReporterInstance = [MTKbdVisibilityReporter new];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:MTKbdVisibilityReporterInstance selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
        [center addObserver:MTKbdVisibilityReporterInstance selector:@selector(keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
        NSLog(@"[MetisKeyboard][KbdHandle] reporter installed");
    });
}

#pragma mark - SpringBoard 端

static BOOL MTKbdHandleEnabled(void) {
    MTPrefsManager *manager = [MTPrefsManager sharedInstance];
    NSDictionary *preferences = manager.preferencesAvailable ? manager.readPrefs : nil;
    id value = [preferences isKindOfClass:[NSDictionary class]] ? preferences[kKbdHandleEnabledKey] : nil;
    return [value isKindOfClass:[NSNumber class]] && [value boolValue];
}

static BOOL MTKbdHandleScreenIsOn(void) {
    int token = NOTIFY_TOKEN_INVALID;
    uint64_t blanked = 1;
    if (notify_register_check("com.apple.springboard.hasBlankedScreen", &token) != NOTIFY_STATUS_OK) return NO;
    BOOL read = notify_get_state(token, &blanked) == NOTIFY_STATUS_OK;
    notify_cancel(token);
    return read && blanked == 0;
}

// LOCALIZED 宏依赖 MTKeyboardHooks.xm 的 tweakBundle 静态变量，这里独立取同一 bundle。
static NSString *MTKbdHandleLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}

// 独立背景层的跨进程命中与悬浮卡同源：WindowServer 先按渲染图层选触摸，透明
// 边界必须显式参与命中；不支持的系统回退 3% 实际绘制遮罩。
static BOOL MTKbdHandleConfigureBackdropHitTesting(id layer) {
    for (NSString *getterName in @[@"allowsHitTesting", @"hitTestsAsOpaque"]) {
        SEL getter = NSSelectorFromString(getterName);
        NSString *setterName = [NSString stringWithFormat:@"set%@%@:",
            [[getterName substringToIndex:1] uppercaseString], [getterName substringFromIndex:1]];
        SEL setter = NSSelectorFromString(setterName);
        NSMethodSignature *getSignature = [layer methodSignatureForSelector:getter];
        NSMethodSignature *setSignature = [layer methodSignatureForSelector:setter];
        if (![layer respondsToSelector:getter] || ![layer respondsToSelector:setter] ||
            getSignature.numberOfArguments != 2 || setSignature.numberOfArguments != 3 ||
            strcmp(setSignature.methodReturnType, "v")) return NO;
        const char *result = getSignature.methodReturnType;
        const char *argument = [setSignature getArgumentTypeAtIndex:2];
        if ((strcmp(result, "B") && strcmp(result, "c")) ||
            (strcmp(argument, "B") && strcmp(argument, "c"))) return NO;
        @try {
            ((void (*)(id, SEL, bool))objc_msgSend)(layer, setter, true);
            if (!((bool (*)(id, SEL))objc_msgSend)(layer, getter)) return NO;
        } @catch (__unused NSException *exception) { return NO; }
    }
    return YES;
}

static id MTKbdHandleObjectValue(id object, NSString *methodName) {
    if (!object) return nil;
    SEL selector = NSSelectorFromString(methodName);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (![object respondsToSelector:selector] || !signature || signature.numberOfArguments != 2 ||
        strcmp(signature.methodReturnType, "@")) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}

static NSString *MTKbdHandleDisplayName(NSString *bundleIdentifier) {
    id controller = MTKbdHandleObjectValue(NSClassFromString(@"SBApplicationController"), @"sharedInstance");
    id application = nil;
    if ([controller respondsToSelector:@selector(applicationWithBundleIdentifier:)]) {
        @try {
            application = ((id (*)(id, SEL, id))objc_msgSend)(controller,
                @selector(applicationWithBundleIdentifier:), bundleIdentifier);
        } @catch (__unused NSException *exception) {}
    }
    id name = MTKbdHandleObjectValue(application, @"displayName");
    return [name isKindOfClass:[NSString class]] && [name length] > 0 ? name : bundleIdentifier;
}

// 瓦片图标与把手内嵌图标同为 24pt 槽位，直接用 MTHelper 的共享缓存（含磁盘缓存）；
// 取不到再回退占位 SF 符号，与工具栏按钮的降级路径一致。
static UIImage *MTKbdHandleApplicationIcon(NSString *bundleIdentifier) {
    UIImage *image = [MTHelper appIconImageForBundleID:bundleIdentifier];
    if (!image) image = [UIImage systemImageNamed:@"app"];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

@class MTKbdHandleWindow;

@interface MTKbdCollapseHandle : NSObject
@property(nonatomic, strong) MTKbdHandleWindow *window;
@property(nonatomic, strong) UIView *backdrop;
@property(nonatomic, strong) UIView *panelView;
@property(nonatomic, strong) MTQuickLauncherView *quickView;
@property(nonatomic) BOOL quickEnabled;
@property(nonatomic) BOOL launchPending;
@property(nonatomic) NSUInteger launchRequest;
@property(nonatomic, copy) NSDictionary *launcherPreferences;
@property(nonatomic) CGRect lastLayoutBounds;
@property(nonatomic, strong) UIView *handleView;
@property(nonatomic, strong) UIVisualEffectView *handleMaterial;
@property(nonatomic, strong) UIImageView *handleIconView;
@property(nonatomic, strong) NSMutableArray<UIButton *> *panelButtons;
@property(nonatomic, strong) NSMutableArray<NSString *> *recentIdentifiers;
@property(nonatomic, copy) NSArray<NSString *> *selectedIdentifiers;
@property(nonatomic, copy) NSArray<NSString *> *panelItems;
@property(nonatomic) NSInteger alignment;
@property(nonatomic) CGFloat anchorFraction;
@property(nonatomic) BOOL nubbed;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic, strong) UIPanGestureRecognizer *handlePan;
@property(nonatomic) BOOL dragging;
@property(nonatomic) CGPoint dragStartCenter;
@property(nonatomic) CGPoint dragCenter;
@property(nonatomic) CGRect dragBounds;
@property(nonatomic) NSInteger dragStartAlignment;
@property(nonatomic) CGFloat dragStartFraction;
@property(nonatomic) BOOL dragStartNubbed;
@property(nonatomic) BOOL startupReady;
@property(nonatomic, strong) id launchObserver;
@property(nonatomic) NSUInteger panelGeneration;
@property(nonatomic) BOOL panelOpen;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL autoHideEnabled;
@property(nonatomic) NSTimeInterval autoHideInterval;
@property(nonatomic, strong) NSTimer *autoHideTimer;
+ (instancetype)shared;
- (void)start;
- (void)applyVisibilityWord:(BOOL)visible;
- (void)handleEnvironmentChange:(NSString *)reason;
- (void)finishStartup;
- (void)refreshVisibility;
- (void)applyPreferences;
- (void)noteFloated:(NSString *)bundleIdentifier;
- (void)layoutForBounds:(CGRect)bounds;
- (void)cancelHandleDrag;
- (void)saveHandlePlacement;
- (NSArray<NSString *> *)panelIdentifiers;
- (NSUInteger)panelCapacityForBounds:(CGRect)bounds;
- (void)armAutoHideTimer;
- (void)cancelAutoHideTimer;
- (void)autoHideTimerFired:(NSTimer *)timer;
- (void)outsideInteractionOnBackdrop:(UIView *)backdrop;
@end

// 在落指时消费面板外的整段触摸，不等待点按/滑动/长按识别结果。
@interface MTKbdHandleBackdropView : UIView
@property(nonatomic, weak) MTKbdCollapseHandle *manager;
@end

@implementation MTKbdHandleBackdropView
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(__unused UIEvent *)event {
    if (touches.count > 0) [self.manager outsideInteractionOnBackdrop:self];
}
@end

@interface MTKbdHandleWindow : UIWindow
@property(nonatomic, weak) MTKbdCollapseHandle *manager;
@end

@implementation MTKbdHandleWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (bool)_shouldCreateContextAsSecure { return YES; }
- (void)layoutSubviews {
    [super layoutSubviews];
    [self.manager layoutForBounds:self.bounds];
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = [super hitTest:point withEvent:event];
    if (self.hidden || !self.manager.handleView)
        return result == (UIView *)self ? nil : result;
    // 视觉缩小到 34pt，触摸仍保留屏幕内的 44pt 范围，缩边时也能点按/向内拉。
    CGRect handle = self.manager.handleView.frame;
    CGRect target = CGRectMake(MTKbdHandleClamp(CGRectGetMidX(handle) - 22,
        CGRectGetMinX(self.bounds), CGRectGetMaxX(self.bounds) - 44),
        MTKbdHandleClamp(CGRectGetMidY(handle) - 22, CGRectGetMinY(self.bounds), CGRectGetMaxY(self.bounds) - 44), 44, 44);
    // 面板打开：面板与把手之外的任何落点一律定向给背景层（落指即收起）。
    // 不依赖背景层自身命中，窗口层直接定向，透明路由失效时也收得起。
    if (self.manager.panelOpen) {
        CGRect panel = self.manager.quickEnabled ? self.manager.quickView.frame : self.manager.panelView.frame;
        if (!CGRectContainsPoint(panel, point) && !CGRectContainsPoint(target, point))
            return self.manager.backdrop;
    }
    if ((result == self || result == self.manager.backdrop) && CGRectContainsPoint(target, point))
        return self.manager.handleView;
    // 空白区域穿透给宿主 App/SpringBoard；只有把手、面板与打开态背景层接收触摸。
    return result == (UIView *)self ? nil : result;
}
@end

@implementation MTKbdCollapseHandle
+ (instancetype)shared {
    static MTKbdCollapseHandle *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ handle = [self new]; });
    return handle;
}

- (void)start {
    if (self.started) return;
    self.started = YES;
    self.recentIdentifiers = [NSMutableArray array];
    self.panelButtons = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    int token = NOTIFY_TOKEN_INVALID;
    if (notify_register_dispatch(MTKbdVisibilityChangedName, &token, dispatch_get_main_queue(), ^(__unused int eventToken) {
        MTKbdCollapseHandle *host = weakSelf;
        if (!host) return;
        uint64_t word = 0;
        if (notify_get_state(eventToken, &word) != NOTIFY_STATUS_OK) return;
        [host applyVisibilityWord:word == MTKbdVisibilityShownWord];
    }) != NOTIFY_STATUS_OK) {
        NSLog(@"[MetisKeyboard][KbdHandle] visibility observer failed");
    }
    for (NSString *name in @[@"com.apple.springboard.lockstate", @"com.apple.springboard.hasBlankedScreen"]) {
        notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(__unused int eventToken) {
            [weakSelf handleEnvironmentChange:@"screen"];
        });
    }
    notify_register_dispatch("com.apple.springboard.frontmostapplicationchanged", &token, dispatch_get_main_queue(), ^(__unused int eventToken) {
        [weakSelf handleEnvironmentChange:@"foreground"];
    });
    notify_register_dispatch(kPrefsChangedIdentifier.UTF8String, &token, dispatch_get_main_queue(), ^(__unused int eventToken) {
        [weakSelf applyPreferences];
    });
    // start 从 tweak ctor 调用；私有锁屏单例和 Window/Scene 必须等 SB 完成启动。
    self.launchObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(__unused NSNotification *notification) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finishStartup]; });
        }];
        [self applyPreferences];
        // 主路径同步置位 startupReady：本块由 %ctor dispatch_async(main) 入队，
        // 执行时 UIApplicationDidFinishLaunchingNotification 通常已广播完毕
        // （didFinishLaunching 返回即发通知，早于主队列块执行），仅依赖通知
        // 观察者会把 startupReady 永远留在 NO、把手永不显示。finishStartup
        // 幂等：与 SMS/浏览器重定向一致「ctor 同步先跑 + 通知兜底」，块若
        // 确实早于通知执行也走同一路径，观察者保留作双保险。
        [self finishStartup];
        NSLog(@"[MetisKeyboard][KbdHandle] host started");
}

- (void)finishStartup {
    if (self.startupReady) return;
    self.startupReady = YES;
    if (self.launchObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.launchObserver];
        self.launchObserver = nil;
    }
    [self applyPreferences];
}

// 键盘开始弹出即隐藏，完全收起再恢复，避免把手盖在键盘动画上。
- (void)applyVisibilityWord:(BOOL)visible {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self applyVisibilityWord:visible]; }); return; }
    self.keyboardVisible = visible;
    [self refreshVisibility];
}

// 前台切换/回桌面收面板但保留入口；锁屏/息屏隐藏，解锁/亮屏重新显示。
- (void)handleEnvironmentChange:(NSString *)reason {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self handleEnvironmentChange:reason]; }); return; }
    [self cancelHandleDrag];
    [self closePanel:NO];
    [self refreshVisibility];
}

- (void)refreshVisibility {
    if (!self.startupReady) return;
    if (!MTKbdHandleEnabled()) {
        [self hideHandleWithReason:@"prefs-disabled"];
    } else if (self.keyboardVisible) {
        [self hideHandleWithReason:@"keyboard-shown"];
    } else if (![MTGlobalPanel deviceUnlocked] || !MTKbdHandleScreenIsOn()) {
        [self hideHandleWithReason:@"screen"];
    } else {
        [self showHandleAnimated:YES];
    }
}

- (void)applyPreferences {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self applyPreferences]; }); return; }
    [[MTPrefsManager sharedInstance] reload];
    MTPrefsManager *manager = [MTPrefsManager sharedInstance];
    NSDictionary *preferences = manager.preferencesAvailable ? manager.readPrefs : nil;
    if (!self.dragging) {
        self.alignment = MTKbdHandlePositionFromPreferences(preferences);
        id anchor = preferences[kKbdHandleAnchorKey];
        self.anchorFraction = [anchor isKindOfClass:[NSNumber class]] && isfinite([anchor doubleValue])
            ? MTKbdHandleClamp([anchor doubleValue], 0, 1) : 1;
        id nubbed = preferences[kKbdHandleNubbedKey];
        self.nubbed = [nubbed isKindOfClass:[NSNumber class]] && [nubbed boolValue];
    }
    id autoHide = preferences[kKbdHandleAutoHideKey];
    self.autoHideEnabled = [autoHide isKindOfClass:[NSNumber class]] && [autoHide boolValue];
    self.autoHideInterval = MTKbdHandleAutoHideSecondsFromPreferences(preferences);
    BOOL enabled = [preferences[kKbdQuickLauncherKey] isKindOfClass:NSNumber.class] && [preferences[kKbdQuickLauncherKey] boolValue];
    BOOL launcherChanged = self.quickEnabled != enabled;
    for (NSString *key in @[kKbdHandleAppsKey, kKbdLauncherOrderKey, kKbdLauncherAliasesKey, kKbdHandlePositionKey]) {
        id previous = self.launcherPreferences[key] ?: NSNull.null, current = preferences[key] ?: NSNull.null;
        if (![previous isEqual:current]) launcherChanged = YES;
    }
    if (self.panelOpen && (self.quickEnabled || enabled) && launcherChanged) [self closePanel:NO];
    self.quickEnabled = enabled;
    self.launcherPreferences = [preferences copy] ?: @{};
    self.selectedIdentifiers = MTKbdHandleAppsFromPreferences(preferences);
    [self refreshVisibility];
    if (self.window && !self.window.hidden) [self layoutForBounds:self.window.bounds];
    if (self.panelOpen && !self.quickEnabled) [self rebuildPanel];
    // 偏好变化后定时器按新开关/时长重新布防；正在使用的面板与拖动由
    // closePanel / handlePanned 的各自路径负责，这里只对齐静止态。
    if (self.autoHideEnabled && self.window && !self.window.hidden && !self.panelOpen && !self.dragging) {
        [self armAutoHideTimer];
    } else {
        [self cancelAutoHideTimer];
    }
}

- (void)noteFloated:(NSString *)bundleIdentifier {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self noteFloated:bundleIdentifier]; }); return; }
    if (!MTIsValidBundleIdentifier(bundleIdentifier)) return;
    if (!self.recentIdentifiers) self.recentIdentifiers = [NSMutableArray array];
    [self.recentIdentifiers removeObject:bundleIdentifier];
    [self.recentIdentifiers insertObject:bundleIdentifier atIndex:0];
    while (self.recentIdentifiers.count > (NSUInteger)kKbdCollapsePanelCapacity) [self.recentIdentifiers removeLastObject];
    if (self.panelOpen && !self.quickEnabled) [self rebuildPanel];
}

#pragma mark 面板数据源与自动隐藏

// 固定列表模式的容量：竖排瓦片加把手必须整体放进安全区，放不下的条目不展示。
- (NSUInteger)panelCapacityForBounds:(CGRect)bounds {
    UIEdgeInsets safe = self.window ? self.window.safeAreaInsets : UIEdgeInsetsZero;
    CGFloat top = CGRectGetMinY(bounds) + MAX(0, safe.top) + MTKbdHandleEdgeMargin;
    CGFloat bottom = CGRectGetMaxY(bounds) - MAX(0, safe.bottom) - MTKbdHandleEdgeMargin;
    CGFloat pitch = MTKbdPanelTileSide + MTKbdPanelTileGap;
    // n 块瓦片总高 side*n+gap*(n-1)；再扣掉把手自身占位，保证翻转下置时也不越界。
    CGFloat span = bottom - top - MTKbdHandleSide - MTKbdHandleBottomGap;
    if (span < pitch) return 1;
    return (NSUInteger)floor((span + MTKbdPanelTileGap) / pitch);
}

// 面板数据源：配置了固定应用列表则展示配置项（AltList 存的是无序集合，展示前
// 按显示名稳定排序），否则回退最近悬浮列表（固定 6 项）。
- (NSArray<NSString *> *)panelIdentifiers {
    if (self.selectedIdentifiers.count == 0) {
        NSArray<NSString *> *recents = self.recentIdentifiers;
        NSUInteger count = MIN(recents.count, (NSUInteger)kKbdCollapsePanelCapacity);
        return count == 0 ? @[] : [recents subarrayWithRange:NSMakeRange(0, count)];
    }
    NSMutableArray<NSString *> *identifiers = [self.selectedIdentifiers mutableCopy];
    [identifiers sortUsingComparator:^NSComparisonResult(NSString *first, NSString *second) {
        NSComparisonResult order = [MTKbdHandleDisplayName(first) localizedStandardCompare:MTKbdHandleDisplayName(second)];
        return order != NSOrderedSame ? order : [first compare:second];
    }];
    NSUInteger capacity = [self panelCapacityForBounds:self.window.bounds];
    if (identifiers.count > capacity) [identifiers removeObjectsInRange:NSMakeRange(capacity, identifiers.count - capacity)];
    return identifiers;
}

// 布防自动隐藏：只在把手可见且未缩边时启动一次性定时器（缩边即目标态，
// 无需倒计时）；面板打开/拖动等使用态由各自路径先 cancel，展开后重新 arm。
- (void)armAutoHideTimer {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self armAutoHideTimer]; }); return; }
    [self.autoHideTimer invalidate];
    self.autoHideTimer = nil;
    if (!self.autoHideEnabled || !self.window || self.window.hidden || self.nubbed) return;
    self.autoHideTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(0.01, self.autoHideInterval)
                                                          target:self selector:@selector(autoHideTimerFired:)
                                                        userInfo:nil repeats:NO];
}

- (void)cancelAutoHideTimer {
    [self.autoHideTimer invalidate];
    self.autoHideTimer = nil;
}

- (void)autoHideTimerFired:(NSTimer *)timer {
    self.autoHideTimer = nil;
    if (!self.autoHideEnabled || !self.window || self.window.hidden) return;
    if (self.panelOpen || self.dragging) { [self armAutoHideTimer]; return; }
    // 已缩边（手动或自动）不再动作：半露出本身就是最小占用常态。
    if (self.nubbed) return;
    // 自动隐藏=滑入边缘只露 11pt（PullOver-X 把手 nub 同款语义），不是整体
    // 消失；点按/向内拖出恢复，与手动缩边共用同一状态并持久化。
    NSLog(@"[MetisKeyboard][KbdHandle] auto tuck after %.1fs", self.autoHideInterval);
    self.nubbed = YES;
    [self saveHandlePlacement];
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
        animations:^{ [self layoutForBounds:self.window.bounds]; } completion:nil];
}

#pragma mark 窗口与视图

- (UIWindowScene *)windowScene {
    UIWindowScene *fallback = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        NSString *identity = windowScene.session.persistentIdentifier ?: @"";
        NSString *role = windowScene.session.role ?: @"";
        if ([identity isEqual:@"com.apple.springboard"]) return windowScene;
        if ([identity.lowercaseString containsString:@"keyboard"] || [identity.lowercaseString containsString:@"systemaperture"] ||
            [role.lowercaseString containsString:@"keyboard"] || [role.lowercaseString containsString:@"systemaperture"]) continue;
        if ([NSStringFromClass(windowScene.class) isEqual:@"SBWindowScene"]) fallback = windowScene;
    }
    return fallback;
}

- (void)createWindowIfNeeded {
    if (self.window) return;
    UIWindowScene *scene = [self windowScene];
    if (!scene) {
        NSLog(@"[MetisKeyboard][KbdHandle] window scene unavailable");
        return;
    }
    MTKbdHandleWindow *window = [[MTKbdHandleWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.backgroundColor = [UIColor clearColor];
    // 悬浮卡(level 100)之上、状态栏(999)之下：面板能盖住已打开的悬浮卡完成切换。
    window.windowLevel = 101;
    window.manager = self;
    window.hidden = YES;

    MTKbdHandleBackdropView *backdrop = [[MTKbdHandleBackdropView alloc] initWithFrame:window.bounds];
    backdrop.manager = self;
    self.backdrop = backdrop;
    self.backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // 面板打开态的轻遮罩：可见像素保证 WindowServer 把外部触摸路由进本窗口
    // （透明层在渲染端可能不参与跨进程命中，外部点按到不了收起手势，正是
    // 「点外部收不起面板」的根因）；私有点击层标志仍照设作双保险。
    self.backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.04];
    self.backdrop.hidden = YES;
    self.backdrop.alpha = 0;
    BOOL hitTestingConfigured = MTKbdHandleConfigureBackdropHitTesting(self.backdrop.layer);
    [window addSubview:self.backdrop];

    // 面板只是瓦片的定位容器：背景与阴影都在每块瓦片上（同把手样式），
    // 这里保持全透明，不再画整体胶囊。
    self.panelView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, MTKbdPanelWidth, 1)];
    self.panelView.backgroundColor = [UIColor clearColor];
    self.panelView.alpha = 0;
    self.panelView.hidden = YES;
    [window addSubview:self.panelView];

    self.handleView = [[UIView alloc] initWithFrame:CGRectZero];
    self.handleView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.handleView.layer.shadowOpacity = 0.25;
    self.handleView.layer.shadowRadius = 6;
    self.handleView.layer.shadowOffset = CGSizeMake(0, 2);
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapped:)];
    self.handlePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanned:)];
    self.handlePan.maximumNumberOfTouches = 1;
    [self.handleView addGestureRecognizer:self.handlePan];
    [tap requireGestureRecognizerToFail:self.handlePan];
    [self.handleView addGestureRecognizer:tap];
    self.handleView.isAccessibilityElement = YES;
    self.handleView.accessibilityLabel = MTKbdHandleLocalized(@"FLOATING_HANDLE_ACCESSIBILITY");
    self.handleView.accessibilityTraits = UIAccessibilityTraitButton;
    [window addSubview:self.handleView];

    self.handleMaterial = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    self.handleMaterial.layer.cornerRadius = MTKbdHandleCornerRadius;
    self.handleMaterial.layer.cornerCurve = kCACornerCurveContinuous;
    self.handleMaterial.clipsToBounds = YES;
    self.handleMaterial.userInteractionEnabled = NO;
    [self.handleView addSubview:self.handleMaterial];

    UIImage *icon = [UIImage imageWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Keyboard512.png"]]
        ?: [MTHelper imageForTypeXWithPlaceholder:NO];
    self.handleIconView = [[UIImageView alloc] initWithImage:icon];
    self.handleIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.handleIconView.layer.cornerRadius = 5;
    self.handleIconView.layer.cornerCurve = kCACornerCurveContinuous;
    self.handleIconView.clipsToBounds = YES;
    [self.handleMaterial.contentView addSubview:self.handleIconView];

    self.window = window;
    NSLog(@"[MetisKeyboard][KbdHandle] window created backdropRouting=%d", hitTestingConfigured);
}

- (void)layoutForBounds:(CGRect)bounds {
    if (!self.window || !self.handleView || bounds.size.width < 1 || bounds.size.height < 1) return;
    UIEdgeInsets safe = self.window.safeAreaInsets;
    if (!CGRectIsEmpty(self.lastLayoutBounds) && !CGRectEqualToRect(bounds, self.lastLayoutBounds) && self.panelOpen && self.quickEnabled) [self closePanel:NO];
    self.lastLayoutBounds = bounds;
    if (self.dragging && !CGRectEqualToRect(bounds, self.dragBounds)) [self cancelHandleDrag];
    CGRect handleFrame = MTKbdHandleFrame(bounds, safe.top, safe.bottom,
        self.alignment, self.anchorFraction, self.nubbed);
    if (self.dragging) {
        CGPoint center = MTKbdHandleDragCenter(bounds, safe.top, safe.bottom, self.dragCenter);
        handleFrame.origin = CGPointMake(center.x - MTKbdHandleSide / 2, center.y - MTKbdHandleSide / 2);
    }
    // frame 与缩放 transform 同时修改会漂移；几何始终由 bounds/center 定位。
    self.handleView.bounds = CGRectMake(0, 0, MTKbdHandleSide, MTKbdHandleSide);
    self.handleView.center = CGPointMake(CGRectGetMidX(handleFrame), CGRectGetMidY(handleFrame));
    self.handleView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.handleView.bounds
                                                                   cornerRadius:MTKbdHandleCornerRadius].CGPath;
    self.handleMaterial.frame = self.handleView.bounds;
    self.handleIconView.frame = UIEdgeInsetsInsetRect(self.handleMaterial.bounds,
        UIEdgeInsetsMake(MTKbdHandleIconInset, MTKbdHandleIconInset, MTKbdHandleIconInset, MTKbdHandleIconInset));

    NSUInteger items = self.panelItems.count;
    CGRect panelFrame = MTKbdHandlePanelFrame(bounds, safe.top, safe.bottom, handleFrame, items);
    self.panelView.bounds = CGRectMake(0, 0, panelFrame.size.width, panelFrame.size.height);
    self.panelView.center = CGPointMake(CGRectGetMidX(panelFrame), CGRectGetMidY(panelFrame));
    if (self.quickView) {
        CGRect quickFrame = MTQuickLauncherFrame(bounds, safe, self.alignment);
        // Keep the small handle available alongside the bottom panel.
        if (self.panelOpen && self.quickEnabled && CGRectIntersectsRect(quickFrame, handleFrame)) {
            quickFrame.size.width = MAX(0, quickFrame.size.width - MTKbdHandleSide - 6);
            if (self.alignment == 0) quickFrame.origin.x += MTKbdHandleSide + 6;
        }
        self.quickView.frame = quickFrame;
    }
}

#pragma mark 显隐与面板

- (void)showHandleAnimated:(BOOL)animated {
    // 重复键盘/前台通知不能重启动画、闪烁把手或关闭正在使用的面板。
    if (self.window && !self.window.hidden) return;
    [self createWindowIfNeeded];
    if (!self.window) return;
    [self.handleView.layer removeAllAnimations];
    self.handleView.transform = CGAffineTransformIdentity;
    [self rebuildPanel];
    self.panelOpen = NO;
    self.backdrop.hidden = YES;
    self.backdrop.alpha = 0;
    self.panelView.hidden = YES;
    self.window.hidden = NO;
    [self layoutForBounds:self.window.bounds];
    if (animated) {
        self.handleView.alpha = 0;
        self.handleView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.handleView.alpha = 1;
            self.handleView.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        self.handleView.alpha = 1;
        self.handleView.transform = CGAffineTransformIdentity;
    }
    [self armAutoHideTimer];
    NSLog(@"[MetisKeyboard][KbdHandle] handle shown items=%lu pinned=%d", (unsigned long)self.panelItems.count,
        self.selectedIdentifiers.count > 0);
}

- (void)hideHandleWithReason:(NSString *)reason {
    [self cancelHandleDrag];
    if (!self.window || self.window.hidden) return;
    [self closePanel:NO];
    // closePanel 会按「面板关了、把手仍在」重新布防，但本路径最终要隐藏，
    // 撤销布防避免隐藏后残留空转定时器。
    [self cancelAutoHideTimer];
    [self.handleView.layer removeAllAnimations];
    self.window.hidden = YES;
    self.handleView.alpha = 1;
    self.handleView.transform = CGAffineTransformIdentity;
    NSLog(@"[MetisKeyboard][KbdHandle] handle hidden reason=%@", reason);
}

- (void)saveHandlePlacement {
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    [manager reload];
    NSDictionary *preferences = manager.preferencesAvailable ? manager.readPrefs : nil;
    if (![preferences isKindOfClass:[NSDictionary class]]) return;
    NSMutableDictionary *updated = [preferences mutableCopy];
    updated[kKbdHandlePositionKey] = @(self.alignment);
    updated[kKbdHandleAnchorKey] = @(MTKbdHandleClamp(self.anchorFraction, 0, 1));
    updated[kKbdHandleNubbedKey] = @(self.nubbed);
    [manager writePrefs:updated];
}

- (void)cancelHandleDrag {
    if (!self.dragging) return;
    self.dragging = NO;
    self.alignment = self.dragStartAlignment;
    self.anchorFraction = self.dragStartFraction;
    self.nubbed = self.dragStartNubbed;
    // 系统取消/锁屏/键盘出现不能把半途位置写回，也不能留下仍在追踪的手势。
    self.handlePan.enabled = NO;
    self.handlePan.enabled = YES;
    if (self.window && !self.window.hidden) [self layoutForBounds:self.window.bounds];
    // 拖动被系统打断视为一次交互结束，静止计时重新开始（后续隐藏路径会再撤销）。
    [self armAutoHideTimer];
}

- (void)handlePanned:(UIPanGestureRecognizer *)gesture {
    if (!NSThread.isMainThread) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (!self.window || self.window.hidden || self.keyboardVisible) return;
        [self closePanel:NO];
        [self cancelAutoHideTimer];
        [self.handleView.layer removeAllAnimations];
        self.handleView.transform = CGAffineTransformIdentity;
        self.dragStartAlignment = self.alignment;
        self.dragStartFraction = self.anchorFraction;
        self.dragStartNubbed = self.nubbed;
        self.dragStartCenter = self.handleView.center;
        self.dragCenter = self.dragStartCenter;
        self.dragBounds = self.window.bounds;
        self.dragging = YES;
        return;
    }
    if (!self.dragging) return;
    if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed ||
        !CGRectEqualToRect(self.dragBounds, self.window.bounds)) {
        [self cancelHandleDrag];
        return;
    }
    CGPoint translation = [gesture translationInView:self.window];
    if (!isfinite(translation.x) || !isfinite(translation.y)) { [self cancelHandleDrag]; return; }
    CGPoint point = CGPointMake(self.dragStartCenter.x + translation.x, self.dragStartCenter.y + translation.y);
    UIEdgeInsets safe = self.window.safeAreaInsets;
    self.dragCenter = MTKbdHandleDragCenter(self.window.bounds, safe.top, safe.bottom, point);
    if (gesture.state == UIGestureRecognizerStateChanged) {
        [self layoutForBounds:self.window.bounds];
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        NSInteger side = self.dragCenter.x >= CGRectGetMidX(self.window.bounds) ? 1 : 0;
        self.nubbed = MTKbdHandleShouldNub(self.window.bounds, self.dragCenter, translation, self.dragStartAlignment, side);
        self.alignment = side;
        self.anchorFraction = MTKbdHandleFraction(self.window.bounds, safe.top, safe.bottom, self.dragCenter.y);
        self.dragging = NO;
        [self saveHandlePlacement];
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            [self layoutForBounds:self.window.bounds];
        } completion:nil];
        [self armAutoHideTimer];
        NSLog(@"[MetisKeyboard][KbdHandle] drag dock side=%ld nubbed=%d", (long)side, self.nubbed);
    }
}

- (void)handleTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || self.window.hidden || self.keyboardVisible || self.dragging) return;
    NSLog(@"[MetisKeyboard][KbdHandle] handle tapped");
    if (self.panelOpen) [self closePanel:YES];
    else [self openPanel];
}

- (void)outsideInteractionOnBackdrop:(UIView *)backdrop {
    if (!NSThread.isMainThread || backdrop != self.backdrop || !self.window || self.window.hidden ||
        backdrop.hidden || !self.panelOpen || self.keyboardVisible || self.dragging) return;
    // 主动操作面板外部即立即缩边，独立于可选的静置自动隐藏开关。
    [self cancelAutoHideTimer];
    self.nubbed = YES;
    [self saveHandlePlacement];
    [self closePanel:YES];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
        animations:^{ [self layoutForBounds:self.window.bounds]; } completion:nil];
    NSLog(@"[MetisKeyboard][KbdHandle] outside interaction close panel tuck=1");
}

- (void)openPanel {
    if (!self.window || self.window.hidden || self.keyboardVisible || self.dragging) return;
    if (self.nubbed) {
        self.nubbed = NO;
        [self saveHandlePlacement];
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            [self layoutForBounds:self.window.bounds];
        } completion:nil];
    }
    if (self.quickEnabled) { [self openQuickLauncher]; return; }
    [self rebuildPanel];
    if (self.panelItems.count == 0) {
        NSLog(@"[MetisKeyboard][KbdHandle] panel skipped empty");
        return;
    }
    // 面板使用中不整体隐藏；closePanel 收起后重新计时。
    [self cancelAutoHideTimer];
    self.panelGeneration++;
    [self.panelView.layer removeAllAnimations];
    self.panelView.transform = CGAffineTransformIdentity;
    self.panelOpen = YES;
    self.backdrop.hidden = NO;
    self.backdrop.alpha = 0;
    self.panelView.hidden = NO;
    self.panelView.alpha = 0;
    self.panelView.transform = CGAffineTransformMakeScale(0.92, 0.92);
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.panelView.alpha = 1;
        self.panelView.transform = CGAffineTransformIdentity;
        self.backdrop.alpha = 1;
    } completion:nil];
    NSLog(@"[MetisKeyboard][KbdHandle] panel opened items=%lu pinned=%d", (unsigned long)self.panelItems.count,
        self.selectedIdentifiers.count > 0);
}

- (void)closePanel:(BOOL)animated {
    if (!self.panelOpen && animated) return;
    NSUInteger generation = ++self.panelGeneration;
    self.panelOpen = NO;
    [self.quickView endSession]; self.quickView.hidden = YES;
    void (^finish)(void) = ^{
        if (self.panelGeneration != generation || self.panelOpen) return;
        [self.panelView.layer removeAllAnimations];
        self.panelView.hidden = YES;
        self.backdrop.hidden = YES;
        self.backdrop.alpha = 0;
        self.panelView.alpha = 0;
        self.panelView.transform = CGAffineTransformIdentity;
    };
    if (animated) {
        [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.panelView.alpha = 0;
            self.panelView.transform = CGAffineTransformMakeScale(0.92, 0.92);
            self.backdrop.alpha = 0;
        } completion:^(__unused BOOL done) { finish(); }];
    } else {
        finish();
    }
    // 面板收起把手仍在屏幕上：静止计时重新开始。隐藏路径（hideHandleWithReason）
    // 会在其后再次 cancelAutoHideTimer，不会残留空转定时器。
    [self armAutoHideTimer];
}

// Each opening freezes favorites and recents; the legacy rail keeps its original ordering.
- (void)openQuickLauncher {
    if (!self.quickView) {
        self.quickView = [[MTQuickLauncherView alloc] initWithFrame:CGRectZero];
        self.quickView.hidden = YES;
        __weak typeof(self) weakSelf = self;
        self.quickView.closeHandler = ^{ [weakSelf closePanel:YES]; };
        self.quickView.selectHandler = ^(NSString *identifier) { [weakSelf launchQuickIdentifier:identifier]; };
        [self.window insertSubview:self.quickView belowSubview:self.handleView];
    }
    NSMutableArray *favorites = [NSMutableArray array];
    id order = self.launcherPreferences[kKbdLauncherOrderKey];
    if ([order isKindOfClass:NSArray.class]) for (id identifier in order) {
        if ([identifier isKindOfClass:NSString.class] && [self.selectedIdentifiers containsObject:identifier] &&
            ![favorites containsObject:identifier]) [favorites addObject:identifier];
    }
    NSArray *sorted = [self.selectedIdentifiers sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult name = [MTKbdHandleDisplayName(a) localizedStandardCompare:MTKbdHandleDisplayName(b)];
        return name == NSOrderedSame ? [a compare:b] : name;
    }];
    for (NSString *identifier in sorted) if (![favorites containsObject:identifier]) [favorites addObject:identifier];
    for (NSString *identifier in self.recentIdentifiers) {
        if (favorites.count >= 6) break;
        if (![favorites containsObject:identifier]) [favorites addObject:identifier];
    }
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (NSString *identifier in favorites) names[identifier] = MTKbdHandleDisplayName(identifier);
    id aliases = self.launcherPreferences[kKbdLauncherAliasesKey], usage = self.launcherPreferences[kKbdLauncherUsageKey];
    [self.quickView beginWithFavorites:favorites names:names
        aliases:[aliases isKindOfClass:NSDictionary.class] ? aliases : @{}
        usage:[usage isKindOfClass:NSDictionary.class] ? usage : @{}];
    self.quickView.launching = self.launchPending;
    [self cancelAutoHideTimer]; self.panelGeneration++; self.panelOpen = YES;
    self.backdrop.hidden = NO; self.backdrop.alpha = 1; self.panelView.hidden = YES;
    self.quickView.hidden = NO; [self layoutForBounds:self.window.bounds];
    NSLog(@"[MetisKeyboard][Launcher] session opened favorites=%lu", (unsigned long)favorites.count);
}

- (void)recordQuickSuccess:(NSString *)identifier {
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    id raw = manager.readPrefs[kKbdLauncherUsageKey];
    NSMutableDictionary *usage = [raw isKindOfClass:NSDictionary.class] ? [raw mutableCopy] : [NSMutableDictionary dictionary];
    id previous = usage[identifier];
    id count = [previous isKindOfClass:NSDictionary.class] ? previous[@"count"] : nil;
    double number = [count isKindOfClass:NSNumber.class] ? [count doubleValue] : 0;
    if (!isfinite(number)) number = 0;
    usage[identifier] = @{@"count": @(MIN(1000000, MAX(0, number) + 1)), @"last": @(NSDate.date.timeIntervalSince1970)};
    // Bound persistent ranking data. Entries use only bundle IDs and successful-use metadata.
    if (usage.count > 256) {
        NSArray *keys = [usage.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            id ar = usage[a], br = usage[b];
            id av = [ar isKindOfClass:NSDictionary.class] ? ar[@"last"] : nil;
            id bv = [br isKindOfClass:NSDictionary.class] ? br[@"last"] : nil;
            double at = [av isKindOfClass:NSNumber.class] ? [av doubleValue] : 0;
            double bt = [bv isKindOfClass:NSNumber.class] ? [bv doubleValue] : 0;
            return at < bt ? NSOrderedAscending : at > bt ? NSOrderedDescending : [a compare:b];
        }];
        for (NSUInteger i = 0; i < keys.count - 256; i++) [usage removeObjectForKey:keys[i]];
    }
    [manager setValue:usage forKey:kKbdLauncherUsageKey];
}

- (void)launchQuickIdentifier:(NSString *)identifier {
    if (!NSThread.isMainThread || !self.quickEnabled || !self.panelOpen || self.window.hidden ||
        self.keyboardVisible || self.dragging || self.launchPending || !MTIsValidBundleIdentifier(identifier)) return;
    self.launchPending = YES; self.quickView.launching = YES;
    NSUInteger generation = self.panelGeneration, request = ++self.launchRequest;
    __weak typeof(self) weakSelf = self;
    MTOpenFloatingApplication(identifier, ^(MTSystemOpenResult result) {
        MTKbdCollapseHandle *host = weakSelf;
        if (!host || host.launchRequest != request || !host.launchPending) return;
        host.launchPending = NO; host.quickView.launching = NO;
        if (result == MTSystemOpenSucceeded) [host recordQuickSuccess:identifier];
        NSLog(@"[MetisKeyboard][Launcher] open completed request=%lu result=%llu", (unsigned long)request, (unsigned long long)result);
        if (!host.panelOpen || host.panelGeneration != generation || host.window.hidden) return;
        if (result == MTSystemOpenSucceeded) [host closePanel:YES];
        else [host.quickView showOpenFailure];
    });
}

- (void)rebuildPanel {
    if (!self.panelView) return;
    self.panelItems = [self panelIdentifiers];
    for (UIButton *button in self.panelButtons) [button removeFromSuperview];
    [self.panelButtons removeAllObjects];
    NSUInteger count = self.panelItems.count;
    CGFloat side = MTKbdPanelTileSide;
    CGFloat tileX = MAX(0, (CGRectGetWidth(self.panelView.bounds) - side) / 2);
    for (NSUInteger index = 0; index < count; index++) {
        NSString *identifier = [self.panelItems objectAtIndex:index];
        if (![identifier isKindOfClass:[NSString class]]) continue;
        // 瓦片与把手同款：34pt SystemThinMaterial、8pt 连续圆角、同阴影参数，
        // 图标内缩 5pt 显示 24pt（PullOver-X POAppRailTile 的比例）。
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(tileX, index * (side + MTKbdPanelTileGap), side, side);
        button.layer.cornerRadius = MTKbdHandleCornerRadius;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        button.layer.shadowColor = [UIColor blackColor].CGColor;
        button.layer.shadowOpacity = 0.25;
        button.layer.shadowRadius = 6;
        button.layer.shadowOffset = CGSizeMake(0, 2);
        button.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:button.bounds
                                                                cornerRadius:MTKbdHandleCornerRadius].CGPath;
        UIVisualEffectView *material = [[UIVisualEffectView alloc]
            initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        material.frame = button.bounds;
        material.layer.cornerRadius = MTKbdHandleCornerRadius;
        material.layer.cornerCurve = kCACornerCurveContinuous;
        material.clipsToBounds = YES;
        material.userInteractionEnabled = NO;
        UIImageView *iconView = [[UIImageView alloc] initWithImage:MTKbdHandleApplicationIcon(identifier)];
        iconView.frame = UIEdgeInsetsInsetRect(material.bounds,
            UIEdgeInsetsMake(MTKbdHandleIconInset, MTKbdHandleIconInset, MTKbdHandleIconInset, MTKbdHandleIconInset));
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.clipsToBounds = YES;
        [material.contentView addSubview:iconView];
        [button addSubview:material];
        button.accessibilityLabel = MTKbdHandleDisplayName(identifier);
        button.tag = (NSInteger)index;
        [button addTarget:self action:@selector(appButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.panelView addSubview:button];
        [self.panelButtons addObject:button];
    }
    // 面板高度随条目数变化，重建后立刻按当前内容重排。
    if (self.window && !self.window.hidden) [self layoutForBounds:self.window.bounds];
}

- (void)appButtonTapped:(UIButton *)button {
    if (!self.panelOpen || self.window.hidden || self.keyboardVisible || self.dragging) return;
    NSUInteger index = (NSUInteger)button.tag;
    if (index >= self.panelItems.count) return;  // 陈旧点击：面板可能已按新列表重建
    NSString *identifier = [self.panelItems objectAtIndex:index];
    if (![identifier isKindOfClass:[NSString class]]) return;
    NSLog(@"[MetisKeyboard][KbdHandle] panel open bundleID=%@", identifier);
    [self closePanel:YES];
    // 目标切换语义由 MTFloatingAppCoordinator.open 承接：同 App 短路，不同 App
    // 走 target-switch 收旧开新，悬浮卡只剩一个。截止时间由 open 通道自建。
    MTOpenFloatingApplication(identifier, ^(MTSystemOpenResult result) {
        NSLog(@"[MetisKeyboard][KbdHandle] float result=%llu bundleID=%@", (unsigned long long)result, identifier);
    });
}

@end

#pragma mark - 进程入口

void MTStartKbdCollapseHandle(void) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
    [[MTKbdCollapseHandle shared] start];
}

void MTKbdCollapseHandleDesktopDidAppear(void) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
    [[MTKbdCollapseHandle shared] handleEnvironmentChange:@"desktop"];
}

void MTKbdCollapseHandleNoteFloated(NSString *bundleIdentifier) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
    [[MTKbdCollapseHandle shared] noteFloated:bundleIdentifier];
}
