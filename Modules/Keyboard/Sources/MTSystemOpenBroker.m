#import "MTSystemOpenBroker.h"
#import "MTSensitiveURLExecutor.h"
#import "MTQuickActionProvider.h"
#import "MTSystemActionCatalog.h"
#import "MTSystemActionExecutor.h"
#import "MTPanelControlState.h"
#import "MTKeyboardPanelPreferences.h"
#import "MTPanelRegistry.h"
#import "MTStatusBarGesturePolicy.h"
#import "MTGlobalPanelPolicy.h"
#import "MTGlobalPanel.h"
#import "MTGlobalActionExecutor.h"
#import "MTFloatingApp.h"
#import <notify.h>
#import "common.h"
#import <objc/message.h>
#import <dlfcn.h>

BOOL MTIsSensitiveOpenScheme(NSString *scheme) {
    NSString *lower = scheme.lowercaseString;
    return [lower isEqualToString:@"prefs"] || [lower isEqualToString:@"app-prefs"] ||
           [lower isEqualToString:@"itms-services"];
}

static BOOL MTIsSystemOpenServerProcess(void) {
    return [NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"];
}

// Accessed on the main queue; NSProgress cancellation can be read by the RPC
// worker. A newer system action invalidates an older pending foreground step.
static NSProgress *MTCurrentSystemOpenRequest;

static NSProgress *MTBeginSystemOpenOperation(void) {
    [MTCurrentSystemOpenRequest cancel];
    MTCancelSystemActionConfirmation();
    MTCurrentSystemOpenRequest = [NSProgress discreteProgressWithTotalUnitCount:1];
    return MTCurrentSystemOpenRequest;
}

static MTSystemOpenResult MTActivateSystemApplication(NSString *bundleIdentifier) {
    // Activate inside SpringBoard through the same native selector used by
    // local PullOver-X. No URL event is sent through WeChat and no invented
    // __LaunchURL option is involved. Check the runtime BOOL return ABI;
    // historical headers disagree about this method's return type.
    UIApplication *application = UIApplication.sharedApplication;
    SEL launch = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    NSMethodSignature *signature = [application methodSignatureForSelector:launch];
    const char *returnType = signature.methodReturnType;
    if (!application || ![application respondsToSelector:launch] || signature.numberOfArguments != 4 || !returnType ||
        (strcmp(returnType, @encode(BOOL)) != 0 && strcmp(returnType, "c") != 0)) {
        return MTSystemOpenUnavailable;
    }
    NSLog(@"[TypeXSB] native application dispatch bundleID=%@", bundleIdentifier);
    BOOL opened = ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(application, launch, bundleIdentifier, NO);
    NSLog(@"[TypeXSB] native application bundleID=%@ result=%d", bundleIdentifier, opened);
    return opened ? MTSystemOpenSucceeded : MTSystemOpenFailed;
}

// Runs only in SpringBoard, on the main queue. The requester never supplies
// an Objective-C selector or an arbitrary launch-options dictionary.
static void MTPerformSystemOpen(NSDictionary *request, MTSystemOpenReply reply) {
    if (!MTIsSystemOpenServerProcess() || !NSThread.isMainThread) {
        reply(MTSystemOpenUnavailable);
        return;
    }
    NSString *kind = request[@"kind"];
    NSString *payload = request[@"payload"];
    if (![kind isKindOfClass:NSString.class] || ![payload isKindOfClass:NSString.class] || !payload.length) {
        reply(MTSystemOpenInvalid);
        return;
    }
    if ([kind isEqual:@"floating-shelf-restore"]) {
        NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
        id control = data.length <= 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![control isKindOfClass:NSDictionary.class] || !MTIsValidBundleIdentifier(control[@"bundleID"]) ||
            ![control[@"revision"] isKindOfClass:NSNumber.class]) { reply(MTSystemOpenInvalid); return; }
        NSDate *deadline = [NSDate dateWithTimeIntervalSince1970:[request[@"created"] doubleValue] + MTSystemOpenRequestTTL];
        MTRestoreFloatingAppFromShelf(control[@"bundleID"], [control[@"revision"] unsignedLongLongValue], deadline, reply);
        return;
    }
    if ([kind isEqual:@"floating-application"] || [kind isEqual:@"floating-url"]) {
        BOOL isURL = [kind isEqual:@"floating-url"];
        NSURL *url = isURL && MTIsOpenableSchemeURLString(payload) ? [NSURL URLWithString:payload] : nil;
        NSString *identifier = isURL ? MTFloatingBundleIdentifierForURL(url) : payload;
        if (payload.length > (isURL ? 4096 : 256) || (isURL && !url) || !MTIsValidBundleIdentifier(identifier)) {
            reply(MTSystemOpenInvalid); return;
        }
        NSDate *deadline = [NSDate dateWithTimeIntervalSince1970:[request[@"created"] doubleValue] + MTSystemOpenRequestTTL];
        MTPresentFloatingApplication(identifier, url, deadline, reply);
        return;
    }
    if ([kind isEqual:@"statusbar-gesture"]) {
        NSTimeInterval age = NSDate.date.timeIntervalSince1970 - [request[@"created"] doubleValue];
        if (!(age >= 0 && age <= 1.5)) { reply(MTSystemOpenExpired); return; }
        NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
        id binding = data.length <= 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (!MTStatusBarRequestValid(binding)) { reply(MTSystemOpenInvalid); return; }
        MTPrefsManager *manager = MTPrefsManager.sharedInstance;
        [manager reload];
        NSString *selector = manager.preferencesAvailable ? MTStatusBarRequestSelector(manager.prefs, binding, kEnabledkey) : nil;
        if (!selector || ![MTGlobalPanel deviceUnlocked] || [MTGlobalPanel.sharedInstance isVisible]) {
            NSLog(@"[MetisKeyboard][StatusBarGesture] dispatch rejected slot=%@ gate=binding/lock/panel", binding[@"slot"]);
            reply(MTSystemOpenUnavailable); return;
        }
        NSLog(@"[MetisKeyboard][StatusBarGesture] dispatch slot=%@", binding[@"slot"]);
        BOOL isPanel = MTPanelAllowed(manager.prefs, selector, MTPanelGestureKind);
        if (isPanel) {
            [MTGlobalPanel.sharedInstance presentPanelSelector:selector fromWindow:nil origin:@"statusbar"];
            reply([MTGlobalPanel.sharedInstance isVisible] ? MTSystemOpenSucceeded : MTSystemOpenUnavailable);
            return;
        }
        id definitions = manager.prefs[kLinkActionskey];
        for (id entry in [definitions isKindOfClass:NSArray.class] ? definitions : @[]) {
            if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"selector"] isEqual:selector]) continue;
            if (!MTIsLinkActionSelector(selector) || !MTGlobalCustomActionSupported(entry)) { reply(MTSystemOpenInvalid); return; }
            MTExecuteGlobalCustomAction(entry, reply);
            return;
        }
        reply(MTSystemOpenInvalid);
        return;
    }
    if ([kind isEqual:@"panel-control"]) {
        NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *control = data.length <= 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (!MTPanelControlRequestValid(control)) { reply(MTSystemOpenInvalid); return; }
        NSTimeInterval age = NSDate.date.timeIntervalSince1970 - [request[@"created"] doubleValue];
        // A drag queued behind a busy SpringBoard must not be applied later.
        if (!(age >= 0 && age <= 1.5)) { reply(MTSystemOpenExpired); return; }
        MTPrefsManager *manager = MTPrefsManager.sharedInstance;
        if (!manager.preferencesAvailable) [manager reload];
        // Toolbar gesture switches no longer control panels opened by buttons.
        // 手势面板恒定启用（原 kMTPanelGlobalEnabled 开关入口已移除），这里统一只校验总开关。
        if (!manager.preferencesAvailable || !MTKeyboardPanelBool(manager.prefs, kEnabledkey, YES)) { reply(MTSystemOpenUnavailable); return; }
        int token = NOTIFY_TOKEN_INVALID;
        NSString *slot = MTPanelControlStateSlot(control[@"token"]);
        uint64_t word = 0;
        if (notify_register_check(slot.UTF8String, &token) != NOTIFY_STATUS_OK) { reply(MTSystemOpenUnavailable); return; }
        if (notify_get_state(token, &word) != NOTIFY_STATUS_OK || word != MTPanelControlPendingWord) {
            notify_cancel(token); reply(MTSystemOpenExpired); return;
        }
        MTSystemOpenResult result = MTSystemOpenFailed;
        @try {
            result = MTPerformPanelSystemControl(control[@"action"], control[@"value"]);
            NSDictionary *state = MTReadPanelSystemControlState();
            if (!state || notify_set_state(token, MTPanelControlEncodeState(state)) != NOTIFY_STATUS_OK)
                result = MTSystemOpenUnavailable;
        } @finally { notify_cancel(token); }
        if (![control[@"action"] isEqual:@"state"] || result != MTSystemOpenSucceeded)
            NSLog(@"[MetisKeyboard][PanelControl] action=%@ result=%llu", control[@"action"], (unsigned long long)result);
        reply(result);
        return;
    }
    if ([kind isEqualToString:@"system-action"]) {
        NSDictionary *definition = MTSystemActionDefinition(payload);
        if (!definition) { reply(MTSystemOpenInvalid); return; }
        NSTimeInterval age = NSDate.date.timeIntervalSince1970 - [request[@"created"] doubleValue];
        if (!(age >= 0 && age <= MTSystemOpenRequestTTL)) { reply(MTSystemOpenExpired); return; }
        MTPrefsManager *manager = MTPrefsManager.sharedInstance;
        if (!manager.preferencesAvailable) [manager reload];
        if (!manager.preferencesAvailable) { reply(MTSystemOpenUnavailable); return; }
        if (!MTSystemActionIsConfigured(manager.prefs[kLinkActionskey], payload, kLinkActionSelectorPrefix)) {
            reply(MTSystemOpenInvalid); return;
        }
        if (MTSystemActionIsRecording(payload)) {
            // ReplayKit acknowledges asynchronously. Its separate flight guard
            // survives unrelated foreground requests and never retries on timeout.
            MTPerformSystemRecordingAction(payload, reply);
            return;
        }
        NSProgress *operation = MTBeginSystemOpenOperation();
        if ([definition[@"destructive"] boolValue]) {
            // A transport success acknowledges the trusted SpringBoard prompt.
            // Execution requires a fresh user choice inside that prompt; callers
            // cannot bypass it by forging a client-side "confirmed" flag.
            // 跨进程调用拿不到调用方 VC，宿主由执行器自行挑选。
            reply(MTConfirmSystemExitActionFrom(payload, operation, nil) ? MTSystemOpenSucceeded : MTSystemOpenUnavailable);
        } else {
            MTSystemOpenResult result = MTPerformSystemAction(payload);
            NSLog(@"[MetisKeyboard][SystemAction] id=%@ result=%llu", payload, (unsigned long long)result);
            reply(result);
        }
        return;
    }
    if ([kind isEqualToString:@"quick-action"]) {
        NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
        if (!data.length || data.length > 4096) { reply(MTSystemOpenInvalid); return; }
        id fields = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![fields isKindOfClass:NSDictionary.class]) { reply(MTSystemOpenInvalid); return; }
        NSString *bundleIdentifier = fields[@"bundleID"];
        NSString *shortcutType = fields[@"shortcutType"];
        if (!MTIsValidBundleIdentifier(bundleIdentifier) || bundleIdentifier.length > 256 ||
            !MTIsValidAppShortcutType(shortcutType)) { reply(MTSystemOpenInvalid); return; }
        NSTimeInterval age = [NSDate date].timeIntervalSince1970 - [request[@"created"] doubleValue];
        if (!(age >= 0 && age <= MTSystemOpenRequestTTL)) { reply(MTSystemOpenExpired); return; }
        MTBeginSystemOpenOperation();
        reply([MTQuickActionProvider activateShortcutWithBundleIdentifier:bundleIdentifier type:shortcutType]);
        return;
    }
    if ([kind isEqualToString:@"sensitive-url"]) {
        NSURL *url = [NSURL URLWithString:payload];
        if (!url || payload.length > 2048 || !MTIsSensitiveOpenScheme(url.scheme)) { reply(MTSystemOpenInvalid); return; }
        typedef bool (*MTSensitiveOpen)(CFURLRef, char);
        MTSensitiveOpen openSensitive = (MTSensitiveOpen)dlsym(RTLD_DEFAULT, "SBSOpenSensitiveURLAndUnlock");
        if (!openSensitive) { reply(MTSystemOpenUnavailable); return; }
        // Preserve the original deadline across the worker queue. A queued RPC
        // cannot become a surprise open after the caller's request expired.
        NSNumber *created = request[@"created"];
        NSDate *deadline = [NSDate dateWithTimeIntervalSince1970:created.doubleValue + MTSystemOpenRequestTTL];
        MTExecuteSensitiveURL(url, deadline, MTBeginSystemOpenOperation(), ^BOOL(NSURL *sensitiveURL) {
            return openSensitive((__bridge CFURLRef)sensitiveURL, 0);
        }, reply);
        return;
    }
    if (![kind isEqualToString:@"application"] || payload.length > 256 || !MTIsValidBundleIdentifier(payload)) {
        reply(MTSystemOpenInvalid);
        return;
    }

    MTBeginSystemOpenOperation();
    reply(MTActivateSystemApplication(payload));
}

