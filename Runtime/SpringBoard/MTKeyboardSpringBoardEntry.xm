// MTKeyboardSpringBoardEntry —— MetisKeyboard（Keyboard 模块）SpringBoard 侧唯一挂接点。
// 原 MTKeyboardHooks.xm ctor 的 isSpringBoard 分支整体迁入：系统 open broker、全局面板、
// 悬浮 App 托管、快速面板宿主、状态栏手势、shortcut/AI 请求监听与桌面可见性钩子。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "common.h"
#import "MTHelper.h"
#import "MTPrefsManager.h"
#import "MTQuickActionProvider.h"
#import "MTAIPanel.h"
#import "MTQuickPanelHost.h"
#import "MTStatusBarGestures.h"
#import "MTEdgeGestures.h"
#import "MTArcGestures.h"
#import "MTGlobalPanel.h"
#import "MTFloatingApp.h"
#import "MTServer.h"
#import "MTSystemOpenBroker.h"
#import "MTCore.h"

#pragma mark - shortcut 快照刷新请求（Settings 两段式枚举的结果回填）

static void mtsbShortcutRefreshRequestCallback(CFNotificationCenterRef center,
                                               void *observer,
                                               CFStringRef name,
                                               const void *object,
                                               CFDictionaryRef userInfo) {
    NSDictionary *request = MTQuickActionSharedValue(MTQuickActionRequestKey);
    NSArray *rawBundles = [request[@"bundles"] isKindOfClass:[NSArray class]] ? request[@"bundles"] : nil;
    NSString *requestID = [request[@"requestID"] isKindOfClass:[NSString class]] ? request[@"requestID"] : nil;
    if (rawBundles.count > 2048) rawBundles = nil;
    if (requestID.length == 0) return;

    static NSString *lastRequestID;
    @synchronized([MTQuickActionProvider class]) {
        if ([lastRequestID isEqualToString:requestID]) return;
        lastRequestID = [requestID copy];
    }

    NSMutableOrderedSet<NSString *> *bundleIdentifiers = [NSMutableOrderedSet orderedSet];
    for (id value in rawBundles) {
        if (MTIsValidBundleIdentifier(value)) [bundleIdentifiers addObject:value];
    }
    [MTQuickActionProvider refreshSnapshotForBundleIdentifiers:bundleIdentifiers.array
                                                     requestID:requestID];
}

#pragma mark - AI 面板请求（SB 桌面呈现）

static NSString *g_mtsbAIPendingSeedText;
static BOOL g_mtsbAIPendingClipboardImage;
static double g_mtsbAIPendingCreatedAt;
static BOOL g_mtsbAIDesktopVisible;
// AI 动作追加的会话参数（format 3）。旧键盘端不会写这些键，保持为空即沿用
// 原有「只带入不发送」的行为。
static NSString *g_mtsbAIPendingPersonaID;
static NSString *g_mtsbAIPendingModel;
static BOOL g_mtsbAIPendingAutoSend;
static BOOL g_mtsbAIPendingExplicitOpen;

static void MTSBDelayedAIPrefsHeal(void);

static void MTSBDClearAIPending(void) {
    g_mtsbAIPendingSeedText = nil;
    g_mtsbAIPendingClipboardImage = NO;
    g_mtsbAIPendingPersonaID = nil;
    g_mtsbAIPendingModel = nil;
    g_mtsbAIPendingAutoSend = NO;
    g_mtsbAIPendingExplicitOpen = NO;
}

static void MTSBDPresentAIPanelFromPending(void) {
    NSString *seed = g_mtsbAIPendingSeedText;
    BOOL clipboardImage = g_mtsbAIPendingClipboardImage;
    NSString *personaID = g_mtsbAIPendingPersonaID;
    NSString *model = g_mtsbAIPendingModel;
    BOOL autoSend = g_mtsbAIPendingAutoSend;
    MTSBDClearAIPending();
    [MTAIPanel presentInSpringBoardWithSeedText:seed
                                 clipboardImage:clipboardImage
                                      personaID:personaID
                                          model:model
                                       autoSend:autoSend];
}

static void MTSBDPresentAIPanelWhenDesktop(void) {
    // AI 动作的空输入也要打开面板，用 explicit open 区分于普通按钮的空会话。
    if (!g_mtsbAIPendingSeedText && !g_mtsbAIPendingClipboardImage && !g_mtsbAIPendingExplicitOpen) return;
    if (!g_mtsbAIDesktopVisible) return;
    if ([NSDate date].timeIntervalSince1970 - g_mtsbAIPendingCreatedAt > 300.0) {
        MTSBDClearAIPending();
        return;
    }
    MTSBDPresentAIPanelFromPending();
}

