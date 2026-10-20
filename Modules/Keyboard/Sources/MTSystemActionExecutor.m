#import "MTSystemActionExecutor.h"
#import "MTSystemActionCatalog.h"
#import "MTSystemActionCompatibility.h"
#import "MTSystemRecordingSession.h"
#import "common.h"
#import "MTCaptureIntegration.h"
#import "MTQuickPanelHost.h"
#import "MTAIPanel.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <notify.h>
#include <signal.h>
#include <unistd.h>

static __weak UIAlertController *MTSystemActionConfirmation;
static UIWindow *MTSystemConfirmHostWindow;

// 确认框存活上限。既是自动收起的兜底，也是「继续」的有效性判定，
// 两处必须同源，否则会出现框还在、点确认却被判超时的错位。
static const NSTimeInterval MTSystemActionConfirmTimeout = 30;

// 自建宿主必须随确认框一起销毁，否则常驻窗口会变成下一次的遮挡者
// （与本次故障同形态）。按实例销毁：dismiss 回调可能晚于下一代宿主的
// 创建，按全局指针拆会误杀新窗口。
static void MTReleaseSystemConfirmHostWindow(UIWindow *window) {
    if (!window) return;
    if (MTSystemConfirmHostWindow == window) MTSystemConfirmHostWindow = nil;
    window.hidden = YES;
    window.rootViewController = nil;
}

static void MTReleaseSystemConfirmHost(void) {
    MTReleaseSystemConfirmHostWindow(MTSystemConfirmHostWindow);
}

// scene 挑选与 MTGlobalPanel 完全同规则（SB 内久经验证可交互的承载）：
// 主屏、排除键盘/系统孔径、接受 Active/Inactive（覆盖前台 App 时 SB scene
// 为 Inactive），优先 com.apple.springboard 与 SBWindowScene。
static UIWindowScene *MTSystemConfirmWindowScene(void) {
    UIWindowScene *best = nil;
    NSInteger bestScore = 0;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if (![candidate isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)candidate;
        NSString *identity = windowScene.session.persistentIdentifier.lowercaseString ?: @"";
        NSString *role = windowScene.session.role.lowercaseString ?: @"";
        if (windowScene.screen != UIScreen.mainScreen || [identity containsString:@"keyboard"] ||
            [role containsString:@"keyboard"] || [identity containsString:@"systemaperture"] ||
            [role containsString:@"systemaperture"]) continue;
        if (windowScene.activationState != UISceneActivationStateForegroundActive &&
            windowScene.activationState != UISceneActivationStateForegroundInactive) continue;
        NSInteger score = [identity isEqualToString:@"com.apple.springboard"] ? 100 :
            ([NSStringFromClass(windowScene.class) isEqualToString:@"SBWindowScene"] ? 50 : 0);
        if (windowScene.activationState == UISceneActivationStateForegroundActive) score += 10;
        if (score > bestScore) { bestScore = score; best = windowScene; }
    }
    return best;
}

// 自建专用窗口是外来窗口全不可用时的唯一可靠宿主：配方与 MTGlobalPanel
// 相同——scene 挂靠、不抢 key（canBecomeKey 保持默认、hidden=NO 即可挂屏）；
// 找不到 scene 的退化分支才 plain-init + makeKeyAndVisible（MTAIPanel 同款）。
static UIViewController *MTMakeSystemConfirmHost(void) {
    if (MTSystemConfirmHostWindow) MTReleaseSystemConfirmHostWindow(MTSystemConfirmHostWindow);
    UIWindowScene *scene = MTSystemConfirmWindowScene();
    UIWindow *window = nil;
    if (scene) {
        window = [[UIWindow alloc] initWithWindowScene:scene];
        window.frame = scene.coordinateSpace.bounds;
    } else {
        window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }
    window.backgroundColor = UIColor.clearColor;
    // 比 Metis 各面板（alert+1）再高一层：确认框必须盖住可能仍开着的面板，
    // 否则弹窗落在面板后面同样点不到；代价是超出截图捕获范围，可接受。
    window.windowLevel = UIWindowLevelAlert + 2;
    UIViewController *host = [UIViewController new];
    host.view.backgroundColor = UIColor.clearColor;
    window.rootViewController = host;
    MTSystemConfirmHostWindow = window;
    if (scene) window.hidden = NO;
    else [window makeKeyAndVisible];
    return host;
}

