// 快速面板宿主：解锁亮屏时由系统动作（「快速面板」）按需唤出 MTQuickLauncherView
// （常用应用 + 九键搜索全量应用）；常用应用与排序见 kKbdHandleAppsKey/kKbdLauncherOrderKey，
// 空位补最近悬浮 App。面板可拖动摆放（落盘归一化坐标），双击小横条或设置内
// 「恢复默认位置」回到 kbdlauncherside 决定的贴边默认位。锁屏、息屏、前台切换、
// 回桌面时收起；最近列表由悬浮会话转 Live 时喂入（SpringBoard 重启后清空）。

#import "MTQuickPanelHost.h"
#import "MTQuickLauncherView.h"
#import "MTQuickLauncherLayout.h"
#import "MTDarwinOpenChannel.h"
#import "MTSystemOpenBroker.h"
#import "MTGlobalPanel.h"
#import "MTModuleGate.h"
#import "common.h"
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <string.h>

static BOOL MTQuickPanelScreenIsOn(void) {
    int token = NOTIFY_TOKEN_INVALID;
    uint64_t blanked = 1;
    if (notify_register_check("com.apple.springboard.hasBlankedScreen", &token) != NOTIFY_STATUS_OK) return NO;
    BOOL read = notify_get_state(token, &blanked) == NOTIFY_STATUS_OK;
    notify_cancel(token);
    return read && blanked == 0;
}

// 独立背景层的跨进程命中与悬浮卡同源：WindowServer 先按渲染图层选触摸，透明
// 边界必须显式参与命中；不支持的系统回退 3% 实际绘制遮罩。
static BOOL MTQuickPanelConfigureBackdropHitTesting(id layer) {
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

static id MTQuickPanelObjectValue(id object, NSString *methodName) {
    if (!object) return nil;
    SEL selector = NSSelectorFromString(methodName);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (![object respondsToSelector:selector] || !signature || signature.numberOfArguments != 2 ||
        strcmp(signature.methodReturnType, "@")) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}

static NSString *MTQuickPanelDisplayName(NSString *bundleIdentifier) {
    id controller = MTQuickPanelObjectValue(NSClassFromString(@"SBApplicationController"), @"sharedInstance");
    id application = nil;
    if ([controller respondsToSelector:@selector(applicationWithBundleIdentifier:)]) {
        @try {
            application = ((id (*)(id, SEL, id))objc_msgSend)(controller,
                @selector(applicationWithBundleIdentifier:), bundleIdentifier);
        } @catch (__unused NSException *exception) {}
    }
    id name = MTQuickPanelObjectValue(application, @"displayName");
    return [name isKindOfClass:[NSString class]] && [name length] > 0 ? name : bundleIdentifier;
}

@class MTQuickPanelWindow;

@interface MTQuickPanelHost : NSObject
@property(nonatomic, strong) MTQuickPanelWindow *window;
@property(nonatomic, strong) UIView *backdrop;
@property(nonatomic, strong) MTQuickLauncherView *quickView;
@property(nonatomic) BOOL launchPending;
@property(nonatomic) NSUInteger launchRequest;
@property(nonatomic, copy) NSDictionary *launcherPreferences;
@property(nonatomic) NSInteger launcherSide;
@property(nonatomic) double launcherScale;
// 面板拖动摆放：已摆放标记 + 归一化中心点（0~1）；拖动中为绝对中心点。
@property(nonatomic) BOOL launcherPlaced;
@property(nonatomic) CGPoint launcherCenter;
@property(nonatomic) BOOL launcherDragging;
@property(nonatomic) CGPoint launcherDragCenter;
@property(nonatomic) CGPoint launcherDragStartCenter;
@property(nonatomic) CGPoint launcherDragBaseCenter;
@property(nonatomic) BOOL launcherDragStartPlaced;
@property(nonatomic) BOOL launcherSideApplied;
@property(nonatomic) CGRect lastLayoutBounds;
@property(nonatomic, strong) NSMutableArray<NSString *> *recentIdentifiers;
@property(nonatomic, copy) NSArray<NSString *> *selectedIdentifiers;
@property(nonatomic) BOOL startupReady;
@property(nonatomic, strong) id launchObserver;
@property(nonatomic) NSUInteger panelGeneration;
@property(nonatomic) BOOL panelOpen;
@property(nonatomic) BOOL started;
+ (instancetype)shared;
- (void)start;
- (void)finishStartup;
- (void)handleEnvironmentChange:(NSString *)reason;
- (void)applyPreferences;
- (BOOL)presentQuickPanel;
- (void)closePanel:(BOOL)animated;
- (void)openQuickLauncher;
- (void)noteFloated:(NSString *)bundleIdentifier;
- (void)layoutForBounds:(CGRect)bounds;
- (void)applyLauncherDragPhase:(MTQuickLauncherDragPhase)phase translation:(CGPoint)translation;
- (void)cancelLauncherDrag;
- (void)resetLauncherPlacement;
- (void)saveLauncherPlacement:(BOOL)placed;
- (void)outsideInteractionOnBackdrop:(UIView *)backdrop;
@end

// 在落指时消费面板外的整段触摸，不等待点按/滑动/长按识别结果。
@interface MTQuickPanelBackdropView : UIView
@property(nonatomic, weak) MTQuickPanelHost *manager;
@end

@implementation MTQuickPanelBackdropView
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(__unused UIEvent *)event {
    if (touches.count > 0) [self.manager outsideInteractionOnBackdrop:self];
}
@end

@interface MTQuickPanelWindow : UIWindow
@property(nonatomic, weak) MTQuickPanelHost *manager;
@end

@implementation MTQuickPanelWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (bool)_shouldCreateContextAsSecure { return YES; }
- (void)layoutSubviews {
    [super layoutSubviews];
    [self.manager layoutForBounds:self.bounds];
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = [super hitTest:point withEvent:event];
    if (self.hidden) return result == (UIView *)self ? nil : result;
    // 面板打开：面板之外的任何落点一律定向给背景层（落指即收起）。
    // 不依赖背景层自身命中，窗口层直接定向，透明路由失效时也收得起。
    if (self.manager.panelOpen) {
        CGRect panel = self.manager.quickView.frame;
        if (!CGRectContainsPoint(panel, point))
            return self.manager.backdrop;
    }
    // 空白区域穿透给宿主 App/SpringBoard；只有面板与打开态背景层接收触摸。
    return result == (UIView *)self ? nil : result;
}
@end

@implementation MTQuickPanelHost
+ (instancetype)shared {
    static MTQuickPanelHost *host;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ host = [self new]; });
    return host;
}