static void MTSubmitSystemOpen(NSString *kind, NSString *payload, MTSystemOpenReply reply) {
    if (MTIsSystemOpenServerProcess()) {
        NSDictionary *request = @{@"kind": kind, @"payload": payload ?: @"",
                                   @"created": @([NSDate date].timeIntervalSince1970)};
        dispatch_async(dispatch_get_main_queue(), ^{
            __block BOOL completed = NO;
            MTSystemOpenReply finish = ^(MTSystemOpenResult result) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completed) return;
                    completed = YES;
                    if (reply) reply(result);
                });
            };
            @try { MTPerformSystemOpen(request, finish); }
            @catch (NSException *exception) {
                NSLog(@"[TypeXSB] direct exception=%@", exception.name);
                finish(MTSystemOpenFailed);
            }
        });
        return;
    }
    MTSendDarwinOpenRequest(kind, payload, reply);
}

void MTRequestStatusBarGesture(NSString *slot, NSString *expectedSelector, BOOL landscape, MTSystemOpenReply reply) {
    NSDictionary *request = @{@"slot": slot ?: @"", @"selector": expectedSelector ?: @"", @"landscape": @(landscape)};
    if (!MTStatusBarRequestValid(request)) { if (reply) reply(MTSystemOpenInvalid); return; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    if (!data.length || data.length > 1024) { if (reply) reply(MTSystemOpenInvalid); return; }
    MTSubmitSystemOpen(@"statusbar-gesture", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], reply);
}