static void MTSBOpenAIPanelWithRequest(NSDictionary *request) {
    NSString *requestID = [request[@"requestID"] isKindOfClass:[NSString class]] ? request[@"requestID"] : nil;
    if (requestID.length == 0) return;

    static NSString *lastAIRequestID;
    @synchronized(MTAIChatRequestKey) {
        if ([lastAIRequestID isEqualToString:requestID]) return;
        lastAIRequestID = [requestID copy];
    }

    double created = [request[@"created"] isKindOfClass:[NSNumber class]] ? [request[@"created"] doubleValue] : 0;
    if (created <= 0 || fabs([NSDate date].timeIntervalSince1970 - created) > 30.0) return;

    NSString *mode = [request[@"mode"] isKindOfClass:[NSString class]] ? request[@"mode"] : nil;
    g_mtsbAIPendingSeedText = ([mode isEqualToString:@"text"] && [request[@"text"] isKindOfClass:[NSString class]])
        ? request[@"text"] : nil;
    if (g_mtsbAIPendingSeedText.length == 0) g_mtsbAIPendingSeedText = nil;
    g_mtsbAIPendingClipboardImage = [mode isEqualToString:@"image"];
    g_mtsbAIPendingCreatedAt = created;
    // format 3 可选字段：缺失即旧键盘端的请求，按原有语义处理。
    g_mtsbAIPendingPersonaID = [request[kAIChatRequestPersonaField] isKindOfClass:[NSString class]]
        ? request[kAIChatRequestPersonaField] : nil;
    if (g_mtsbAIPendingPersonaID.length == 0) g_mtsbAIPendingPersonaID = nil;
    g_mtsbAIPendingModel = [request[kAIChatRequestModelField] isKindOfClass:[NSString class]]
        ? request[kAIChatRequestModelField] : nil;
    if (g_mtsbAIPendingModel.length == 0) g_mtsbAIPendingModel = nil;
    g_mtsbAIPendingAutoSend = [request[kAIChatRequestAutoSendField] isKindOfClass:[NSNumber class]] &&
        [request[kAIChatRequestAutoSendField] boolValue];
    g_mtsbAIPendingExplicitOpen = [request[kAIChatRequestOpenField] isKindOfClass:[NSNumber class]] &&
        [request[kAIChatRequestOpenField] boolValue];

    if ([request[@"origin"] isKindOfClass:[NSString class]] &&
        [request[@"origin"] isEqualToString:@"sb"]) {
        MTSBDPresentAIPanelFromPending();
    } else {
        MTSBDPresentAIPanelWhenDesktop();
    }
}

static void mtsbAIChatRequestCallback(CFNotificationCenterRef center,
                                      void *observer,
                                      CFStringRef name,
                                      const void *object,
                                      CFDictionaryRef userInfo) {
    NSDictionary *request = MTQuickActionSharedValue(MTAIChatRequestKey);
    if (![request isKindOfClass:[NSDictionary class]]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        MTSBOpenAIPanelWithRequest(request);
    });
}

#pragma mark - 桌面可见性（SBHomeScreenViewController）

// 桌面可见性信号：app 来源的延迟 AI 请求在桌面真正出现时才创建面板。
%hook SBHomeScreenViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // 冷启动兜底：ctor 时域读取可能撞上 cfprefsd 未就绪/首解锁前保护而读空。
    if (![MTPrefsManager sharedInstance].preferencesAvailable) MTSBDelayedAIPrefsHeal();
    g_mtsbAIDesktopVisible = YES;
    MTSBDPresentAIPanelWhenDesktop();
    // 回桌面时收回展开的快速面板。
    MTQuickPanelDesktopDidAppear();
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    g_mtsbAIDesktopVisible = NO;
}

%end

static void MTSBDelayedAIPrefsHeal(void) {
    // MTPrefsManager +load 已注册 prefschanged 观察并自愈；这里只主动触发一次读取。
    [[MTPrefsManager sharedInstance] readPrefs];
}

%ctor {
    @autoreleasepool {
        if (![[[NSProcessInfo processInfo] processName] isEqualToString:@"SpringBoard"]) {
            return;
        }
        isSpringBoard = YES;

        // 状态栏手势必须在 ctor 同步启动（此时处于 main 之前的加载线程）：
        // SpringBoard 启动早期就会构造/挂窗第一批状态栏实例，构造 hook 与
        // didMoveToWindow hook 晚于实例创建即静默漏挂，只能等后续通知扫描
        // 补救——刚注销/冷启动后桌面手势会静默失效。TypeX 4.3.3 的分析
        // （tests/STATUS_BAR_CORE_LIFECYCLE_20261005.md）明确要求"主线程
        // 调用启动入口时立即注册，减少首次构造之前的异步空隙"；MTStart-
        // StatusBarGestures 内部自线程路由，pre-main 即主线程，观察者与
        // 扫描对此刻的空 UI 均为安全空操作。
        MTStartStatusBarGestures();
        MTStartEdgeGestures();
        MTStartArcGestures();

        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                // 不 load MetisKeyboardPrefs.bundle：其链接 SwiftUI/JSContext
                // 等重框架，SB 无需其代码；资源访问用 NSBundle 按需读取即可。

                CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, mtsbShortcutRefreshRequestCallback, (CFStringRef)kShortcutRefreshRequestIdentifier, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
                CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, mtsbAIChatRequestCallback, (CFStringRef)kAIChatRequestIdentifier, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

                %init();

                [MTModuleGate addObserver:nil block:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        CFNotificationCenterPostNotification(
                            CFNotificationCenterGetDarwinNotifyCenter(),
                            (CFStringRef)kPrefsChangedIdentifier, NULL, NULL, TRUE);
                        MTLogInfo(MTLogModuleKeyboard, @"state=sb-gate-applied enabled=%d",
                                  [MTModuleGate globalEnabled]);
                    });
                }];

                MTStartSystemOpenBroker();
                MTStartGlobalPanel();
                MTStartFloatingAppHost();
                MTStartQuickPanelHost();
                MTLogInfo(MTLogModuleKeyboard, @"state=sb-entry-ready version=%@", MTCoreVersionString);
            }
        });
    }
}
