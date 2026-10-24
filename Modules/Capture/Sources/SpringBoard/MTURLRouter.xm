#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>
#import "../Common/MTConstants.h"
#import "../Common/MTCaptureAction.h"
#import "../Common/MTCaptureLog.h"
#import "../Capture/MTCaptureCoordinator.h"

// 外部调用方经 prefs://root=metis_* 触达截图协调器。设置页本地测试走 Darwin，
// 不依赖 Preferences 向自身 openURL 时是否产生 SpringBoard 启动事务。
// 路由解析、白名单和对应通知与设置页共用 MTCaptureAction 目录。
// 普通请求、trusted 请求及系统直接请求仍分别探测并安装，非 Metis 路由原样放行。
typedef void (^MTOpenCompletion)(NSError *error);

// 命中 metis_ 命名空间即消费（无效 root 也由本方拒绝，不交给系统打开设置页）；
// 非本命名空间的 URL 返回 NO，由调用方原样放行。
static BOOL MTConsumeRouteURL(NSURL *url, MTOpenCompletion completion) {
    NSString *root = MTCaptureRouteRoot(url);
    if (![root hasPrefix:(__bridge NSString *)MTURLRoutePrefix]) return NO;
    NSString *name = MTCaptureActionForURL(url).notificationName;
    if (name) {
        // 与 Darwin 通知入口同一协调器方法：总开关关闭/任务忙时按既有语义忽略并记日志。
        // 方法内部自带主线程兜底；URL 分发本身即在主线程。
        [[MTCaptureCoordinator sharedCoordinator] handleDarwinNotificationName:name];
        MTCaptureLogInfo(@"url route dispatched root=%@ notify=%@", root, name);
    } else {
        MTCaptureLogWarn(@"url route rejected: unknown root=%@", root);
    }
    if (completion) completion(nil);
    return YES;
}

// 普通 App 通过 FrontBoard 发来的 URL 请求；本地 PullOver-X 使用同一接收点。
static id MTReadRequestObject(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSURL *MTURLFromOpenOptions(id options) {
    id value = MTReadRequestObject(options, @"url");
    if ([value isKindOfClass:NSURL.class]) return value;
    id dictionary = [options isKindOfClass:NSDictionary.class]
        ? options : MTReadRequestObject(options, @"dictionary");
    value = [dictionary isKindOfClass:NSDictionary.class] ? dictionary[@"__PayloadURL"] : nil;
    if ([value isKindOfClass:NSURL.class]) return value;
    return [value isKindOfClass:NSString.class] ? [NSURL URLWithString:value] : nil;
}

// systemService 入口拿到的是 request（URL 在其 options），trusted 入口直接拿到
// options，两种形态共用上方解析。
static NSURL *MTURLFromOpenRequest(id request) {
    return MTURLFromOpenOptions(MTReadRequestObject(request, @"options"));
}

static void (*MTOriginalWorkspaceOpen)(id, SEL, id, id, MTOpenCompletion);
static void MTWorkspaceOpen(id self, SEL cmd, id service, id request, MTOpenCompletion completion) {
    if (MTConsumeRouteURL(MTURLFromOpenRequest(request), completion)) return;
    MTOriginalWorkspaceOpen(self, cmd, service, request, completion);
}

// SpringBoard 自身及其他插件的直接 URL 请求。系统版本之间存在带/不带
// notifyLSOnFailure 的两种入口，分别检查后安装，不猜测不存在的方法。
static void (*MTOriginalSpringBoardOpen)(id, SEL, NSURL *, id, BOOL, id, id, MTOpenCompletion);
static void MTSpringBoardOpen(id self, SEL cmd, NSURL *url, id app, BOOL animated,
                             id settings, id origin, MTOpenCompletion result) {
    if (MTConsumeRouteURL(url, result)) return;
    MTOriginalSpringBoardOpen(self, cmd, url, app, animated, settings, origin, result);
}

static void (*MTOriginalSpringBoardOpenNotify)(id, SEL, NSURL *, id, BOOL, id, id, BOOL, MTOpenCompletion);
static void MTSpringBoardOpenNotify(id self, SEL cmd, NSURL *url, id app, BOOL animated,
                                   id settings, id origin, BOOL notifyLS, MTOpenCompletion result) {
    if (MTConsumeRouteURL(url, result)) return;
    MTOriginalSpringBoardOpenNotify(self, cmd, url, app, animated, settings, origin, notifyLS, result);
}

// 目标 App 已在前台的外部 openURL 请求可能经 trusted 入口分发。
// 参数序与 PullOver-X 实测实现一致：(application, options, activationSettings,
// origin, result)，URL 解析口径与普通请求相同。
static void (*MTOriginalWorkspaceTrustedOpen)(id, SEL, id, id, id, id, MTOpenCompletion);
static void MTWorkspaceTrustedOpen(id self, SEL cmd, id application, id options,
                                   id activationSettings, id origin, MTOpenCompletion result) {
    if (MTConsumeRouteURL(MTURLFromOpenOptions(options), result)) return;
    MTOriginalWorkspaceTrustedOpen(self, cmd, application, options, activationSettings, origin, result);
}

static void MTInstallURLHook(Class cls, NSString *selectorName, IMP replacement, IMP *original) {
    SEL selector = NSSelectorFromString(selectorName);
    if (cls && class_getInstanceMethod(cls, selector)) {
        MSHookMessageEx(cls, selector, replacement, original);
        MTCaptureLogInfo(@"url router hook installed: %@", selectorName);
    } else {
        MTCaptureLogWarn(@"url router hook unavailable: %@", selectorName);
    }
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            MTInstallURLHook(NSClassFromString(@"SBMainWorkspace"),
                @"systemService:handleOpenApplicationRequest:withCompletion:",
                (IMP)MTWorkspaceOpen, (IMP *)&MTOriginalWorkspaceOpen);
            MTInstallURLHook(NSClassFromString(@"SBMainWorkspace"),
                @"_handleTrustedOpenRequestForApplication:options:activationSettings:origin:withResult:",
                (IMP)MTWorkspaceTrustedOpen, (IMP *)&MTOriginalWorkspaceTrustedOpen);
            Class springBoard = NSClassFromString(@"SpringBoard");
            MTInstallURLHook(springBoard,
                @"applicationOpenURL:withApplication:animating:activationSettings:origin:withResult:",
                (IMP)MTSpringBoardOpen, (IMP *)&MTOriginalSpringBoardOpen);
            MTInstallURLHook(springBoard,
                @"applicationOpenURL:withApplication:animating:activationSettings:origin:notifyLSOnFailure:withResult:",
                (IMP)MTSpringBoardOpenNotify, (IMP *)&MTOriginalSpringBoardOpenNotify);
            MTCaptureLogInfo(@"url router loaded");
        } @catch (NSException *exception) {
            MTCaptureLogError(@"url router ctor exception: %@", exception);
        }
    });
}
