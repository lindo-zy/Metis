#import "MTGlobalActionExecutor.h"
#import "MTGlobalPanelPolicy.h"
#import "MTGlobalPanel.h"
#import "MTShortcutsGenerator.h"
#import "MTFloatingAppSession.h"
#import "common.h"
#import <notify.h>

void MTExecuteGlobalCustomAction(NSDictionary *entry, MTSystemOpenReply reply) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"] ||
        ![MTGlobalPanel deviceUnlocked] || !MTGlobalCustomActionSupported(entry)) {
        if (reply) reply(MTSystemOpenUnavailable);
        return;
    }
    NSString *type = MTGlobalPanelString(entry[@"type"]);
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
