#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>
#import "../Common/MTConstants.h"
#import "../Common/MTCaptureLog.h"
#import "../Capture/MTCaptureCoordinator.h"

// 外部 URL 入口（2026-10-22 重新引入，寄生方案）：
// iOS 捷径「打开 URL」动作等外部调用方经 prefs://root=metis_* 触达截图协调器。
// prefs scheme 由 Preferences.app 认领，URL 必然经过 SpringBoard 分发层；在此拦截后
// 同进程直达协调器，不再向下打开设置页。与 6ff28c6 移除的 kayokox:// 自有 scheme
// 方案同构：hook 点沿用当时 ios16 实测可用的 PullOver-X 同款实现——SBMainWorkspace
// 两个入口：systemService:handleOpenApplicationRequest: 收普通 App 经 FrontBoard 发来
// 的请求（捷径即此路径）；_handleTrustedOpenRequestForApplication: 收目标 App 已在
// 前台的 openURL（设置页「测试」分组自身点击即此形态，2026-10-24 补入：这类请求不
// 产生完整启动事务，普通入口收不到，导致点击无响应）。另留 SpringBoard 两个
// applicationOpenURL: 变体收系统层直接转发。逐点运行时探测，不猜测不存在的方法。
// 差异只在白名单口径：只消费 metis_ 命名空间的 prefs 路由，其余 URL（含其他
// prefs 面板、shellx_ 等第三方路由）原样放行。路由常量单一事实源在 MTConstants。

typedef void (^MTOpenCompletion)(NSError *error);

// 从完整路由串反推 root id（截取 "root=" 之后的部分）。
static inline NSString *MTRouteRootOf(CFStringRef route) {
    NSString *value = (__bridge NSString *)route ?: @"";
    NSRange marker = [value rangeOfString:@"root=" options:NSBackwardsSearch];
    if (marker.location == NSNotFound) return value;
    return [value substringFromIndex:marker.location + marker.length];
}

// root id → Darwin 通知名。键由 MTURLRoute* 常量反推，值逐字对应，改路由必须同步两边。
// 冻结/即时/取消不在表内（需求决定不走 URL 入口，仍可由 Darwin 通知与键盘动作触发）；
// 未知 metis_ root 一律消费并记日志，不放行到设置页。
static NSDictionary<NSString *, NSString *> *MTRouteTable(void) {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            MTRouteRootOf(MTURLRouteFull):          (__bridge NSString *)MTDarwinCaptureFull,
            MTRouteRootOf(MTURLRouteArea):          (__bridge NSString *)MTDarwinCaptureArea,
            MTRouteRootOf(MTURLRouteMarkup):        (__bridge NSString *)MTDarwinCaptureMarkup,
            MTRouteRootOf(MTURLRouteLong):          (__bridge NSString *)MTDarwinCaptureLong,
            MTRouteRootOf(MTURLRouteEditClipboard): (__bridge NSString *)MTDarwinEditClipboard,
        };
    });
    return table;
}

// 只接受 prefs scheme；root 参数可能落在 host（NSURL 宽容解析 prefs://root=X）或
// resourceSpecifier（prefs:root=X 无 // 形态），两种都扫描；& 分隔的其他面板参数
// 忽略；带 query/fragment 的一律拒绝（与旧实现同口径，避免编码载荷夹带）。
static NSString *MTRouteRootFromURL(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) return nil;
    if (![url.scheme.lowercaseString isEqualToString:@"prefs"]) return nil;
    if (url.query.length || url.fragment.length) return nil;
    NSString *spec = url.host.length ? url.host : url.resourceSpecifier;
    if (spec.length == 0) return nil;
    if ([spec hasPrefix:@"//"]) spec = [spec substringFromIndex:2];
    for (NSString *part in [spec componentsSeparatedByString:@"&"]) {
        if ([part hasPrefix:@"root="]) {
            NSString *value = [part substringFromIndex:@"root=".length];
            return value.stringByRemovingPercentEncoding ?: value;
        }
    }
    return nil;
}

// 命中 metis_ 命名空间即消费（无效 root 也由本方拒绝，不交给系统打开设置页）；
// 非本命名空间的 URL 返回 NO，由调用方原样放行。
static BOOL MTConsumeRouteURL(NSURL *url, MTOpenCompletion completion) {
    NSString *root = MTRouteRootFromURL(url).lowercaseString;
    if (![root hasPrefix:(__bridge NSString *)MTURLRoutePrefix]) return NO;
    NSString *name = MTRouteTable()[root];
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

// 目标 App 已在前台的 openURL 请求（设置页自身点击「测试」分组即此形态）：
// 不再发起完整启动事务，只走 trusted 入口，systemService 入口收不到。
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
