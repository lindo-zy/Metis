#import "MTGlobalActionExecutor.h"
#import "MTGlobalPanelPolicy.h"
#import "MTGlobalPanel.h"
#import "MTShortcutsGenerator.h"
#import "MTFloatingAppSession.h"
#import "MTJavaScriptHost.h"
#import "common.h"
#import <notify.h>

// 无输入框 JS 的 open 结果映射：app 走系统打开，url 在 SB 直接 openURL。
static void MTExecuteSessionlessJSOpen(NSString *kind, NSString *payload) {
    if ([kind isEqual:@"app"]) {
        if (MTIsValidBundleIdentifier(payload)) MTOpenSystemApplication(payload, nil);
        return;
    }
    if (!MTIsOpenableSchemeURLString(payload)) return;
    NSURL *url = [NSURL URLWithString:payload];
    if (MTIsSensitiveOpenScheme(url.scheme)) { MTOpenSensitiveSystemURL(url, nil); return; }
    UIApplication *application = UIApplication.sharedApplication;
    if (![application respondsToSelector:@selector(openURL:options:completionHandler:)]) return;
    @try {
        [application openURL:url options:@{} completionHandler:nil];
    } @catch (__unused NSException *exception) {
    }
}

void MTExecuteGlobalCustomAction(NSDictionary *entry, MTSystemOpenReply reply) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"] ||
        ![MTGlobalPanel deviceUnlocked] || !MTGlobalCustomActionSupported(entry)) {
        if (reply) reply(MTSystemOpenUnavailable);
        return;
    }
    NSString *type = MTGlobalPanelString(entry[@"type"]);
    // 无输入框 JavaScript：输入取系统剪切板、输出 copy；引擎异步运行，
    // 「succeeded」只表示已提交给执行引擎（03 §7 提交边界语义）。
    if ([type isEqual:kCustomActionTypeJavaScript]) {
        [MTJavaScriptHost startSessionlessEntry:entry
                                           open:MTExecuteSessionlessJSOpen
                                          error:^(NSString *message) {
            NSLog(@"[MetisKeyboard][GlobalPanel] sessionless-js failed: %@", message);
        }];
        if (reply) reply(MTSystemOpenSucceeded);
        return;
    }
    NSString *payload = MTGlobalPanelNormalizedPayload(entry[@"link"]);
    if ([type isEqual:kCustomActionTypeSystem]) { MTRunSystemAction(entry[kCustomActionSystemIdentifierKey], reply); return; }
    if ([type isEqual:kCustomActionTypeShortcut]) { MTOpenSystemShortcut(payload, entry[kCustomActionShortcutTypeKey], reply); return; }
    if ([type isEqual:kCustomActionTypeOpenApp] || (!type.length && MTIsValidBundleIdentifier(payload))) {
        if (!MTIsValidBundleIdentifier(payload)) { if (reply) reply(MTSystemOpenInvalid); return; }
        if (MTActionUsesFloatingApp(entry, YES)) { MTOpenFloatingApplication(payload, reply); return; }
        MTOpenSystemApplication(payload, reply); return;
    }
    NSURL *url = MTIsOpenableSchemeURLString(payload) ? [NSURL URLWithString:payload] : nil;
    if ([type isEqual:kCustomActionTypeURL] && (!url.host.length || ![@[@"http", @"https"] containsObject:url.scheme.lowercaseString])) url = nil;
    if (!url) { if (reply) reply(MTSystemOpenInvalid); return; }
    BOOL legacyScheme = !type.length && ![@[@"http", @"https"] containsObject:url.scheme.lowercaseString];
    if (([type isEqual:kCustomActionTypeURLScheme] || legacyScheme) && MTActionUsesFloatingApp(entry, NO)) {
        MTOpenFloatingURL(url, reply); return;
    }
    if (MTIsSensitiveOpenScheme(url.scheme)) { MTOpenSensitiveSystemURL(url, reply); return; }
    UIApplication *application = UIApplication.sharedApplication;
    if (![application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        if (reply) reply(MTSystemOpenUnavailable); return;
    }
    @try {
        // One dispatch even when another tweak swallows the completion.
        [application openURL:url options:@{} completionHandler:^(BOOL success) {
            if (reply) reply(success ? MTSystemOpenSucceeded : MTSystemOpenFailed);
        }];
    } @catch (__unused NSException *exception) { if (reply) reply(MTSystemOpenFailed); }
}
