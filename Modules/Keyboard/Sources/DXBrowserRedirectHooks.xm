#import "common.h"
#import <objc/message.h>
#import <objc/runtime.h>
#include <atomic>

// 默认浏览器重定向：把经 SpringBoard 打开 Safari / Firefox / Chrome / Brave
// 的请求改派给 Reynard。开关默认关闭，写入 com.lindo.typex 的
// browserredirectBOOL，受总开关 enabledBOOL 约束。行为移植自 ReynardDefault
// （FBSystemServiceOpenApplicationRequest 的 setBundleIdentifier: 换目标），
// 偏好读取与安装时机沿用 DXSMSCodeHooks 的模式。
#define kDXBrowserRedirectEnabledKey @"browserredirectBOOL"

static NSString *const DXBrowserRedirectTarget = @"com.minh-ton.Reynard";
static NSString *const DXBrowserRedirectScheme = @"reynard";
static NSArray<NSString *> *const DXBrowserRedirectSources = @[
    @"com.apple.mobilesafari",
    @"org.mozilla.ios.Firefox",
    @"com.google.chrome.ios",
    @"com.brave.ios.browser",
];

// The hook can run off the main queue, while reloads only happen on main.
static std::atomic<BOOL> DXBrowserRedirectEnabled(NO);

static BOOL DXBrowserRedirectPreferencesEnabled(NSDictionary *preferences) {
    if (![preferences isKindOfClass:NSDictionary.class]) return NO;
    id feature = preferences[kDXBrowserRedirectEnabledKey];
    id master = preferences[kEnabledkey];
    return [feature isKindOfClass:NSNumber.class] && [feature boolValue] &&
        (!master || ([master isKindOfClass:NSNumber.class] && [master boolValue]));
}

static void DXBrowserRedirectReload(void) {
    NSDictionary *preferences = [[DXPrefsManager sharedInstance] readPrefs];
    DXBrowserRedirectEnabled.store(DXBrowserRedirectPreferencesEnabled(preferences));
}

// Reynard does not register http/https handlers in its Info.plist, so iOS drops
// the URL once the bundle identifier is swapped. Hand it over as
// reynard://open?url=<encoded>, the form Reynard's SceneDelegate decodes back
// to the original URL. Other schemes keep the URL untouched.
static NSURL *DXBrowserRedirectWrapURL(NSURL *original) {
    if (![original isKindOfClass:NSURL.class]) return nil;
    NSString *scheme = original.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return nil;
    NSString *encoded = [original.absoluteString
        stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    if (!encoded.length) return nil;
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@://open?url=%@",
        DXBrowserRedirectScheme, encoded]];
}

// URL accessors checked at runtime: a missing or changed private accessor on
// the request skips the URL hand-over instead of crashing SpringBoard.
static NSURL *DXBrowserRedirectRequestURL(id request) {
    SEL selector = NSSelectorFromString(@"URL");
    if (![request respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [request methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(request, selector);
}

static void DXBrowserRedirectSetRequestURL(id request, NSURL *url) {
    SEL selector = NSSelectorFromString(@"setURL:");
    if (![request respondsToSelector:selector]) return;
    NSMethodSignature *signature = [request methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3 || signature.methodReturnType[0] != 'v') return;
    ((void (*)(id, SEL, id))objc_msgSend)(request, selector, url);
}

%group DXBrowserRedirect
%hook FBSystemServiceOpenApplicationRequest
- (void)setBundleIdentifier:(NSString *)bundleIdentifier {
    if (DXBrowserRedirectEnabled.load() &&
        [bundleIdentifier isKindOfClass:NSString.class] &&
        [DXBrowserRedirectSources containsObject:bundleIdentifier]) {
        // The URL is never logged; it can carry tokens or other private data.
        NSURL *wrapped = DXBrowserRedirectWrapURL(DXBrowserRedirectRequestURL(self));
        if (wrapped) DXBrowserRedirectSetRequestURL(self, wrapped);
        NSLog(@"[TypeX][BrowserRedirect] %@ -> %@ url=%@",
            bundleIdentifier, DXBrowserRedirectTarget, wrapped ? @"wrapped" : @"kept");
        %orig(DXBrowserRedirectTarget);
    } else {
        %orig;
    }
}
%end
%end

static BOOL DXBrowserRedirectMethodMatches(Class cls) {
    // setBundleIdentifier: is v@:@; a changed signature disables the feature.
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(@"setBundleIdentifier:"));
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char type[16] = {};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'v') return NO;
    method_getArgumentType(method, 2, type, sizeof(type));
    return type[0] == '@';
}

static void DXBrowserRedirectTryInstallHooks(void) {
    Class cls = NSClassFromString(@"FBSystemServiceOpenApplicationRequest");
    if (!cls || !DXBrowserRedirectMethodMatches(cls)) return;
    static BOOL installed = NO;
    if (installed) return;
    installed = YES;
    %init(DXBrowserRedirect, FBSystemServiceOpenApplicationRequest = cls);
    NSLog(@"[TypeX][BrowserRedirect] hooks installed");
}

static void DXBrowserRedirectPreferencesChanged(CFNotificationCenterRef center, void *observer,
                                               CFStringRef name, const void *object, CFDictionaryRef info) {
    // The hook acts on the current atomic value, so a plain reload is enough;
    // there is no queued capture work that could outlive a disable.
    dispatch_async(dispatch_get_main_queue(), ^{ DXBrowserRedirectReload(); });
}

%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            DXBrowserRedirectReload();
            DXBrowserRedirectTryInstallHooks();
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                DXBrowserRedirectPreferencesChanged, (CFStringRef)kPrefsChangedIdentifier, NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            // Process-lifetime observers, installed exactly once in SpringBoard.
            [NSNotificationCenter.defaultCenter addObserverForName:NSBundleDidLoadNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { DXBrowserRedirectTryInstallHooks(); }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { DXBrowserRedirectTryInstallHooks(); }];
        });
    }
}
