#import "../Common/MTShellXBridge.h"
#import "../Common/MTConstants.h"
#import "../Common/MTCaptureLog.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>

// SHELLX 出向桥实现（依据 SHELLX 插件文档 2/3 节 + ShellX 3.1.1 逆向报告 2.1/2.2 节）。
// 与入向注册（MTShellXPlugin）不同，这里不触碰 SHELLX 的 ObjC 接口：通知类动作只发
// Darwin 通知（文档约定 SHELLX 两个中心都监听，调用方每次只发一条），URL 类动作经
// SpringBoard 的 UIApplication openURL 打开 prefs:// 路由（快捷指令同链路，SHELLX 在
// URL 分发层拦截）。名与路由常量集中在 MTConstants，逐字取自 SHELLX 插件文档。
// 探测不设重试链：调用时机全部是用户主动交互，远晚于 SpringBoard 注入期。
// 工具栏按钮显隐不在此判定：由 MTEditorOrder.shellXInstalled 统一（装了就显示）。

@implementation MTShellXBridge

+ (BOOL)isInstalled {
    return objc_getClass("SHELLXPluginManager") != nil;
}

+ (NSString *)notificationNameForAction:(MTShellXAction)action {
    switch (action) {
        case MTShellXActionArea:      return (__bridge NSString *)MTShellXTriggerArea;
        case MTShellXActionInstant:   return (__bridge NSString *)MTShellXTriggerInstant;
        case MTShellXActionFreeze:    return (__bridge NSString *)MTShellXTriggerFreeze;
        case MTShellXActionHistory:   return (__bridge NSString *)MTShellXTriggerHistory;
        case MTShellXActionOpenLast:  return (__bridge NSString *)MTShellXTriggerOpenLast;
        case MTShellXActionClose:     return (__bridge NSString *)MTShellXTriggerClose;
        // 整屏截一张走 AssistiveScreenshot 通知：真机实测该通知即整屏截一张（2026-10-07
        // 用户核对），与逆向报告「通知=套壳截图」的推断相反，以真机为准。
        case MTShellXActionFullShot:  return (__bridge NSString *)MTShellXTriggerAssistive;
        case MTShellXActionLongShot:
        case MTShellXActionMark:
        case MTShellXActionEdit:
        case MTShellXActionAI2:
        case MTShellXActionTranslate:
        case MTShellXActionScan:
        case MTShellXActionAssistive:
            return nil;   // 走 prefs:// 路由
    }
    return nil;
}

+ (NSURL *)urlForAction:(MTShellXAction)action {
    CFStringRef route = NULL;
    switch (action) {
        case MTShellXActionLongShot:  route = MTShellXRouteLong; break;
        // 套壳截图走 shellx_full 路由：真机实测该路由即套壳截图（2026-10-07 用户核对），
        // 与官方文档「shellx_full=整屏截一张」的表述相反，以真机为准。
        case MTShellXActionAssistive: route = MTShellXRouteFull; break;
        case MTShellXActionMark:      route = MTShellXRouteMark; break;
        case MTShellXActionEdit:      route = MTShellXRouteEdit; break;
        case MTShellXActionAI2:       route = MTShellXRouteAI2; break;
        case MTShellXActionTranslate: route = MTShellXRouteTranslate; break;
        case MTShellXActionScan:      route = MTShellXRouteScan; break;
        case MTShellXActionArea:
        case MTShellXActionInstant:
        case MTShellXActionFreeze:
        case MTShellXActionHistory:
        case MTShellXActionOpenLast:
        case MTShellXActionClose:
        case MTShellXActionFullShot:
            return nil;   // 通知类动作不走 URL
    }
    if (!route) return nil;
    return [NSURL URLWithString:(__bridge NSString *)route];
}

+ (void)notifyAction:(MTShellXAction)action {
    if (![self isInstalled]) {
        MTCaptureLogInfo(@"shellx notify skipped: not installed");
        return;
    }
    NSString *name = [self notificationNameForAction:action];
    if (name) {
        notify_post(name.UTF8String);
        MTCaptureLogInfo(@"shellx notify posted: %@", name);
        return;
    }
    NSURL *url = [self urlForAction:action];
    if (!url) return;
    // SpringBoard 本身是 UIApplication 子类实例，openURL 走系统 URL 分发层；
    // 外部 URL scheme 入口已移除；SHELLX 触发经其自身通知别名进入。
    // 回调线程不确定，只打日志。SHELLX 未拦截时系统会打开设置页对应面板，可据此排查。
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        MTCaptureLogInfo(@"shellx url opened: %@ success=%d", url, success);
    }];
}

@end
