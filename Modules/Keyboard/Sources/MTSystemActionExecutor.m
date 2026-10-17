#import "MTSystemActionExecutor.h"
#import "MTSystemActionCatalog.h"
#import "MTSystemActionCompatibility.h"
#import "MTSystemRecordingSession.h"
#import "common.h"
#import "MTCaptureIntegration.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#include <signal.h>
#include <unistd.h>

static __weak UIAlertController *MTSystemActionConfirmation;

void MTCancelSystemActionConfirmation(void) {
    if (!NSThread.isMainThread) return;
    [MTSystemActionConfirmation dismissViewControllerAnimated:NO completion:nil];
    MTSystemActionConfirmation = nil;
}

BOOL MTConfirmSystemExitAction(NSString *action, NSProgress *operation) {
    if (!MTSystemExitActionAvailable(action) || ![MTSystemActionDefinition(action)[@"destructive"] boolValue]) return NO;
    UIWindow *window = MTKeyWindow();
    UIViewController *presenter = window.rootViewController;
    while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed)
        presenter = presenter.presentedViewController;
    if (!presenter || !window || window.hidden || presenter.view.window != window) return NO;
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSString *title = [bundle localizedStringForKey:MTSystemActionDefinition(action)[@"title"] value:action table:nil];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:[bundle localizedStringForKey:@"SYSTEM_ACTION_CONFIRM" value:@"Continue?" table:nil]
        preferredStyle:UIAlertControllerStyleAlert];
    NSTimeInterval deadline = NSDate.date.timeIntervalSince1970 + 60;
    __weak UIWindow *originalWindow = window;
    __weak UIViewController *originalPresenter = presenter;
    __weak UIAlertController *originalAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"CANCEL" value:@"Cancel" table:nil]
        style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *choice) {
            if (MTSystemActionConfirmation == originalAlert) MTSystemActionConfirmation = nil;
            [operation cancel];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"ANSWER_YES" value:@"Continue" table:nil]
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *choice) {
            BOOL current = MTSystemActionConfirmation == originalAlert;
            if (current) MTSystemActionConfirmation = nil;
            UIWindow *source = originalWindow;
            if (!current || operation.cancelled || !source || source.hidden || MTKeyWindow() != source ||
                originalPresenter.view.window != source || NSDate.date.timeIntervalSince1970 > deadline) return;
            MTSystemOpenResult result = MTPerformSystemAction(action);
            NSLog(@"[MetisKeyboard][SystemAction] confirmed id=%@ result=%llu", action, (unsigned long long)result);
            if (result != MTSystemOpenSucceeded) {
                UIAlertController *error = [UIAlertController alertControllerWithTitle:title
                    message:[bundle localizedStringForKey:@"SYSTEM_ACTION_UNAVAILABLE" value:@"Unavailable" table:nil]
                    preferredStyle:UIAlertControllerStyleAlert];
                [error addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"ANSWER_OK" value:@"OK" table:nil]
                    style:UIAlertActionStyleDefault handler:nil]];
                UIAlertController *prompt = originalAlert;
                [prompt dismissViewControllerAnimated:YES completion:^{
                    UIWindow *currentWindow = originalWindow;
                    UIViewController *currentPresenter = originalPresenter;
                    if (operation.cancelled || !currentWindow || currentWindow.hidden || MTKeyWindow() != currentWindow ||
                        currentPresenter.view.window != currentWindow || currentPresenter.presentedViewController ||
                        NSDate.date.timeIntervalSince1970 > deadline) return;
                    [currentPresenter presentViewController:error animated:YES completion:nil];
                }];
            }
        }]];
    MTSystemActionConfirmation = alert;
    [presenter presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (MTSystemActionConfirmation != originalAlert || !originalAlert) return;
        [operation cancel];
        MTCancelSystemActionConfirmation();
    });
    return YES;
}