- (void)start {
    if (self.started) return;
    self.started = YES;
    self.recentIdentifiers = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    int token = NOTIFY_TOKEN_INVALID;
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
    // 观察者会把 startupReady 永远留在 NO、面板永不弹出。finishStartup
    // 幂等：与 SMS/浏览器重定向一致「ctor 同步先跑 + 通知兜底」，块若
    // 确实早于通知执行也走同一路径，观察者保留作双保险。
    [self finishStartup];
    NSLog(@"[MetisKeyboard][QuickPanel] host started");
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

// 锁屏/息屏/前台切换/回桌面：结束拖动并收起面板；锁屏、息屏时连窗口一起收掉，
// 解锁亮屏后由系统动作按需重新唤出。
- (void)handleEnvironmentChange:(NSString *)reason {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self handleEnvironmentChange:reason]; }); return; }
    [self closePanel:NO];
    if (![MTModuleGate globalEnabled] || ![MTGlobalPanel deviceUnlocked] || !MTQuickPanelScreenIsOn()) {
        if (self.window) self.window.hidden = YES;
    }
}

- (void)applyPreferences {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self applyPreferences]; }); return; }
    [[MTPrefsManager sharedInstance] reload];
    MTPrefsManager *manager = [MTPrefsManager sharedInstance];
    NSDictionary *preferences = manager.preferencesAvailable ? manager.readPrefs : nil;
    // 拖动中不接受外部配置覆盖，避免面板在手指下跳走。
    if (!self.launcherDragging) {
        self.launcherPlaced = MTKbdLauncherPlacedFromPreferences(preferences);
        self.launcherCenter = MTKbdLauncherOriginFromPreferences(preferences);
    }
    NSInteger side = MTKbdLauncherSideFromPreferences(preferences);
    // 设置里改了停靠侧：拖动摆放位作废回到默认贴边位，否则该项成了死选项。
    if (self.launcherSideApplied && side != self.launcherSide && self.launcherPlaced && !self.launcherDragging) {
        self.launcherPlaced = NO;
        self.launcherCenter = CGPointMake(0.5, 0.5);
        [self saveLauncherPlacement:NO];
    }
    self.launcherSide = side;
    self.launcherSideApplied = YES;
    self.launcherScale = MTKbdLauncherScaleFromPreferences(preferences);
    // 面板数据源或停靠侧变化时收起旧会话，下次唤出按新配置重开。
    BOOL launcherChanged = NO;
    for (NSString *key in @[kKbdHandleAppsKey, kKbdLauncherOrderKey, kKbdLauncherAliasesKey, kKbdLauncherSideKey]) {
        id previous = self.launcherPreferences[key] ?: NSNull.null, current = preferences[key] ?: NSNull.null;
        if (![previous isEqual:current]) launcherChanged = YES;
    }
    if (self.panelOpen && launcherChanged) [self closePanel:NO];
    self.launcherPreferences = [preferences copy] ?: @{};
    self.selectedIdentifiers = MTKbdHandleAppsFromPreferences(preferences);
    if (self.window && !self.window.hidden) [self layoutForBounds:self.window.bounds];
}

