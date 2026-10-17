#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>
#import "../Common/MTConstants.h"
#import "../Common/MTExternalRequest.h"
#import "../Common/MTCaptureLog.h"
#import "../Capture/MTCaptureCoordinator.h"
#import "MTShellXPlugin.h"

// 跨进程请求入口：Darwin 通知只携带名称，不携带数据（DEVELOPMENT.md 2.2）。
// 回调线程不确定，统一跳主线程后交给协调器分发。

static void MTDispatchExternalRequest(NSString *name, NSString *source) {
    dispatch_async(dispatch_get_main_queue(), ^{
        MTCaptureLogInfo(@"external request source=%@ action=%@", source, name);
        [[MTCaptureCoordinator sharedCoordinator] handleDarwinNotificationName:name];
    });
}

// observer 传 MTDistributedObserverTag 标记 Distributed 中心注册，便于日志区分来源；
// CF 仅把它当不透明指针原样回传，只比较不解引用。若未来新增移除逻辑，必须用同一指针。
#define MTDistributedObserverTag ((void *)1)
static void MTHandleExternalNotification(CFNotificationCenterRef center,
                                         void *observer,
                                         CFStringRef name,
                                         const void *object,
                                         CFDictionaryRef userInfo) {
    if (name) {
        MTDispatchExternalRequest([(__bridge NSString *)name copy],
                                  observer == MTDistributedObserverTag ? @"distributed" : @"darwin");
    }
}

// iOS SDK 头文件不再声明 Distributed 中心，符号仍在 CoreFoundation 内：
// dlsym 取用，缺失时返回 NULL，调用方跳过 Distributed 注册（Darwin 通道不受影响）。
static CFNotificationCenterRef MTDistributedCenter(void) {
    static CFNotificationCenterRef (*mtDistributedCenter)(void);
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        *(void **)&mtDistributedCenter = dlsym(RTLD_DEFAULT, "CFNotificationCenterGetDistributedCenter");
    });
    return mtDistributedCenter ? mtDistributedCenter() : NULL;
}

// withResult / withCompletion 为 FrontBoard 的 NSError * 回调；nil 表示请求已接收，
// 不表示图片已保存。只消费自己的 scheme，且消费后绝不调用原方法或再发一次通知。
typedef void (^MTOpenCompletion)(NSError *error);