// 宿主挑选：调用方指定 > 自建专用窗口。外来窗口一律不挂——SB 的状态栏
// 窗口（剪贴板面板就装在里面）bounds 全屏、命中区域却只有窄条，尺寸过滤
// 挡不住它，弹窗挂上去能显示、收不到触摸，正是「点不动、只能等超时」的
// 成因。判定改用窗口 rootVC 的类名 MT 前缀：Metis 自有面板的根控制器
// 都以 MT 开头，SB 自己的窗口（含状态栏、锁屏等）不会命中。
static BOOL MTSystemConfirmWindowIsHostable(UIWindow *window) {
    if (!window || window.hidden || window.alpha < 0.01) return NO;
    UIViewController *root = window.rootViewController;
    if (!root || root.presentedViewController) return NO;
    if (root.isViewLoaded && root.view.isHidden) return NO;
    if (![NSStringFromClass(root.class) hasPrefix:@"MT"]) return NO;
    UIWindowScene *scene = window.windowScene;
    // 全屏是承载模态的最低要求：小窗口承载的弹窗会被裁剪、按钮收不到触摸。
    return scene && CGSizeEqualToSize(window.bounds.size, scene.coordinateSpace.bounds.size);
}

static UIViewController *MTSystemConfirmPresenter(UIViewController *preferred, NSString **hostSource) {
    if (preferred && [preferred isKindOfClass:UIViewController.class] && !preferred.presentedViewController &&
        MTSystemConfirmWindowIsHostable(preferred.view.window)) {
        if (hostSource) *hostSource = @"caller";
        return preferred;
    }
    if (hostSource) *hostSource = @"dedicated";
    return MTMakeSystemConfirmHost();
}

void MTCancelSystemActionConfirmation(void) {
    if (!NSThread.isMainThread) return;
    UIAlertController *alert = MTSystemActionConfirmation;
    MTSystemActionConfirmation = nil;
    if (!alert) {
        MTReleaseSystemConfirmHost();
        return;
    }
    // 捕获当前那一代宿主：dismiss 回调执行时全局指针可能已经指向新窗口。
    UIWindow *host = MTSystemConfirmHostWindow;
    // 在 dismiss 回调里拆宿主：直接释放窗口会让正在退场的模态层凭空消失。
    [alert dismissViewControllerAnimated:NO completion:^{ MTReleaseSystemConfirmHostWindow(host); }];
}