void MTOpenSystemApplication(NSString *bundleIdentifier, MTSystemOpenReply reply) {
    MTSubmitSystemOpen(@"application", bundleIdentifier, reply);
}

void MTRestoreFloatingApplication(NSString *identifier, uint64_t revision, MTSystemOpenReply reply) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"bundleID": identifier ?: @"", @"revision": @(revision)} options:0 error:nil];
    MTSubmitSystemOpen(@"floating-shelf-restore", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], reply);
}
void MTOpenFloatingApplication(NSString *bundleIdentifier, MTSystemOpenReply reply) {
    MTSubmitSystemOpen(@"floating-application", bundleIdentifier, reply);
}

void MTOpenFloatingURL(NSURL *url, MTSystemOpenReply reply) {
    MTSubmitSystemOpen(@"floating-url", url.absoluteString, reply);
}

void MTRunSystemAction(NSString *identifier, MTSystemOpenReply reply) {
    if (!MTSystemActionDefinition(identifier)) {
        if (reply) dispatch_async(dispatch_get_main_queue(), ^{ reply(MTSystemOpenInvalid); });
        return;
    }
    if ([identifier isEqual:@"image-edit"] && !NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ MTRunSystemAction(identifier, reply); });
        return;
    }
    if ([identifier isEqual:@"image-edit"]) {
        // End the input session in the originating app before the SB editor opens.
        Class cls = NSClassFromString(@"UIKeyboardImpl");
        SEL active = NSSelectorFromString(@"activeInstance"), dismiss = NSSelectorFromString(@"dismissKeyboard");
        @try {
            id keyboard = [cls respondsToSelector:active] ? ((id (*)(id, SEL))objc_msgSend)(cls, active) : nil;
            if ([keyboard respondsToSelector:dismiss]) ((void (*)(id, SEL))objc_msgSend)(keyboard, dismiss);
        } @catch (__unused NSException *exception) {
            NSLog(@"[MetisKeyboard][ImageEditor] source keyboard dismiss failed");
        }
    }
    MTSubmitSystemOpen(@"system-action", identifier, reply);
}