static void MTLoadSystemActionFrameworks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *name in @[@"BluetoothManager", @"DoNotDisturb", @"DoNotDisturbKit", @"AVFCapture"]) {
            NSString *path = [NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%@.framework/%@", name, name];
            if (!dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_GLOBAL))
                NSLog(@"[MetisKeyboard][SystemAction] framework unavailable name=%@", name);
        }
        dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY | RTLD_GLOBAL);
    });
}

static id MTSystemShared(NSString *className, NSString *selector) {
    id result = nil;
    return MTSystemInvoke(NSClassFromString(className), selector, @[], &result) ? result : nil;
}

void MTPerformSystemRecordingAction(NSString *action, MTSystemOpenReply reply) {
    if (!MTSystemActionIsRecording(action)) { if (reply) reply(MTSystemOpenInvalid); return; }
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"] || !NSThread.isMainThread) {
        if (reply) reply(MTSystemOpenUnavailable);
        return;
    }
    static dispatch_once_t once;
    static MTSystemRecordingSession *session;
    dispatch_once(&once, ^{
        if (!dlopen("/System/Library/Frameworks/ReplayKit.framework/ReplayKit", RTLD_LAZY | RTLD_GLOBAL))
            NSLog(@"[MetisKeyboard][SystemRecording] framework unavailable name=ReplayKit");
        session = [MTSystemRecordingSession new];
    });
    [session toggleRecorder:MTSystemShared(@"RPScreenRecorder", @"sharedRecorder")
        microphoneEnabled:[action isEqual:@"screen-recording-microphone"] reply:reply];
}

static id MTSystemObjectIvar(id owner, const char *name) {
    Ivar ivar = owner ? class_getInstanceVariable([owner class], name) : NULL;
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(owner, ivar) : nil;
}
static id MTSystemVolumeControl(void) {
    Class cls = NSClassFromString(@"SBVolumeControl");
    if ([cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
        id control = MTSystemShared(@"SBVolumeControl", @"sharedInstance");
        if (control) return control;
    }
    return MTSystemObjectIvar(MTSystemShared(@"SBMediaController", @"sharedInstance"), "_volumeControl") ?:
        MTSystemObjectIvar(MTSystemShared(@"SBUIController", @"sharedInstance"), "_volumeControl");
}
static id MTSystemFlashlight(void) {
    static id flashlight;
    if (!flashlight) flashlight = [NSClassFromString(@"AVFlashlight") new];
    return flashlight;
}
static id MTSystemRingerControl(void) {
    id workspace = MTSystemShared(@"SBMainWorkspace", @"sharedInstance"), ringer = nil;
    if ([workspace respondsToSelector:NSSelectorFromString(@"ringerControl")])
        MTSystemInvoke(workspace, @"ringerControl", @[], &ringer);
    return ringer ?: MTSystemObjectIvar(MTSystemVolumeControl(), "_ringerControl");
}
static NSString *MTSystemAvailableGetter(id target, NSArray<NSString *> *names) {
    for (NSString *name in names) if ([target respondsToSelector:NSSelectorFromString(name)]) return name;
    return nil;
}
static NSNumber *MTSystemPanelValue(id target, NSString *getter) {
    id value = nil;
    return getter && [target respondsToSelector:NSSelectorFromString(getter)] &&
        MTSystemInvoke(target, getter, @[], &value) && [value isKindOfClass:NSNumber.class] ? value : nil;
}
static id MTSystemPanelVolumeTarget(void) {
    id media = MTSystemShared(@"SBMediaController", @"sharedInstance");
    if ([media respondsToSelector:NSSelectorFromString(@"volume")] && [media respondsToSelector:NSSelectorFromString(@"setVolume:")]) return media;
    return MTSystemVolumeControl();
}

static MTSystemOpenResult MTSystemToggle(id target, NSString *getter, NSString *setter) {
    id state = nil;
    if (!MTSystemInvoke(target, getter, @[], &state) || ![state isKindOfClass:NSNumber.class]) return MTSystemOpenUnavailable;
    return MTSystemCall(target, setter, @[@(![state boolValue])]);
}

static BOOL MTSafeModeHandlerLoaded(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        NSString *image = name ? [NSString stringWithUTF8String:name].lowercaseString : nil;
        if ([image containsString:@"safemode"] || [image containsString:@"mobilesafety"]) return YES;
    }
    return NO;
}

