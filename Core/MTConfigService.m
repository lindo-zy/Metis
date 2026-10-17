#import "MTConfigService.h"
#import "MTModuleGate.h"
#import "MTLog.h"
#import <CoreFoundation/CoreFoundation.h>

static void MTPostConfigChanged(void) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)MTConfigChangedNotification,
        NULL,
        NULL,
        TRUE);
}

@implementation MTConfigService

+ (void)setGlobalEnabled:(BOOL)enabled {
    CFPreferencesSetValue(
        (__bridge CFStringRef)@"enabled",
        (enabled ? kCFBooleanTrue : kCFBooleanFalse),
        (__bridge CFStringRef)MTConfigDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    MTLogInfo(MTLogModulePrefs, @"state=global-set enabled=%d", enabled);
}

+ (void)setModule:(NSString *)moduleID enabled:(BOOL)enabled {
    NSString *key = [NSString stringWithFormat:@"%@Enabled", moduleID];
    CFPreferencesSetValue(
        (__bridge CFStringRef)key,
        (enabled ? kCFBooleanTrue : kCFBooleanFalse),
        (__bridge CFStringRef)MTConfigDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    MTLogInfo(MTLogModulePrefs, @"state=module-set module=%@ enabled=%d", moduleID, enabled);
}

+ (void)flush {
    CFPreferencesSynchronize(
        (__bridge CFStringRef)MTConfigDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    MTPostConfigChanged();
}

@end
