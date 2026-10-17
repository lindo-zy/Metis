//
//  MTURLOpenHooks.m
//  Mt
//

#define CHUseSubstrate

#import "MTClipboardHelperHookInstaller.h"
#import "MTClipboardHelperRuntime.h"

#import <CaptainHook/CaptainHook.h>
#import <Foundation/Foundation.h>
#import <HBLog.h>
#import <UIKit/UIKit.h>

typedef void (^MTURLOpenCompletionHandler)(BOOL success);

static NSString *const kMTURLOpenScheme = @"kayokox";

CHDeclareClass(UIApplication);

static BOOL MTURLOpenIsMtURL(NSURL *url) {
    if (![url isKindOfClass:[NSURL class]] || !url.scheme) {
        return NO;
    }
    return [url.scheme.lowercaseString isEqualToString:kMTURLOpenScheme];
}

static void MTURLOpenHandleURL(NSURL *url) {
    NSString *action = url.host.lowercaseString;
    MTClipboardHelperRuntime *runtime = [MTClipboardHelperRuntime sharedRuntime];
    HBLogDebug(@"Mt: url scheme request action=%@", action);

    if ([action isEqualToString:@"close"] || [action isEqualToString:@"hide"]) {
        [runtime hideMt];
        return;
    }
    if ([action isEqualToString:@"toggle"]) {
        [runtime toggleMt];
        return;
    }
    [runtime showMtAfterCapturingCurrentFocus];
}

@implementation MTClipboardHelperHookInstaller (URLOpen)

CHOptimizedMethod3(self, void, UIApplication, openURL, NSURL *, url, options, NSDictionary *, options,
                   completionHandler, MTURLOpenCompletionHandler, completionHandler) {
    if (MTURLOpenIsMtURL(url)) {
        MTURLOpenHandleURL(url);
        if (completionHandler) {
            completionHandler(YES);
        }
        return;
    }
    CHSuper3(UIApplication, openURL, url, options, options, completionHandler, completionHandler);
}

CHOptimizedMethod1(self, BOOL, UIApplication, openURL, NSURL *, url) {
    if (MTURLOpenIsMtURL(url)) {
        MTURLOpenHandleURL(url);
        return YES;
    }
    return CHSuper1(UIApplication, openURL, url);
}

CHOptimizedMethod1(self, BOOL, UIApplication, canOpenURL, NSURL *, url) {
    if (MTURLOpenIsMtURL(url)) {
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