BOOL MTConfirmSystemExitActionFrom(NSString *action, NSProgress *operation, UIViewController *preferred) {
    if (!MTSystemExitActionAvailable(action) || ![MTSystemActionDefinition(action)[@"destructive"] boolValue]) return NO;
    NSString *hostSource = nil;
    UIViewController *presenter = MTSystemConfirmPresenter(preferred, &hostSource);
    if (!presenter) return NO;
    // 自建宿主刚创建时 view 可能还没挂进窗口，兜底取全局那一代。
    UIWindow *window = presenter.view.window ?: MTSystemConfirmHostWindow;
    if (!window || window.hidden || presenter.presentedViewController) return NO;
    UIWindowScene *hostScene = window.windowScene;
    NSLog(@"[MetisKeyboard][SystemConfirm] host=%@ level=%.0f fullscreen=%d source=%@ scene=%@",
        NSStringFromClass(window.class), (double)window.windowLevel,
        hostScene ? CGSizeEqualToSize(window.bounds.size, hostScene.coordinateSpace.bounds.size) : NO, hostSource,
        hostScene.session.persistentIdentifier);
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSString *title = [bundle localizedStringForKey:MTSystemActionDefinition(action)[@"title"] value:action table:nil];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:[bundle localizedStringForKey:@"SYSTEM_ACTION_CONFIRM" value:@"Continue?" table:nil]
        preferredStyle:UIAlertControllerStyleAlert];
    NSTimeInterval deadline = NSDate.date.timeIntervalSince1970 + MTSystemActionConfirmTimeout;
    __weak UIWindow *originalWindow = window;
    __weak UIViewController *originalPresenter = presenter;
    __weak UIAlertController *originalAlert = alert;
    // 本次确认框自己那一代宿主（借用别人窗口时为 nil），清理只针对它。
    __weak UIWindow *ownedHost = MTSystemConfirmHostWindow;
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"CANCEL" value:@"Cancel" table:nil]
        style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *choice) {
            if (MTSystemActionConfirmation == originalAlert) {
                MTSystemActionConfirmation = nil;
                dispatch_async(dispatch_get_main_queue(), ^{ MTReleaseSystemConfirmHostWindow(ownedHost); });
            }
            [operation cancel];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"ANSWER_YES" value:@"Continue" table:nil]
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *choice) {
            BOOL current = MTSystemActionConfirmation == originalAlert;
            if (current) MTSystemActionConfirmation = nil;
            UIWindow *host = originalWindow;
            UIViewController *controller = originalPresenter;
            // 宿主由执行器指定，不能再拿全局 keyWindow 比对：它会随场景切换漂移。
            if (!current || operation.cancelled || !host || host.hidden || !controller ||
                controller.view.window != host || NSDate.date.timeIntervalSince1970 > deadline) return;
            MTSystemOpenResult result = MTPerformSystemAction(action);
            NSLog(@"[MetisKeyboard][SystemAction] confirmed id=%@ result=%llu", action, (unsigned long long)result);
            if (result != MTSystemOpenSucceeded) {
                UIAlertController *error = [UIAlertController alertControllerWithTitle:title
                    message:[bundle localizedStringForKey:@"SYSTEM_ACTION_UNAVAILABLE" value:@"Unavailable" table:nil]
                    preferredStyle:UIAlertControllerStyleAlert];
                [error addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"ANSWER_OK" value:@"OK" table:nil]
                    style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *acknowledged) {
                        dispatch_async(dispatch_get_main_queue(), ^{ MTReleaseSystemConfirmHostWindow(ownedHost); });
                    }]];
                UIAlertController *prompt = originalAlert;
                [prompt dismissViewControllerAnimated:YES completion:^{
                    UIWindow *currentWindow = originalWindow;
                    UIViewController *currentPresenter = originalPresenter;
                    if (operation.cancelled || !currentWindow || currentWindow.hidden || !currentPresenter ||
                        currentPresenter.view.window != currentWindow || currentPresenter.presentedViewController ||
                        NSDate.date.timeIntervalSince1970 > deadline) return;
                    [currentPresenter presentViewController:error animated:YES completion:nil];
                }];
            } else {
                // 动作已受理。若它没能让 SpringBoard 退出（重复触发或被底层拒绝），
                // 自建宿主会留在最上层挡住触摸——正是本次故障的形态，这里兜底回收。
                // 进程真正退出的分支不会执行到这段。
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    MTReleaseSystemConfirmHostWindow(ownedHost);
                });
            }
        }]];
    MTSystemActionConfirmation = alert;
    [presenter presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MTSystemActionConfirmTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (MTSystemActionConfirmation != originalAlert || !originalAlert) return;
        [operation cancel];
        MTCancelSystemActionConfirmation();
    });
    return YES;
}

BOOL MTConfirmSystemExitAction(NSString *action, NSProgress *operation) {
    return MTConfirmSystemExitActionFrom(action, operation, nil);
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
    // 走现有唤起通知：剪切板核心负责展示，输入宿主同时记录焦点以供粘贴恢复。
    if ([action isEqual:@"clipboard"]) {
        if (!NSClassFromString(@"MTClipboardCoreRuntime")) return MTSystemOpenUnavailable;
        return notify_post("com.lindo.metis.clipboard.core.show") == NOTIFY_STATUS_OK
            ? MTSystemOpenSucceeded : MTSystemOpenFailed;
    }
    if ([action isEqual:@"ai-chat"])
        return [MTAIPanel presentForSystemAction] ? MTSystemOpenSucceeded : MTSystemOpenUnavailable;
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
    // 保留已保存的 reachability 标识，统一转到 Metis 快速面板。
    if ([action isEqual:@"reachability"])
        return MTPresentQuickPanel() ? MTSystemOpenSucceeded : MTSystemOpenUnavailable;
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