static BOOL MTConsumeExternalURL(NSURL *url, MTOpenCompletion completion) {
    if (!MTIsExternalURL(url)) return NO;
    NSString *name = MTNotificationNameForExternalURL(url);
    if (name) {
        MTDispatchExternalRequest(name, @"url");
    } else {
        MTCaptureLogWarn(@"external URL rejected: invalid command");
    }
    if (completion) {
        completion(name ? nil : [NSError errorWithDomain:MTBundleID code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid MetisCapture command"}]);
    }
    return YES;
}

// 普通 App 通过 FrontBoard 发来的 URL 请求；本地 PullOver-X 使用同一接收点。
static id MTReadRequestObject(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSURL *MTURLFromOpenRequest(id request) {
    id options = MTReadRequestObject(request, @"options");
    id value = MTReadRequestObject(options, @"url");
    if ([value isKindOfClass:NSURL.class]) return value;
    id dictionary = [options isKindOfClass:NSDictionary.class]
        ? options : MTReadRequestObject(options, @"dictionary");
    value = [dictionary isKindOfClass:NSDictionary.class] ? dictionary[@"__PayloadURL"] : nil;
    if ([value isKindOfClass:NSURL.class]) return value;
    return [value isKindOfClass:NSString.class] ? [NSURL URLWithString:value] : nil;
}

static void (*MTOriginalWorkspaceOpen)(id, SEL, id, id, MTOpenCompletion);
static void MTWorkspaceOpen(id self, SEL cmd, id service, id request, MTOpenCompletion completion) {
    if (MTConsumeExternalURL(MTURLFromOpenRequest(request), completion)) return;
    MTOriginalWorkspaceOpen(self, cmd, service, request, completion);
}

// SpringBoard 自身及其他插件的直接 URL 请求。系统版本之间存在带/不带
// notifyLSOnFailure 的两种入口，分别检查后安装，不猜测不存在的方法。
static void (*MTOriginalSpringBoardOpen)(id, SEL, NSURL *, id, BOOL, id, id, MTOpenCompletion);
static void MTSpringBoardOpen(id self, SEL cmd, NSURL *url, id app, BOOL animated,
                             id settings, id origin, MTOpenCompletion result) {
    if (MTConsumeExternalURL(url, result)) return;
    MTOriginalSpringBoardOpen(self, cmd, url, app, animated, settings, origin, result);
}

static void (*MTOriginalSpringBoardOpenNotify)(id, SEL, NSURL *, id, BOOL, id, id, BOOL, MTOpenCompletion);
static void MTSpringBoardOpenNotify(id self, SEL cmd, NSURL *url, id app, BOOL animated,
                                   id settings, id origin, BOOL notifyLS, MTOpenCompletion result) {
    if (MTConsumeExternalURL(url, result)) return;
    MTOriginalSpringBoardOpenNotify(self, cmd, url, app, animated, settings, origin, notifyLS, result);
}

static void MTInstallURLHook(Class cls, NSString *selectorName, IMP replacement, IMP *original) {
    SEL selector = NSSelectorFromString(selectorName);
    if (cls && class_getInstanceMethod(cls, selector)) {
        MSHookMessageEx(cls, selector, replacement, original);
        MTCaptureLogInfo(@"external URL hook installed: %@", selectorName);
    } else {
        MTCaptureLogWarn(@"external URL hook unavailable: %@", selectorName);
    }
}

%ctor {
    // 协调器构造会操作 UIDevice / 通知观察者，初始化也统一放到主线程。
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [[MTCaptureCoordinator sharedCoordinator] start];

            // SHELLX 插件插入形式：以 Snapper3 协议注册进 SHELLXPluginManager，
            // 未装 SHELLX 时探测链自动放弃（MTShellXPlugin.xm）。
            MTShellXPluginInstall();

            CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
            CFStringRef names[] = {
                MTDarwinActivate,
                MTDarwinCaptureFull,
                MTDarwinCaptureArea,
                MTDarwinCaptureFreeze,
                MTDarwinCaptureInstant,
                MTDarwinCaptureMarkup,
                MTDarwinCaptureLong,
                MTDarwinCaptureCancel,
                MTDarwinPreferencesReload,
                // Snapper3 兼容别名：第三方按 Snapper3 公开约定发通知即可驱动 MetisCapture。
                MTDarwinSnapperForceOpen,
                MTDarwinSnapperForceInstantOpen,
                MTDarwinSnapperForceFreezeOpen,
                MTDarwinSnapperCloseAll,
                MTDarwinSnapperCloseCrop,
            };
            for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
                CFNotificationCenterAddObserver(center,
                                                NULL,
                                                MTHandleExternalNotification,
                                                names[i],
                                                NULL,
                                                CFNotificationSuspensionBehaviorDeliverImmediately);
            }

            // SHELLX 兼容别名：其调用约定允许把通知发到 Darwin 或 Distributed 任一中心
            //（每次只发一条），所以两个中心都要监听，漏一个就会丢调用。
            CFStringRef shellXNames[] = {
                MTDarwinShellXOpen,
                MTDarwinShellXOpenInstant,
                MTDarwinShellXOpenFreeze,
                MTDarwinShellXClose,
            };
            CFNotificationCenterRef distributed = MTDistributedCenter();
            for (size_t i = 0; i < sizeof(shellXNames) / sizeof(shellXNames[0]); i++) {
                CFNotificationCenterAddObserver(center,
                                                NULL,
                                                MTHandleExternalNotification,
                                                shellXNames[i],
                                                NULL,
                                                CFNotificationSuspensionBehaviorDeliverImmediately);
                if (distributed) {
                    CFNotificationCenterAddObserver(distributed,
                                                    MTDistributedObserverTag,
                                                    MTHandleExternalNotification,
                                                    shellXNames[i],
                                                    NULL,
                                                    CFNotificationSuspensionBehaviorDeliverImmediately);
                }
            }

            MTInstallURLHook(NSClassFromString(@"SBMainWorkspace"),
                @"systemService:handleOpenApplicationRequest:withCompletion:",
                (IMP)MTWorkspaceOpen, (IMP *)&MTOriginalWorkspaceOpen);
            Class springBoard = NSClassFromString(@"SpringBoard");
            MTInstallURLHook(springBoard,
                @"applicationOpenURL:withApplication:animating:activationSettings:origin:withResult:",
                (IMP)MTSpringBoardOpen, (IMP *)&MTOriginalSpringBoardOpen);
            MTInstallURLHook(springBoard,
                @"applicationOpenURL:withApplication:animating:activationSettings:origin:notifyLSOnFailure:withResult:",
                (IMP)MTSpringBoardOpenNotify, (IMP *)&MTOriginalSpringBoardOpenNotify);

            MTCaptureLogInfo(@"loaded into SpringBoard");
        } @catch (NSException *exception) {
            MTCaptureLogError(@"ctor exception: %@", exception);
        }
    });
}