- (void)noteFloated:(NSString *)bundleIdentifier {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self noteFloated:bundleIdentifier]; }); return; }
    if (!MTIsValidBundleIdentifier(bundleIdentifier)) return;
    if (!self.recentIdentifiers) self.recentIdentifiers = [NSMutableArray array];
    [self.recentIdentifiers removeObject:bundleIdentifier];
    [self.recentIdentifiers insertObject:bundleIdentifier atIndex:0];
    while (self.recentIdentifiers.count > (NSUInteger)kKbdCollapsePanelCapacity) [self.recentIdentifiers removeLastObject];
}

#pragma mark - 窗口与视图

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
        NSLog(@"[MetisKeyboard][QuickPanel] window scene unavailable");
        return;
    }
    MTQuickPanelWindow *window = [[MTQuickPanelWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.backgroundColor = [UIColor clearColor];
    // 悬浮卡(level 100)之上：面板能盖住已打开的悬浮卡完成切换；alert 级保证
    // 触摸路由先于宿主 App 窗口。面板按需唤出，窗口平时隐藏。
    window.windowLevel = UIWindowLevelAlert + 1;
    window.manager = self;
    window.hidden = YES;

    MTQuickPanelBackdropView *backdrop = [[MTQuickPanelBackdropView alloc] initWithFrame:window.bounds];
    backdrop.manager = self;
    self.backdrop = backdrop;
    self.backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // 面板打开态的轻遮罩：可见像素保证 WindowServer 把外部触摸路由进本窗口
    // （透明层在渲染端可能不参与跨进程命中，外部点按到不了收起手势，正是
    // 「点外部收不起面板」的根因）；私有点击层标志仍照设作双保险。
    self.backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.04];
    self.backdrop.hidden = YES;
    self.backdrop.alpha = 0;
    BOOL hitTestingConfigured = MTQuickPanelConfigureBackdropHitTesting(self.backdrop.layer);
    [window addSubview:self.backdrop];

    self.quickView = [[MTQuickLauncherView alloc] initWithFrame:CGRectZero];
    self.quickView.hidden = YES;
    __weak typeof(self) weakSelf = self;
    self.quickView.closeHandler = ^{ [weakSelf closePanel:YES]; };
    self.quickView.selectHandler = ^(NSString *identifier) { [weakSelf launchQuickIdentifier:identifier]; };
    self.quickView.dragHandler = ^(MTQuickLauncherDragPhase phase, CGPoint translation) {
        [weakSelf applyLauncherDragPhase:phase translation:translation];
    };
    self.quickView.resetHandler = ^{ [weakSelf resetLauncherPlacement]; };
    [window addSubview:self.quickView];

    self.window = window;
    NSLog(@"[MetisKeyboard][QuickPanel] window created backdropRouting=%d", hitTestingConfigured);
}

