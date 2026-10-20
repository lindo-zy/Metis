#import "MTCornerGestures.h"
#import "MTCornerGesturePolicy.h"
#import "MTStatusBarGesturePolicy.h"
#import "MTSystemOpenBroker.h"
#import "MTGlobalPanel.h"
#import "MTGlobalPanelPolicy.h"
#import "MTKeyboardPanelPreferences.h"
#import "MTPanelRegistry.h"
#import "MTDockPanelTouchPolicy.h"
#import "common.h"
#import <objc/runtime.h>
#import <notify.h>

// 屏幕左下/右下角落上滑手势。识别器挂"覆盖整屏的常规层级窗口"（App 主窗与
// SpringBoard 主窗都满足），扇形命中与方向判定都在触摸回调里做；生命周期与
// 状态栏手势同源（窗口/Scene/前台通知 + prefschanged/lockstate 通知驱动，
// 每次回调先刷新再扫描补挂）。触发经 SystemOpenBroker corner-gesture 链路：
// App 内走 darwin RPC 转发 SpringBoard，SpringBoard 内短路直执，服务端统一
// 二次校验后再弹面板/执行动作。
//
// App 内可用性：屏幕底部通常被 Home 指示条系统手势区与 Tab bar 占用，因此扇形
// 锚点按 cornergestureBottomInset 抬起，锚点以下保留贴边的起手容错带（见
// MTCornerGesturePolicy.h）。完成门槛与方向比由灵敏度档位给出，快速甩动可在
// 位移不足时兜底；手势 begin 时给一次轻触觉，让用户知道这一划已被接住。
static char MTCornerHandlerKey, MTCornerRecognizerKey, MTCornerSessionKey;
static NSHashTable *MTCornerHandlers;
static void MTTryCornerHooks(void);

static BOOL MTCornerWindowEligible(UIWindow *window) {
    if (!window || window.hidden || window.alpha <= 0.01 || !window.userInteractionEnabled || !window.windowScene) return NO;
    NSString *name = NSStringFromClass(window.class);
    if ([name containsString:@"Keyboard"] || [name containsString:@"StatusBar"] || [name containsString:@"TextEffects"]) return NO;
    // 弹窗/键盘/状态栏等系统窗口都在高层级；角落扇形锚定屏幕底角，
    // 只应挂普通层级的整屏窗口，避免在弹窗上截胡角落触摸。
    if (window.windowLevel != UIWindowLevelNormal) return NO;
    return MTCornerGestureWindowMatchesBounds(window.frame, window.bounds, window.windowScene.coordinateSpace.bounds);
}

@interface MTCornerGestureSession : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, copy) NSString *digest;
@property(nonatomic, copy) NSString *region;
@property(nonatomic, copy) NSString *selector;
@property(nonatomic, assign) CGRect windowBounds;
@property(nonatomic, assign) MTCornerGestureMetrics metrics;
@property(nonatomic, assign) BOOL hapticEnabled;
@property(nonatomic) BOOL acknowledged;
@property(nonatomic) BOOL dispatched;
@end
@implementation MTCornerGestureSession @end

// 起手确认反馈：手势一旦 begin 就给一次极轻触觉，让用户知道这一划已经被接住，
// 不必靠「有没有弹出面板」反推自己是否按对了位置。
static UISelectionFeedbackGenerator *MTCornerSelectionFeedback(void) {
    static UISelectionFeedbackGenerator *generator;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ generator = [[UISelectionFeedbackGenerator alloc] init]; });
    return generator;
}

@interface MTCornerGestureHandler : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, strong) UIPanGestureRecognizer *pan;
@property(nonatomic, copy) NSString *lastRejection;
@property(nonatomic, copy) NSString *lastConfiguration;
- (BOOL)available;
- (BOOL)reject:(NSString *)reason;
- (BOOL)hasAction:(NSString *)region preferences:(NSDictionary *)preferences;
- (BOOL)sessionIsCurrent:(MTCornerGestureSession *)session;
- (void)refresh;
- (void)cornerPan:(UIPanGestureRecognizer *)gesture;
@end