void MTOpenSensitiveSystemURL(NSURL *url, MTSystemOpenReply reply) {
    MTSubmitSystemOpen(@"sensitive-url", url.absoluteString, reply);
}

BOOL MTStartSystemOpenBroker(void) {
    if (!MTIsSystemOpenServerProcess()) return NO;
    return MTStartDarwinOpenServer(^(NSDictionary *request, MTSystemOpenReply reply) {
        MTPerformSystemOpen(request, reply);
    });
}

void MTOpenSystemShortcut(NSString *bundleIdentifier, NSString *shortcutType, MTSystemOpenReply reply) {
    if (!MTIsValidBundleIdentifier(bundleIdentifier) || bundleIdentifier.length > 256 ||
        !MTIsValidAppShortcutType(shortcutType)) {
        if (reply) dispatch_async(dispatch_get_main_queue(), ^{ reply(MTSystemOpenInvalid); });
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"bundleID": bundleIdentifier, @"shortcutType": shortcutType}
                                                 options:0 error:nil];
    if (!data.length || data.length > 4096) {
        if (reply) dispatch_async(dispatch_get_main_queue(), ^{ reply(MTSystemOpenInvalid); });
        return;
    }
    MTSubmitSystemOpen(@"quick-action", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], reply);
}

// NSProgress may dispatch cancellationHandler asynchronously. Revoke the
// request-owned slot synchronously when the keyboard panel closes on main.
@interface MTPanelControlOperation : NSProgress
@property(nonatomic, copy) void (^invalidateSlot)(void);
@end
@implementation MTPanelControlOperation
- (void)cancel {
    void (^invalidate)(void) = self.invalidateSlot;
    if (invalidate) {
        if (NSThread.isMainThread) invalidate();
        else dispatch_async(dispatch_get_main_queue(), invalidate);
    }
    [super cancel];
}
@end