- (void)layoutForBounds:(CGRect)bounds {
    if (!self.window || !self.quickView || bounds.size.width < 1 || bounds.size.height < 1) return;
    UIEdgeInsets safe = self.window.safeAreaInsets;
    if (!CGRectIsEmpty(self.lastLayoutBounds) && !CGRectEqualToRect(bounds, self.lastLayoutBounds) && self.panelOpen) [self closePanel:NO];
    self.lastLayoutBounds = bounds;
    CGRect quickFrame;
    // 拖动中即使尚未标记「已摆放」也要跟手，落盘后按摆放位还原。
    if (self.launcherPlaced || self.launcherDragging) {
        // 拖动摆放位：以归一化中心点定位，落点夹在安全区内的可用区里。
        CGRect available = MTQuickLauncherAvailableRect(bounds, safe.top, safe.left, safe.bottom, safe.right);
        CGSize size = MTQuickLauncherDisplayedSize(bounds, available, self.launcherScale);
        CGPoint normalized = self.launcherDragging
            ? MTQuickLauncherNormalizedCenter(available, size, self.launcherDragCenter) : self.launcherCenter;
        quickFrame = MTQuickLauncherPlacedFrame(available, size, normalized);
    } else {
        // 停靠侧由设置决定（kbdlauncherside，默认靠右紧贴右缘）。
        quickFrame = MTQuickLauncherFrame(bounds, safe, self.launcherSide, self.launcherScale);
    }
    self.quickView.frame = quickFrame;
}

#pragma mark 面板拖动摆放

// 面板几何只由 layoutForBounds 写入；拖动期间由 dragCenter 驱动，落指后归一化落盘。
- (void)applyLauncherDragPhase:(MTQuickLauncherDragPhase)phase translation:(CGPoint)translation {
    if (!NSThread.isMainThread) {
        MTQuickLauncherDragPhase captured = phase;
        dispatch_async(dispatch_get_main_queue(), ^{ [self applyLauncherDragPhase:captured translation:translation]; });
        return;
    }
    if (phase == MTQuickLauncherDragBegan) {
        if (!self.window || self.window.hidden || !self.panelOpen || !self.quickView) { [self cancelLauncherDrag]; return; }
        self.launcherDragStartPlaced = self.launcherPlaced;
        self.launcherDragStartCenter = self.launcherCenter;
        self.launcherDragCenter = CGPointMake(CGRectGetMidX(self.quickView.frame), CGRectGetMidY(self.quickView.frame));
        self.launcherDragBaseCenter = self.launcherDragCenter;
        self.launcherDragging = YES;
        return;
    }
    if (!self.launcherDragging) return;
    if (phase == MTQuickLauncherDragCancelled || !isfinite(translation.x) || !isfinite(translation.y)) {
        [self cancelLauncherDrag]; return;
    }
    self.launcherDragCenter = CGPointMake(self.launcherDragCenter.x + translation.x,
                                          self.launcherDragCenter.y + translation.y);
    if (phase == MTQuickLauncherDragChanged) { [self layoutForBounds:self.window.bounds]; return; }
    // 双击复位等原地微动不应把面板标记为「已摆放」，未越过阈值按取消回滚。
    CGFloat movedX = self.launcherDragCenter.x - self.launcherDragBaseCenter.x;
    CGFloat movedY = self.launcherDragCenter.y - self.launcherDragBaseCenter.y;
    if (!(hypot(movedX, movedY) >= 4.0)) { [self cancelLauncherDrag]; return; }
    // 落指：先归一化落盘，再动画贴回夹取后的最终位置。
    self.launcherDragging = NO;
    [self saveLauncherPlacement:YES];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
        animations:^{ [self layoutForBounds:self.window.bounds]; } completion:nil];
    NSLog(@"[MetisKeyboard][Launcher] panel placed at %.2f,%.2f", self.launcherCenter.x, self.launcherCenter.y);
}