BOOL MTSystemExitActionAvailable(NSString *action) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"] || !NSThread.isMainThread) return NO;
    if ([action isEqual:@"respring-sb"]) return YES;
    if ([action isEqual:@"safe-mode"]) return MTSafeModeHandlerLoaded();
    // Use the exact userspace flag; never fall back to a full reboot or to a shell.
    // This syscall needs privileges that a particular jailbreak may not grant SB.
    if ([action isEqual:@"userspace-reboot"]) return dlsym(RTLD_DEFAULT, "reboot3") != NULL;
    id service = MTSystemShared(@"FBSSystemService", @"sharedService");
    if ([action isEqual:@"shutdown"]) return [service respondsToSelector:NSSelectorFromString(@"shutdown")];
    if ([action isEqual:@"reboot"]) return [service respondsToSelector:NSSelectorFromString(@"reboot")];
    if ([action isEqual:@"respring"]) return [service respondsToSelector:NSSelectorFromString(@"sendActions:withResult:")] &&
        [NSClassFromString(@"SBSRelaunchAction") respondsToSelector:NSSelectorFromString(@"actionWithReason:options:targetURL:")];
    return NO;
}

MTSystemOpenResult MTPerformSystemAction(NSString *action) {
    if (!MTSystemActionDefinition(action)) return MTSystemOpenInvalid;
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"] || !NSThread.isMainThread) return MTSystemOpenUnavailable;
    if (MTSystemActionDefinition(action)[@"captureNotification"])
        return MTPostCaptureSystemAction(action, MT_ROOT_PATH_NS(MTCaptureDylibPath));
    MTLoadSystemActionFrameworks();
    NSLog(@"[MetisKeyboard][SystemAction] execute id=%@", action);
    if ([action isEqual:@"previous-track"] || [action isEqual:@"next-track"]) {
        return MTSystemCall(MTSystemShared(@"SBMediaController", @"sharedInstance"), @"changeTrack:eventSource:",
            @[@([action isEqual:@"next-track"] ? 1 : -1), @0]);
    }
    if ([action isEqual:@"play-pause"]) return MTSystemCall(MTSystemShared(@"SBMediaController", @"sharedInstance"), @"togglePlayPauseForEventSource:", @[@0]);
    if ([action isEqual:@"home"]) return MTSystemCallFirstAvailable(UIApplication.sharedApplication, @[
        @[@"_simulateHomeButtonPress", @[]], @[@"_simulateHomeButtonPressWithCompletion:", @[NSNull.null]]]);
    // Enter SpringBoard's native capture path so screenshot hooks still run.
    // Its void return acknowledges dispatch, not photo-library persistence.
    if ([action isEqual:@"screenshot"]) return MTSystemCall(UIApplication.sharedApplication, @"takeScreenshot", @[]);
    if ([action isEqual:@"switcher"]) {
        id coordinator = MTSystemShared(@"SBMainSwitcherControllerCoordinator", @"sharedInstance");
        NSArray *interfaces = @[@[@"toggleSwitcherNoninteractivelyWithSource:", @[@1]],
            @[@"toggleMainSwitcherNoninteractivelyWithSource:animated:", @[@1, @YES]],
            @[@"toggleSwitcherNoninteractively", @[]]];
        BOOL supported = NO;
        for (NSArray *candidate in interfaces) supported |= [coordinator respondsToSelector:NSSelectorFromString(candidate[0])];
        if (!supported) coordinator = MTSystemShared(@"SBMainSwitcherViewController", @"sharedInstance");
        return MTSystemCallFirstAvailable(coordinator, interfaces);
    }
    if ([action isEqual:@"control-center"]) return MTSystemCallFirstAvailable(MTSystemShared(@"SBControlCenterController", @"sharedInstance"), @[
        @[@"presentAnimated:completion:", @[@YES, NSNull.null]], @[@"presentAnimated:", @[@YES]]]);
    if ([action isEqual:@"wifi"]) return MTSystemToggle(MTSystemShared(@"SBWiFiManager", @"sharedInstance"), @"wiFiEnabled", @"setWiFiEnabled:");
    if ([action isEqual:@"bluetooth"]) {
        id manager = MTSystemShared(@"BluetoothManager", @"sharedInstance");
        id powered = nil;
        if (!MTSystemInvoke(manager, @"powered", @[], &powered) || ![powered isKindOfClass:NSNumber.class]) return MTSystemOpenUnavailable;
        // Bluetooth has separate enabled and powered states. Enable its service
        // before powering on; retain the original route when setEnabled is absent.
        BOOL next = ![powered boolValue];
        if (next && [manager respondsToSelector:NSSelectorFromString(@"setEnabled:")]) {
            MTSystemOpenResult result = MTSystemCall(manager, @"setEnabled:", @[@YES]);
            if (result != MTSystemOpenSucceeded) return result;
        }
        return MTSystemCall(manager, @"setPowered:", @[@(next)]);
    }
    if ([action isEqual:@"airplane"]) return MTSystemToggle(MTSystemShared(@"SBAirplaneModeController", @"sharedInstance"), @"isInAirplaneMode", @"setInAirplaneMode:");
    if ([action isEqual:@"cellular"]) {
        typedef Boolean (*GetData)(void);
        typedef void (*SetData)(Boolean);
        GetData get = (GetData)dlsym(RTLD_DEFAULT, "CTCellularDataPlanGetIsEnabled");
        SetData set = (SetData)dlsym(RTLD_DEFAULT, "CTCellularDataPlanSetIsEnabled");
        if (!get || !set) return MTSystemOpenUnavailable;
        Boolean next = !get();
        set(next);
        // The setter has no acknowledgment; radio changes are asynchronous.
        return MTSystemOpenSucceeded;
    }
    if ([action isEqual:@"orientation-lock"]) {
        id manager = MTSystemShared(@"SBOrientationLockManager", @"sharedInstance");
        id locked = nil;
        if (!MTSystemInvoke(manager, @"isUserLocked", @[], &locked) || ![locked isKindOfClass:NSNumber.class]) return MTSystemOpenUnavailable;
        if ([locked boolValue]) return MTSystemCall(manager, @"unlock", @[]);
        UIInterfaceOrientation orientation = MTKeyWindow().windowScene.interfaceOrientation;
        if (orientation == UIInterfaceOrientationUnknown) orientation = UIInterfaceOrientationPortrait;
        return MTSystemCallFirstAvailable(manager, @[@[@"lock", @[]], @[@"lock:", @[@(orientation)]]]);
    }
    if ([action isEqual:@"dark-mode"]) return MTSystemCall(MTSystemShared(@"UIUserInterfaceStyleArbiter", @"sharedInstance"), @"toggleCurrentStyle", @[]);
    if ([action isEqual:@"brightness-up"] || [action isEqual:@"brightness-down"]) {
        UIScreen *screen = UIScreen.mainScreen;
        screen.brightness = MIN(1, MAX(0, screen.brightness + ([action isEqual:@"brightness-up"] ? 0.1 : -0.1)));
        return MTSystemOpenSucceeded;
    }
    if ([action isEqual:@"volume-up"] || [action isEqual:@"volume-down"]) {
        id volume = MTSystemVolumeControl();
        return MTSystemCall(volume, [action isEqual:@"volume-up"] ? @"increaseVolume" : @"decreaseVolume", @[]);
    }
    if ([action isEqual:@"flashlight"]) {
        id flashlight = MTSystemFlashlight();
        id level = nil;
        if (!MTSystemInvoke(flashlight, @"flashlightLevel", @[], &level) || ![level isKindOfClass:NSNumber.class]) return MTSystemOpenUnavailable;
        return MTSystemCall(flashlight, @"setFlashlightLevel:withError:", @[@([level floatValue] > 0 ? 0.0f : 1.0f), NSNull.null]);
    }
    if ([action isEqual:@"do-not-disturb"]) return MTSystemToggleDND(NSClassFromString(@"DNDStateService"), NSClassFromString(@"DNDToggleManager"));
    if (!MTSystemExitActionAvailable(action)) return MTSystemOpenUnavailable;
    if ([action isEqual:@"respring-sb"]) { exit(0); }
    if ([action isEqual:@"safe-mode"]) { return kill(getpid(), SIGSEGV) == 0 ? MTSystemOpenSucceeded : MTSystemOpenFailed; }
    if ([action isEqual:@"userspace-reboot"]) {
        typedef int (*UserReboot)(uint64_t, ...);
        UserReboot reboot = (UserReboot)dlsym(RTLD_DEFAULT, "reboot3");
        return reboot && reboot(0x2000000000000000ULL) == 0 ? MTSystemOpenSucceeded : MTSystemOpenFailed;
    }
    id service = MTSystemShared(@"FBSSystemService", @"sharedService");
    if ([action isEqual:@"respring"]) {
        id relaunch = nil;
        if (!MTSystemInvoke(NSClassFromString(@"SBSRelaunchAction"), @"actionWithReason:options:targetURL:",
            @[@"RestartRenderServer", @4, NSNull.null], &relaunch) || !relaunch) return MTSystemOpenUnavailable;
        return MTSystemCall(service, @"sendActions:withResult:", @[[NSSet setWithObject:relaunch], NSNull.null]);
    }
    return MTSystemCall(service, [action isEqual:@"shutdown"] ? @"shutdown" : @"reboot", @[]);
}

