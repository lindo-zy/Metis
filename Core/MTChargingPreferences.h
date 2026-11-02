#import <Foundation/Foundation.h>
#import "MTModuleGate.h"

// A feature preference, independent of the retired module gates. Keeping it in
// the existing authority domain also includes it in configuration backups.
static inline BOOL MTChargingDetailsEnabled(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("chargingDetailsEnabled"),
        (__bridge CFStringRef)MTConfigDomain);
    id object = CFBridgingRelease(value);
    return [object isKindOfClass:NSNumber.class] && [object boolValue];
}

static inline void MTSetChargingDetailsEnabled(BOOL enabled) {
    CFPreferencesSetAppValue(CFSTR("chargingDetailsEnabled"), (__bridge CFBooleanRef)@(enabled),
        (__bridge CFStringRef)MTConfigDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)MTConfigDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)MTConfigChangedNotification, NULL, NULL, YES);
}