// 打断拖动（锁屏、前台切换、面板关闭）：回滚到起手位置，不写回半途坐标。
- (void)cancelLauncherDrag {
    [self.quickView cancelDrag];
    if (!self.launcherDragging) return;
    self.launcherDragging = NO;
    self.launcherPlaced = self.launcherDragStartPlaced;
    self.launcherCenter = self.launcherDragStartCenter;
    if (self.window && !self.window.hidden && self.panelOpen) [self layoutForBounds:self.window.bounds];
}

- (void)resetLauncherPlacement {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self resetLauncherPlacement]; }); return; }
    [self cancelLauncherDrag];
    if (!self.launcherPlaced) return;
    self.launcherPlaced = NO;
    self.launcherCenter = CGPointMake(0.5, 0.5);
    [self saveLauncherPlacement:NO];
    if (self.panelOpen && self.window && !self.window.hidden) {
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
            animations:^{ [self layoutForBounds:self.window.bounds]; } completion:nil];
    }
    NSLog(@"[MetisKeyboard][Launcher] panel placement reset");
}

- (void)saveLauncherPlacement:(BOOL)placed {
    CGRect available = CGRectZero;
    CGSize size = CGSizeZero;
    if (self.window && !CGRectIsEmpty(self.window.bounds)) {
        UIEdgeInsets safe = self.window.safeAreaInsets;
        available = MTQuickLauncherAvailableRect(self.window.bounds, safe.top, safe.left, safe.bottom, safe.right);
        size = MTQuickLauncherDisplayedSize(self.window.bounds, available, self.launcherScale);
    }
    CGPoint normalized = (placed && size.width > 0 && size.height > 0)
        ? MTQuickLauncherNormalizedCenter(available, size, self.launcherDragCenter) : CGPointMake(0.5, 0.5);
    self.launcherCenter = normalized;
    self.launcherPlaced = placed;
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    [manager reload];
    NSDictionary *preferences = manager.preferencesAvailable ? manager.readPrefs : nil;
    if (![preferences isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary *updated = [preferences mutableCopy];
    updated[kKbdLauncherPlacedKey] = @(placed);
    updated[kKbdLauncherOriginXKey] = @(normalized.x);
    updated[kKbdLauncherOriginYKey] = @(normalized.y);
    [manager writePrefs:updated];
}

#pragma mark 面板显隐

// 系统动作入口：按需建窗并唤出面板，不依赖键盘显隐。
- (BOOL)presentQuickPanel {
    if (!NSThread.isMainThread || !self.startupReady || ![MTModuleGate globalEnabled] ||
        ![MTGlobalPanel deviceUnlocked] || !MTQuickPanelScreenIsOn()) return NO;
    if (self.panelOpen && self.window && !self.window.hidden) return YES;
    [self applyPreferences];
    [self cancelLauncherDrag];
    [self closePanel:NO];
    [self createWindowIfNeeded];
    if (!self.window) return NO;
    [MTGlobalPanel.sharedInstance dismiss];
    self.window.hidden = NO;
    [self openQuickLauncher];
    NSLog(@"[MetisKeyboard][Launcher] quick panel opened");
    return self.panelOpen && !self.window.hidden;
}

- (void)closePanel:(BOOL)animated {
    if (!self.panelOpen) return;
    // 任何收起路径都先结束进行中的拖动，避免残留手势或半途坐标。
    [self cancelLauncherDrag];
    NSUInteger generation = ++self.panelGeneration;
    self.panelOpen = NO;
    [self.quickView endSession]; self.quickView.hidden = YES;
    void (^finish)(void) = ^{
        if (self.panelGeneration != generation || self.panelOpen) return;
        self.backdrop.hidden = YES;
        self.backdrop.alpha = 0;
        // 窗口只服务面板：收起即隐藏，下次唤出重建可见性。
        self.window.hidden = YES;
    };
    if (animated) {
        [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.backdrop.alpha = 0;
        } completion:^(__unused BOOL done) { finish(); }];
    } else {
        finish();
    }
}

- (void)outsideInteractionOnBackdrop:(UIView *)backdrop {
    if (!NSThread.isMainThread || backdrop != self.backdrop || !self.window || self.window.hidden ||
        backdrop.hidden || !self.panelOpen) return;
    // 主动操作面板外部即收起。
    [self closePanel:YES];
    NSLog(@"[MetisKeyboard][QuickPanel] outside interaction close panel");
}

// 使用频率推荐排序：成功启动次数多的在前，同次数按最近一次启动时间新的在前；
// 从未启动过的排到最后并保持传入顺序（手动排序 → 名称），让常用位先给用过的 App。
- (NSArray<NSString *> *)rankedIdentifiers:(NSArray<NSString *> *)identifiers byUsage:(id)usage {
    if (![identifiers isKindOfClass:NSArray.class]) return @[];
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *lasts = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *ranks = [NSMutableDictionary dictionary];
    [identifiers enumerateObjectsUsingBlock:^(NSString *identifier, NSUInteger index, __unused BOOL *stop) {
        ranks[identifier] = @(index);
    }];
    if ([usage isKindOfClass:NSDictionary.class]) for (id key in (NSDictionary *)usage) {
        if (![key isKindOfClass:NSString.class]) continue;
        id record = ((NSDictionary *)usage)[key];
        if (![record isKindOfClass:NSDictionary.class]) continue;
        id count = record[@"count"], last = record[@"last"];
        double value = [count respondsToSelector:@selector(doubleValue)] ? [count doubleValue] : 0;
        double stamp = [last respondsToSelector:@selector(doubleValue)] ? [last doubleValue] : 0;
        if (isfinite(value) && value > 0) counts[(NSString *)key] = @(value);
        if (isfinite(stamp) && stamp > 0) lasts[(NSString *)key] = @(stamp);
    }
    return [identifiers sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        double countA = [counts[a] doubleValue], countB = [counts[b] doubleValue];
        if ((countA > 0) != (countB > 0)) return countA > 0 ? NSOrderedAscending : NSOrderedDescending;
        if (countA > 0) {
            if (countA != countB) return countA > countB ? NSOrderedAscending : NSOrderedDescending;
            double lastA = [lasts[a] doubleValue], lastB = [lasts[b] doubleValue];
            if (lastA != lastB) return lastA > lastB ? NSOrderedAscending : NSOrderedDescending;
        }
        NSComparisonResult order = [ranks[a] compare:ranks[b]];
        return order == NSOrderedSame ? [a compare:b] : order;
    }];
}

