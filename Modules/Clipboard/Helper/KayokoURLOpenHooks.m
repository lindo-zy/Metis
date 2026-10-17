//
//  KayokoURLOpenHooks.m
//  Kayoko
//

#define CHUseSubstrate

#import "KayokoHelperHookInstaller.h"
#import "KayokoHelperRuntime.h"

#import <CaptainHook/CaptainHook.h>
#import <Foundation/Foundation.h>
#import <HBLog.h>
#import <UIKit/UIKit.h>

typedef void (^KayokoURLOpenCompletionHandler)(BOOL success);

static NSString *const kKayokoURLOpenScheme = @"kayokox";

CHDeclareClass(UIApplication);

static BOOL KayokoURLOpenIsKayokoURL(NSURL *url) {
    if (![url isKindOfClass:[NSURL class]] || !url.scheme) {
        return NO;
    }
    return [url.scheme.lowercaseString isEqualToString:kKayokoURLOpenScheme];
}

static void KayokoURLOpenHandleURL(NSURL *url) {
    NSString *action = url.host.lowercaseString;
    KayokoHelperRuntime *runtime = [KayokoHelperRuntime sharedRuntime];
    HBLogDebug(@"Kayoko: url scheme request action=%@", action);

    if ([action isEqualToString:@"close"] || [action isEqualToString:@"hide"]) {
        [runtime hideKayoko];
        return;
    }
    if ([action isEqualToString:@"toggle"]) {
        [runtime toggleKayoko];
        return;
    }
    [runtime showKayokoAfterCapturingCurrentFocus];
}

@implementation KayokoHelperHookInstaller (URLOpen)

CHOptimizedMethod3(self, void, UIApplication, openURL, NSURL *, url, options, NSDictionary *, options,
                   completionHandler, KayokoURLOpenCompletionHandler, completionHandler) {
    if (KayokoURLOpenIsKayokoURL(url)) {
        KayokoURLOpenHandleURL(url);
        if (completionHandler) {
            completionHandler(YES);
        }
        return;
    }
    CHSuper3(UIApplication, openURL, url, options, options, completionHandler, completionHandler);
}

CHOptimizedMethod1(self, BOOL, UIApplication, openURL, NSURL *, url) {
    if (KayokoURLOpenIsKayokoURL(url)) {
        KayokoURLOpenHandleURL(url);
        return YES;
    }
    return CHSuper1(UIApplication, openURL, url);
}

CHOptimizedMethod1(self, BOOL, UIApplication, canOpenURL, NSURL *, url) {
    if (KayokoURLOpenIsKayokoURL(url)) {
        return YES;
    }
    return CHSuper1(UIApplication, canOpenURL, url);
}

+ (void)installURLOpenHooks {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      CHLoadClass_(&UIApplication$, NSClassFromString(@"UIApplication"));
      CHHook3(UIApplication, openURL, options, completionHandler);
      CHHook1(UIApplication, openURL);
      CHHook1(UIApplication, canOpenURL);
    });
}

@end