@implementation MTCornerGestureHandler
- (BOOL)reject:(NSString *)reason {
    if (![self.lastRejection isEqual:reason])
        NSLog(@"[MetisKeyboard][CornerGesture] rejected host=%@ gate=%@", NSProcessInfo.processInfo.processName, reason);
    self.lastRejection = reason;
    return NO;
}
- (void)detach {
    UIWindow *window = _window;
    UIPanGestureRecognizer *pan = _pan;
    void (^remove)(void) = ^{
        pan.enabled = NO;
        pan.delegate = nil;
        if (pan.view == window) [window removeGestureRecognizer:pan];
        objc_setAssociatedObject(window, &MTCornerHandlerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    };
    if (NSThread.isMainThread) remove();
    else dispatch_async(dispatch_get_main_queue(), remove);
}
- (void)dealloc { [self detach]; }
- (BOOL)available {
    if (!NSThread.isMainThread) return NO;
    UIWindow *window = self.window;
    if (!MTCornerWindowEligible(window)) return [self reject:@"window"];
    BOOL springBoard = [NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"];
    if (springBoard) {
        if (![MTGlobalPanel deviceUnlocked] || [MTGlobalPanel.sharedInstance isVisible]) return [self reject:@"lock/panel"];
    } else if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return [self reject:@"inactive-app"];
    UIWindowScene *scene = window.windowScene;
    if (scene && scene.activationState != UISceneActivationStateForegroundActive &&
        !(springBoard && scene.activationState == UISceneActivationStateForegroundInactive)) return [self reject:@"inactive-scene"];
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    if (!manager.preferencesAvailable) [manager reload];
    if (!manager.preferencesAvailable || !MTKeyboardPanelBool(manager.prefs, kEnabledkey, YES) ||
        !MTCornerGestureMasterEnabled(manager.prefs)) return [self reject:@"preferences/enabled"];
    return YES;
}
- (BOOL)hasAction:(NSString *)region preferences:(NSDictionary *)preferences {
    NSString *selector = MTCornerGestureSelector(preferences, MTCornerGestureSlot(region));
    if (!selector) return NO;
    // 手势面板恒定启用：绑定到手势面板即视为有效动作（与状态栏/Dock 一致）。
    if (MTPanelAllowed(preferences, selector, MTPanelGestureKind)) return YES;
    id definitions = preferences[kLinkActionskey];
    for (id entry in [definitions isKindOfClass:NSArray.class] ? definitions : @[])
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return MTGlobalCustomActionSupported(entry);
    return NO;
}
- (void)refresh {
    if (!NSThread.isMainThread || !self.pan) return;
    // 尚未开始的手势一律作废：配置、前后台、锁屏或旋转通知后必须重新起手。
    // 已经 begin 的手势不受影响——UIKit 保证其后必定来到 ended 或 cancelled，
    // 这期间的偏好刷新不该让一次已经开始的上滑白做；完成判定仍然按会话摘要、
    // 窗口几何与可见性逐次复核。
    MTCornerGestureSession *pending = objc_getAssociatedObject(self.pan, &MTCornerSessionKey);
    if (!pending.acknowledged)
        objc_setAssociatedObject(self.pan, &MTCornerSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDictionary *preferences = MTPrefsManager.sharedInstance.prefs;
    NSUInteger configured = 0;
    for (NSString *region in MTCornerGestureRegions())
        if ([self hasAction:region preferences:preferences]) configured++;
    // 可见性/锁屏/面板 gate 逐触摸评估；这里只反映配置摘要，面板关闭后手势立即可再用。
    NSString *configuration = [NSString stringWithFormat:@"%d/%lu", MTPrefsManager.sharedInstance.preferencesAvailable, (unsigned long)configured];
    if (![self.lastConfiguration isEqual:configuration]) {
        self.lastConfiguration = configuration;
        NSLog(@"[MetisKeyboard][CornerGesture] config host=%@ available=%d slots=%lu", NSProcessInfo.processInfo.processName,
            MTPrefsManager.sharedInstance.preferencesAvailable, (unsigned long)configured);
    }
    self.pan.enabled = MTPrefsManager.sharedInstance.preferencesAvailable && configured > 0 &&
        MTKeyboardPanelBool(preferences, kEnabledkey, YES) && MTCornerGestureMasterEnabled(preferences);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (!NSThread.isMainThread || gesture != self.pan) return NO;
    // 新触摸（含第二根手指）使上一个未完成会话作废，杜绝陈旧触发。
    objc_setAssociatedObject(gesture, &MTCornerSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (![self available]) return NO;
    UIWindow *window = self.window;
    if (touch.window != window) return [self reject:@"window-mismatch"];
    NSDictionary *preferences = MTPrefsManager.sharedInstance.prefs;
    CGPoint point = [touch locationInView:window];
    NSString *region = MTCornerRegionAtPointWithInset(point, window.bounds.size, MTCornerGestureRadius(preferences),
        MTCornerGestureAngle(preferences), MTCornerGestureBottomInset(preferences));
    if (!region) return NO;
    // 角落的原生交互不抢占：App 控件（tab bar 按钮、滑条等）与 SB Dock 图标。
    for (UIView *view = touch.view; view && view != window; view = view.superview)
        if ([view isKindOfClass:UIControl.class] || MTDockPanelIsIconView(view)) return [self reject:@"native-control"];
    if (![self hasAction:region preferences:preferences]) return NO;
    self.lastRejection = nil;
    MTCornerGestureSession *session = [MTCornerGestureSession new];
    session.region = region;
    session.selector = [MTCornerGestureSelector(preferences, MTCornerGestureSlot(region)) copy];
    session.window = window;
    session.digest = [MTCornerGestureSessionDigest(preferences) copy];
    session.metrics = MTCornerGestureMetricsForPreferences(preferences);
    session.hapticEnabled = MTKeyboardPanelBool(preferences, kEnabledHaptickey, YES);
    session.windowBounds = window.bounds;
    objc_setAssociatedObject(gesture, &MTCornerSessionKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (session.hapticEnabled) [MTCornerSelectionFeedback() prepare];
    NSLog(@"[MetisKeyboard][CornerGesture] touch host=%@ region=%@ origin=(%.0f,%.0f) view=%@",
        NSProcessInfo.processInfo.processName, region, point.x, point.y, NSStringFromClass(touch.view.class));
    return YES;
}
- (BOOL)sessionIsCurrent:(MTCornerGestureSession *)session {
    if (!session || session.dispatched) return NO;
    // 只比对决定本次触发的字段。无关偏好变动（其它页面的编辑）不再作废一次
    // 正在进行的滑动；触摸起点是 begin 之前唯一一次采样，抬起前必须全程有效。
    return [self available] && session.window == self.window &&
        CGRectEqualToRect(session.windowBounds, self.window.bounds) &&
        [session.digest isEqual:MTCornerGestureSessionDigest(MTPrefsManager.sharedInstance.prefs)];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture != self.pan) return YES;
    MTCornerGestureSession *session = objc_getAssociatedObject(gesture, &MTCornerSessionKey);
    if (![self sessionIsCurrent:session]) return NO;
    CGPoint delta = [self.pan translationInView:self.window];
    if (CGPointEqualToPoint(delta, CGPointZero)) delta = [self.pan velocityInView:self.window];
    if (!isfinite(delta.x) || !isfinite(delta.y)) return NO;
    return MTCornerGestureUpwardWithRatio(delta.x, delta.y, session.metrics.ratio);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    // 已配置的角落扇形触摸归本识别器独占：避免角落上滑同时滚动内容或触发
    // SpringBoard 转场。未配置/未命中时本识别器不 begin，不拦截任何手势。
    if (!NSThread.isMainThread || gesture != self.pan || objc_getAssociatedObject(other, &MTCornerRecognizerKey)) return NO;
    MTCornerGestureSession *session = objc_getAssociatedObject(gesture, &MTCornerSessionKey);
    if (![self sessionIsCurrent:session]) return NO;
    return [other isKindOfClass:UIPanGestureRecognizer.class] && ![other isKindOfClass:UIScreenEdgePanGestureRecognizer.class];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)gesture; (void)other;
    return NO;
}
- (void)cornerPan:(UIPanGestureRecognizer *)gesture {
    if (!NSThread.isMainThread || gesture != self.pan) return;
    if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        if (objc_getAssociatedObject(gesture, &MTCornerSessionKey))
            NSLog(@"[MetisKeyboard][CornerGesture] cancelled host=%@ state=%ld", NSProcessInfo.processInfo.processName, (long)gesture.state);
        objc_setAssociatedObject(gesture, &MTCornerSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (gesture.state == UIGestureRecognizerStateBegan) {
        MTCornerGestureSession *began = objc_getAssociatedObject(gesture, &MTCornerSessionKey);
        if ([self sessionIsCurrent:began] && !began.acknowledged) {
            began.acknowledged = YES;
            if (began.hapticEnabled) [MTCornerSelectionFeedback() selectionChanged];
        }
        return;
    }
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    MTCornerGestureSession *session = objc_getAssociatedObject(gesture, &MTCornerSessionKey);
    objc_setAssociatedObject(gesture, &MTCornerSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!session || session.dispatched || ![self sessionIsCurrent:session]) return;
    CGPoint delta = [gesture translationInView:self.window];
    CGPoint velocity = [gesture velocityInView:self.window];
    if (!MTCornerGestureCompletesWithMetrics(delta.x, delta.y, velocity.y, session.metrics)) return;
    session.dispatched = YES;
    NSString *slot = MTCornerGestureSlot(session.region);
    NSLog(@"[MetisKeyboard][CornerGesture] trigger host=%@ slot=%@ travel=(%.0f,%.0f) velocity=%.0f",
        NSProcessInfo.processInfo.processName, slot, delta.x, delta.y, velocity.y);
    if (session.hapticEnabled) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
    }
    MTRequestCornerGesture(slot, session.selector, ^(MTSystemOpenResult result) {
        NSLog(@"[MetisKeyboard][CornerGesture] result host=%@ slot=%@ status=%llu",
            NSProcessInfo.processInfo.processName, slot, (unsigned long long)result);
    });
}
@end

static void MTInstallCornerGesture(UIWindow *window) {
    if (!NSThread.isMainThread || !MTCornerWindowEligible(window)) return;
    NSString *host = NSProcessInfo.processInfo.processName;
    if (!MTCornerGestureLocalRecognizerAllowed(MTPrefsManager.sharedInstance.prefs, host)) return;
    MTCornerGestureHandler *handler = objc_getAssociatedObject(window, &MTCornerHandlerKey);
    if (handler) { [handler refresh]; return; }
    handler = [MTCornerGestureHandler new];
    handler.window = window;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:handler action:@selector(cornerPan:)];
    pan.minimumNumberOfTouches = 1;
    pan.maximumNumberOfTouches = 1;
    pan.cancelsTouchesInView = YES;
    pan.delaysTouchesBegan = NO;
    pan.delegate = handler;
    handler.pan = pan;
    objc_setAssociatedObject(pan, &MTCornerRecognizerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(window, &MTCornerHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!MTCornerHandlers) MTCornerHandlers = [NSHashTable weakObjectsHashTable];
    [MTCornerHandlers addObject:handler];
    [window addGestureRecognizer:pan];
    [handler refresh];
    NSLog(@"[MetisKeyboard][CornerGesture] installed host=%@ window=%@ size=(%.0f,%.0f)", NSProcessInfo.processInfo.processName,
        NSStringFromClass(window.class), window.bounds.size.width, window.bounds.size.height);
}

// 通道切换后要把已经挂上的识别器拆干净：否则关掉 legacy 通道后，旧的 window pan
// 仍留在窗口上，会与新开的 system 通道各自触发一次动作。
static void MTCornerTeardownHandlers(void) {
    for (MTCornerGestureHandler *handler in MTCornerHandlers.allObjects.copy) {
        [handler detach];
        [MTCornerHandlers removeObject:handler];
    }
}

static void MTTryCornerHooks(void) {
    if (!NSThread.isMainThread) return;
    NSString *host = NSProcessInfo.processInfo.processName;
    if (!MTCornerGestureLocalRecognizerAllowed(MTPrefsManager.sharedInstance.prefs, host)) {
        if (MTCornerHandlers.count) {
            MTCornerTeardownHandlers();
            NSLog(@"[MetisKeyboard][CornerGesture] legacy channel disabled host=%@", host);
        }
        return;
    }
    NSMutableSet<UIWindow *> *windows = [NSMutableSet set];
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows ?: @[]];
    #pragma clang diagnostic pop
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows ?: @[]];
    for (UIWindow *window in windows) MTInstallCornerGesture(window);
    // 窗口隐藏/降级后回收识别器，避免陈旧 handler 常驻失效窗口。
    for (MTCornerGestureHandler *handler in MTCornerHandlers.allObjects.copy) {
        UIWindow *window = handler.window;
        if (window && MTCornerWindowEligible(window)) { [handler refresh]; continue; }
        if (window) {
            if (handler.pan && handler.pan.view == window) [window removeGestureRecognizer:handler.pan];
            objc_setAssociatedObject(window, &MTCornerHandlerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [MTCornerHandlers removeObject:handler];
    }
}

void MTStartCornerGestures(void) {
    if (!MTStatusBarHostAllowed(NSProcessInfo.processInfo.processName, NSBundle.mainBundle.bundleURL.pathExtension)) return;
    void (^start)(void) = ^{
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            if (!MTCornerHandlers) MTCornerHandlers = [NSHashTable weakObjectsHashTable];
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            for (NSString *name in @[UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeKeyNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    MTTryCornerHooks();
                    if ([note.object isKindOfClass:UIWindow.class]) MTInstallCornerGesture(note.object);
                }];
            }
            for (NSString *name in @[UIApplicationDidFinishLaunchingNotification, UISceneWillConnectNotification, UISceneDidActivateNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { MTTryCornerHooks(); }];
            }
            [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                [MTPrefsManager.sharedInstance reload];
                MTTryCornerHooks();
            }];
            for (NSString *name in @[UIApplicationWillResignActiveNotification, UISceneWillDeactivateNotification, UIDeviceOrientationDidChangeNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    for (MTCornerGestureHandler *handler in MTCornerHandlers.allObjects) [handler refresh];
                }];
            }
            for (NSString *name in @[kPrefsChangedIdentifier, @"com.apple.springboard.lockstate", @"com.apple.springboard.frontmostapplicationchanged"]) {
                int token = NOTIFY_TOKEN_INVALID;
                uint32_t result = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(__unused int delivered) {
                    [MTPrefsManager.sharedInstance reload];
                    MTTryCornerHooks();
                });
                if (result != NOTIFY_STATUS_OK) NSLog(@"[MetisKeyboard][CornerGesture] notification registration failed status=%u", result);
            }
            MTTryCornerHooks();
        });
    };
    if (NSThread.isMainThread) start();
    else dispatch_async(dispatch_get_main_queue(), start);
}