// 每次打开冻结常用应用与最近悬浮快照；面板停靠侧由 kbdlauncherside 决定。
- (void)openQuickLauncher {
    if (!self.quickView) return;
    // 基准顺序：手动排序优先，其后按名称兜底空出来的条目（写入侧与设置页同源）。
    NSMutableArray *favorites = [NSMutableArray array];
    id order = self.launcherPreferences[kKbdLauncherOrderKey];
    if ([order isKindOfClass:NSArray.class]) for (id identifier in order) {
        if ([identifier isKindOfClass:NSString.class] && [self.selectedIdentifiers containsObject:identifier] &&
            ![favorites containsObject:identifier]) [favorites addObject:identifier];
    }
    NSArray *sorted = [self.selectedIdentifiers sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult name = [MTQuickPanelDisplayName(a) localizedStandardCompare:MTQuickPanelDisplayName(b)];
        return name == NSOrderedSame ? [a compare:b] : name;
    }];
    for (NSString *identifier in sorted) if (![favorites containsObject:identifier]) [favorites addObject:identifier];
    favorites = [[self rankedIdentifiers:favorites byUsage:self.launcherPreferences[kKbdLauncherUsageKey]] mutableCopy];
    for (NSString *identifier in self.recentIdentifiers) {
        if (favorites.count >= 6) break;
        if (![favorites containsObject:identifier]) [favorites addObject:identifier];
    }
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (NSString *identifier in favorites) names[identifier] = MTQuickPanelDisplayName(identifier);
    id aliases = self.launcherPreferences[kKbdLauncherAliasesKey], usage = self.launcherPreferences[kKbdLauncherUsageKey];
    [self.quickView beginWithFavorites:favorites names:names
        aliases:[aliases isKindOfClass:NSDictionary.class] ? aliases : @{}
        usage:[usage isKindOfClass:NSDictionary.class] ? usage : @{}];
    self.quickView.launching = self.launchPending;
    self.panelGeneration++; self.panelOpen = YES;
    self.backdrop.hidden = NO; self.backdrop.alpha = 1;
    self.quickView.hidden = NO; [self layoutForBounds:self.window.bounds];
    NSLog(@"[MetisKeyboard][Launcher] session opened favorites=%lu side=%ld", (unsigned long)favorites.count, (long)self.launcherSide);
}

