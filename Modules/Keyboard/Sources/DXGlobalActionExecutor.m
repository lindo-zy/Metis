#import "DXGlobalActionExecutor.h"
#import "DXGlobalPanelPolicy.h"
#import "DXGlobalPanel.h"
#import "DXShortcutsGenerator.h"
#import "DXFloatingAppSession.h"
#import "common.h"
#import <notify.h>

void DXExecuteGlobalCustomAction(NSDictionary *entry, DXSystemOpenReply reply) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"] ||
        ![DXGlobalPanel deviceUnlocked] || !DXGlobalCustomActionSupported(entry)) {
        if (reply) reply(DXSystemOpenUnavailable);
        return;
    }
    NSString *type = DXGlobalPanelString(entry[@"type"]);
    NSString *payload = DXGlobalPanelNormalizedPayload(entry[@"link"]);
    if ([type isEqual:kCustomActionTypeSystem]) { DXRunSystemAction(entry[kCustomActionSystemIdentifierKey], reply); return; }
    if ([type isEqual:kCustomActionTypeShortcut]) { DXOpenSystemShortcut(payload, entry[kCustomActionShortcutTypeKey], reply); return; }
    if ([type isEqual:kCustomActionTypeOpenApp] || (!type.length && DXIsValidBundleIdentifier(payload))) {
        if (!DXIsValidBundleIdentifier(payload)) { if (reply) reply(DXSystemOpenInvalid); return; }
        if (DXActionUsesFloatingApp(entry, YES)) { DXOpenFloatingApplication(payload, reply); return; }
        DXOpenSystemApplication(payload, reply); return;
    }
    NSURL *url = DXIsOpenableSchemeURLString(payload) ? [NSURL URLWithString:payload] : nil;
    if ([type isEqual:kCustomActionTypeURL] && (!url.host.length || ![@[@"http", @"https"] containsObject:url.scheme.lowercaseString])) url = nil;
    if (!url) { if (reply) reply(DXSystemOpenInvalid); return; }
    BOOL legacyScheme = !type.length && ![@[@"http", @"https"] containsObject:url.scheme.lowercaseString];
    if (([type isEqual:kCustomActionTypeURLScheme] || legacyScheme) && DXActionUsesFloatingApp(entry, NO)) {
        DXOpenFloatingURL(url, reply); return;
    }
    if (DXIsSensitiveOpenScheme(url.scheme)) { DXOpenSensitiveSystemURL(url, reply); return; }
    UIApplication *application = UIApplication.sharedApplication;
    if (![application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        if (reply) reply(DXSystemOpenUnavailable); return;
    }
    @try {
        // One dispatch even when another tweak swallows the completion.
        [application openURL:url options:@{} completionHandler:^(BOOL success) {
            if (reply) reply(success ? DXSystemOpenSucceeded : DXSystemOpenFailed);
        }];
    } @catch (__unused NSException *exception) { if (reply) reply(DXSystemOpenFailed); }
}