NSProgress *MTRequestPanelSystemControl(NSString *action, NSNumber *value, NSString *source, MTPanelSystemControlReply reply) {
    MTPanelControlOperation *operation = [[MTPanelControlOperation alloc] initWithParent:nil userInfo:nil];
    operation.totalUnitCount = 1;
    if (!NSThread.isMainThread) {
        if (reply) dispatch_async(dispatch_get_main_queue(), ^{ reply(MTSystemOpenUnavailable, nil); });
        return operation;
    }
    NSMutableDictionary *request = [@{@"action": action ?: @"", @"source": source ?: @"", @"token": NSUUID.UUID.UUIDString} mutableCopy];
    if (value) request[@"value"] = value;
    if (!MTPanelControlRequestValid(request)) {
        if (reply) dispatch_async(dispatch_get_main_queue(), ^{ if (!operation.cancelled) reply(MTSystemOpenInvalid, nil); });
        return operation;
    }
    int token = NOTIFY_TOKEN_INVALID;
    NSString *slot = MTPanelControlStateSlot(request[@"token"]);
    if (notify_register_check(slot.UTF8String, &token) != NOTIFY_STATUS_OK) {
        if (reply) dispatch_async(dispatch_get_main_queue(), ^{ if (!operation.cancelled) reply(MTSystemOpenUnavailable, nil); });
        return operation;
    }
    __block BOOL cleaned = NO;
    void (^cleanup)(void) = ^{
        if (cleaned) return;
        cleaned = YES;
        notify_set_state(token, 0);
        notify_cancel(token);
    };
    operation.invalidateSlot = cleanup;
    if (notify_set_state(token, MTPanelControlPendingWord) != NOTIFY_STATUS_OK) {
        cleanup();
        if (reply) dispatch_async(dispatch_get_main_queue(), ^{ if (!operation.cancelled) reply(MTSystemOpenUnavailable, nil); });
        return operation;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    MTSubmitSystemOpen(@"panel-control", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], ^(MTSystemOpenResult result) {
        uint64_t word = 0;
        NSDictionary *state = !cleaned && notify_get_state(token, &word) == NOTIFY_STATUS_OK ? MTPanelControlDecodeState(word) : nil;
        cleanup();
        if (result == MTSystemOpenSucceeded && !state) result = MTSystemOpenUnavailable;
        if (!operation.cancelled && reply) reply(result, state);
    });
    return operation;
}