- (void)recordQuickSuccess:(NSString *)identifier {
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    id raw = manager.readPrefs[kKbdLauncherUsageKey];
    NSMutableDictionary *usage = [raw isKindOfClass:NSDictionary.class] ? [raw mutableCopy] : [NSMutableDictionary dictionary];
    id previous = usage[identifier];
    id count = [previous isKindOfClass:NSDictionary.class] ? previous[@"count"] : nil;
    double number = [count isKindOfClass:[NSNumber class]] ? [count doubleValue] : 0;
    if (!isfinite(number)) number = 0;
    usage[identifier] = @{@"count": @(MIN(1000000, MAX(0, number) + 1)), @"last": @(NSDate.date.timeIntervalSince1970)};
    // Bound persistent ranking data. Entries use only bundle IDs and successful-use metadata.
    if (usage.count > 256) {
        NSArray *keys = [usage.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            id ar = usage[a], br = usage[b];
            id av = [ar isKindOfClass:NSDictionary.class] ? ar[@"last"] : nil;
            id bv = [br isKindOfClass:NSDictionary.class] ? br[@"last"] : nil;
            double at = [av isKindOfClass:[NSNumber class]] ? [av doubleValue] : 0;
            double bt = [bv isKindOfClass:[NSNumber class]] ? [bv doubleValue] : 0;
            return at < bt ? NSOrderedAscending : at > bt ? NSOrderedDescending : [a compare:b];
        }];
        for (NSUInteger i = 0; i < keys.count - 256; i++) [usage removeObjectForKey:keys[i]];
    }
    [manager setValue:usage forKey:kKbdLauncherUsageKey];
}

- (void)launchQuickIdentifier:(NSString *)identifier {
    if (!NSThread.isMainThread || !self.panelOpen || self.window.hidden ||
        self.launcherDragging || self.launchPending || !MTIsValidBundleIdentifier(identifier)) return;
    self.launchPending = YES; self.quickView.launching = YES;
    NSUInteger request = ++self.launchRequest;
    // Release the panel before dispatch, including cold launches and failures.
    [self closePanel:NO];
    __weak typeof(self) weakSelf = self;
    MTOpenFloatingApplication(identifier, ^(MTSystemOpenResult result) {
        MTQuickPanelHost *host = weakSelf;
        if (!host || host.launchRequest != request || !host.launchPending) return;
        host.launchPending = NO; host.quickView.launching = NO;
        if (result == MTSystemOpenSucceeded) [host recordQuickSuccess:identifier];
        NSLog(@"[MetisKeyboard][Launcher] open completed request=%lu result=%llu", (unsigned long)request, (unsigned long long)result);
        // Completion must never close or reopen a subsequently presented panel.
    });
}

@end

#pragma mark - 进程入口

void MTStartQuickPanelHost(void) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
    [[MTQuickPanelHost shared] start];
}

void MTQuickPanelDesktopDidAppear(void) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
    [[MTQuickPanelHost shared] handleEnvironmentChange:@"desktop"];
}

void MTQuickPanelNoteFloated(NSString *bundleIdentifier) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
    [[MTQuickPanelHost shared] noteFloated:bundleIdentifier];
}

BOOL MTPresentQuickPanel(void) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return NO;
    MTQuickPanelHost *host = MTQuickPanelHost.shared;
    [host start];
    return [host presentQuickPanel];
}