// Fixed safe controls use their own whitelist in the broker. They do not add
// definitions to the custom-action directory or expose destructive actions.
NSDictionary *MTReadPanelSystemControlState(void) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return nil;
    MTLoadSystemActionFrameworks();
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    id btManager = MTSystemShared(@"BluetoothManager", @"sharedInstance");
    NSNumber *powered = MTSystemPanelValue(btManager, @"powered");
    if (powered && [btManager respondsToSelector:NSSelectorFromString(@"setPowered:")]) state[@"bluetooth"] = @([powered boolValue]);
    id wifi = MTSystemShared(@"SBWiFiManager", @"sharedInstance");
    NSNumber *enabled = MTSystemPanelValue(wifi, @"wiFiEnabled");
    if (enabled && [wifi respondsToSelector:NSSelectorFromString(@"setWiFiEnabled:")]) state[@"wifi"] = @([enabled boolValue]);
    // Read-only mirror of the toggle route in MTSystemToggleDND: the DND daemon
    // only answers entitlement-checked Control Center client identifiers.
    id dndService = nil, dndState = nil;
    NSError *dndError = nil;
    if (MTSystemInvoke(NSClassFromString(@"DNDStateService"), @"serviceForClientIdentifier:",
        @[@"com.apple.donotdisturb.control-center.module"], &dndService) && dndService &&
        MTSystemInvokeReportingError(dndService, @"queryCurrentStateWithError:", @[NSNull.null], &dndState, &dndError) && dndState && !dndError) {
        id activeIdentifier = nil;
        if (MTSystemInvoke(dndState, @"activeModeIdentifier", @[], &activeIdentifier))
            state[@"do-not-disturb"] = @([activeIdentifier isEqual:@"com.apple.donotdisturb.mode.default"]);
        else {
            id isActive = nil;
            if (MTSystemInvoke(dndState, @"isActive", @[], &isActive) && [isActive isKindOfClass:NSNumber.class])
                state[@"do-not-disturb"] = @([isActive boolValue]);
        }
    }
    id lock = MTSystemShared(@"SBOrientationLockManager", @"sharedInstance");
    NSNumber *locked = MTSystemPanelValue(lock, @"isUserLocked");
    if (locked && [lock respondsToSelector:NSSelectorFromString(@"unlock")] &&
        ([lock respondsToSelector:NSSelectorFromString(@"lock")] || [lock respondsToSelector:NSSelectorFromString(@"lock:")])) state[@"orientation-lock"] = @([locked boolValue]);
    id ringer = MTSystemRingerControl();
    NSString *getter = MTSystemAvailableGetter(ringer, @[@"isRingerMuted", @"_accessibilityIsRingerMuted"]);
    NSNumber *muted = MTSystemPanelValue(ringer, getter);
    if (muted && ([ringer respondsToSelector:NSSelectorFromString(@"setRingerMuted:")] ||
        [ringer respondsToSelector:NSSelectorFromString(@"setRingerMuted:withFeedback:reason:clientType:")])) state[@"silent"] = @([muted boolValue]);
    id volume = MTSystemPanelVolumeTarget();
    getter = MTSystemAvailableGetter(volume, @[@"_getMediaVolumeForIAP", @"getMediaVolume", @"volume"]);
    NSNumber *mediaLevel = MTSystemPanelValue(volume, getter);
    if (mediaLevel && ([volume respondsToSelector:NSSelectorFromString(@"_setMediaVolumeForIAP:")] ||
        [volume respondsToSelector:NSSelectorFromString(@"setMediaVolume:")] || [volume respondsToSelector:NSSelectorFromString(@"setVolume:")])) state[@"volume"] = mediaLevel;
    state[@"brightness"] = @(UIScreen.mainScreen.brightness);
    return state;
}
MTSystemOpenResult MTPerformPanelSystemControl(NSString *action, NSNumber *value) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return MTSystemOpenUnavailable;
    MTLoadSystemActionFrameworks();
    if ([action isEqual:@"state"]) return MTSystemOpenSucceeded;
    if ([action isEqual:@"brightness"] || [action isEqual:@"volume"]) {
        if (![value isKindOfClass:NSNumber.class] || !isfinite(value.doubleValue) || value.doubleValue < 0 || value.doubleValue > 1) return MTSystemOpenInvalid;
        if ([action isEqual:@"brightness"]) { UIScreen.mainScreen.brightness = value.doubleValue; return MTSystemOpenSucceeded; }
        return MTSystemCallFirstAvailable(MTSystemPanelVolumeTarget(), @[@[@"_setMediaVolumeForIAP:", @[value]],
            @[@"setMediaVolume:", @[value]], @[@"setVolume:", @[value]]]);
    }
    if ([action isEqual:@"silent"]) {
        id ringer = MTSystemRingerControl();
        NSNumber *muted = MTSystemPanelValue(ringer, MTSystemAvailableGetter(ringer, @[@"isRingerMuted", @"_accessibilityIsRingerMuted"]));
        if (!muted) return MTSystemOpenUnavailable;
        NSNumber *next = @(!muted.boolValue);
        return MTSystemCallFirstAvailable(ringer, @[@[@"setRingerMuted:", @[next]],
            @[@"setRingerMuted:withFeedback:reason:clientType:", @[next, @NO, @"TypeXPanel", @0]]]);
    }
    if ([@[@"do-not-disturb", @"wifi", @"bluetooth", @"orientation-lock"] containsObject:action]) return MTPerformSystemAction(action);
    return MTSystemOpenInvalid;
}
