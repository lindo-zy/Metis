// MTKeyboardSpringBoardEntry —— MetisKeyboard（Keyboard 模块）SpringBoard 侧唯一挂接点。
// 原 DXKeyboardHooks.xm ctor 的 isSpringBoard 分支整体迁入：系统 open broker、全局面板、
// 悬浮 App 托管、键盘收起把手、状态栏手势、shortcut/AI 请求监听与桌面可见性钩子。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "common.h"
#import "DXHelper.h"
#import "DXPrefsManager.h"
#import "DXQuickActionProvider.h"
#import "DXAIPanel.h"
#import "DXKbdCollapseHandle.h"
#import "DXStatusBarGestures.h"
#import "DXGlobalPanel.h"
#import "DXFloatingApp.h"
#import "DXServer.h"
#import "DXSystemOpenBroker.h"
#import "MTCore.h"

#pragma mark - shortcut 快照刷新请求（Settings 两段式枚举的结果回填）

static void dxsbShortcutRefreshRequestCallback(CFNotificationCenterRef center,
                                               void *observer,
                                               CFStringRef name,
                                               const void *object,
                                               CFDictionaryRef userInfo) {
    NSDictionary *request = DXQuickActionSharedValue(MTQuickActionRequestKey);
    NSArray *rawBundles = [request[@"bundles"] isKindOfClass:[NSArray class]] ? request[@"bundles"] : nil;
    NSString *requestID = [request[@"requestID"] isKindOfClass:[NSString class]] ? request[@"requestID"] : nil;
    if (rawBundles.count > 2048) rawBundles = nil;
    if (requestID.length == 0) return;

    static NSString *lastRequestID;
    @synchronized([DXQuickActionProvider class]) {
        if ([lastRequestID isEqualToString:requestID]) return;
        lastRequestID = [requestID copy];
    }

    NSMutableOrderedSet<NSString *> *bundleIdentifiers = [NSMutableOrderedSet orderedSet];
    for (id value in rawBundles) {
        if (DXIsValidBundleIdentifier(value)) [bundleIdentifiers addObject:value];
    }
    [DXQuickActionProvider refreshSnapshotForBundleIdentifiers:bundleIdentifiers.array
                                                     requestID:requestID];
}

#pragma mark - AI 面板请求（SB 桌面呈现）

static NSString *g_dxsbAIPendingSeedText;
static BOOL g_dxsbAIPendingClipboardImage;
static double g_dxsbAIPendingCreatedAt;
static BOOL g_dxsbAIDesktopVisible;

static void DXSBDelayedAIPrefsHeal(void);

static void DXSBDPresentAIPanelFromPending(void) {
    NSString *seed = g_dxsbAIPendingSeedText;
    BOOL clipboardImage = g_dxsbAIPendingClipboardImage;
    g_dxsbAIPendingSeedText = nil;
    g_dxsbAIPendingClipboardImage = NO;
    [DXAIPanel presentInSpringBoardWithSeedText:seed clipboardImage:clipboardImage];
}

static void DXSBDPresentAIPanelWhenDesktop(void) {
    if (!g_dxsbAIPendingSeedText && !g_dxsbAIPendingClipboardImage) return;
    if (!g_dxsbAIDesktopVisible) return;
    if ([NSDate date].timeIntervalSince1970 - g_dxsbAIPendingCreatedAt > 300.0) {
        g_dxsbAIPendingSeedText = nil;
        g_dxsbAIPendingClipboardImage = NO;
        return;
    }
    DXSBDPresentAIPanelFromPending();
}

static void DXSBOpenAIPanelWithRequest(NSDictionary *request) {
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
    g_dxsbAIPendingSeedText = ([mode isEqualToString:@"text"] && [request[@"text"] isKindOfClass:[NSString class]])
        ? request[@"text"] : nil;
    if (g_dxsbAIPendingSeedText.length == 0) g_dxsbAIPendingSeedText = nil;
    g_dxsbAIPendingClipboardImage = [mode isEqualToString:@"image"];
    g_dxsbAIPendingCreatedAt = created;

    if ([request[@"origin"] isKindOfClass:[NSString class]] &&
        [request[@"origin"] isEqualToString:@"sb"]) {
        DXSBDPresentAIPanelFromPending();
    } else {
        DXSBDPresentAIPanelWhenDesktop();
    }
}

static void dxsbAIChatRequestCallback(CFNotificationCenterRef center,
                                      void *observer,
                                      CFStringRef name,
                                      const void *object,
                                      CFDictionaryRef userInfo) {
    NSDictionary *request = DXQuickActionSharedValue(MTAIChatRequestKey);
    if (![request isKindOfClass:[NSDictionary class]]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        DXSBOpenAIPanelWithRequest(request);
    });
}

#pragma mark - 桌面可见性（SBHomeScreenViewController）

// 桌面可见性信号：app 来源的延迟 AI 请求在桌面真正出现时才创建面板。
%hook SBHomeScreenViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // 冷启动兜底：ctor 时域读取可能撞上 cfprefsd 未就绪/首解锁前保护而读空。
    if (![DXPrefsManager sharedInstance].preferencesAvailable) DXSBDelayedAIPrefsHeal();
    g_dxsbAIDesktopVisible = YES;
    DXSBDPresentAIPanelWhenDesktop();
    // 回桌面时收回展开面板，保留边缘常驻把手。
    DXKbdCollapseHandleDesktopDidAppear();
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    g_dxsbAIDesktopVisible = NO;
}

%end

static void DXSBDelayedAIPrefsHeal(void) {
    // DXPrefsManager +load 已注册 prefschanged 观察并自愈；这里只主动触发一次读取。
    [[DXPrefsManager sharedInstance] readPrefs];
}

%ctor {
    @autoreleasepool {
        if (![[[NSProcessInfo processInfo] processName] isEqualToString:@"SpringBoard"]) {
            return;
        }
        isSpringBoard = YES;

        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                // 不 load MetisKeyboardPrefs.bundle：其链接 SwiftUI/JSContext
                // 等重框架，SB 无需其代码；资源访问用 NSBundle 按需读取即可。

                CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, dxsbShortcutRefreshRequestCallback, (CFStringRef)kShortcutRefreshRequestIdentifier, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
                CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, dxsbAIChatRequestCallback, (CFStringRef)kAIChatRequestIdentifier, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

                %init();

                [MTModuleGate addObserver:nil block:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        CFNotificationCenterPostNotification(
                            CFNotificationCenterGetDarwinNotifyCenter(),
                            (CFStringRef)kPrefsChangedIdentifier, NULL, NULL, TRUE);
                        MTLogInfo(MTLogModuleKeyboard, @"state=sb-gate-applied enabled=%d",
                                  [MTModuleGate moduleEnabled:MTModuleKeyboard]);
                    });
                }];

                DXStartStatusBarGestures();
                DXStartSystemOpenBroker();
                DXStartGlobalPanel();
                DXStartFloatingAppHost();
                DXStartKbdCollapseHandle();
                DXStartKbdVisibilityReporter();
                MTLogInfo(MTLogModuleKeyboard, @"state=sb-entry-ready version=%@", MTCoreVersionString);
            }
        });
    }
}
