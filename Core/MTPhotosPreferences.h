#import <Foundation/Foundation.h>
#import "MTModuleGate.h"

// Photo-album enhancement preferences, independent of the retired module
// gates. Keeping them in the existing authority domain also includes them in
// configuration backups. Same shape as MTChargingPreferences.h: the settings
// host is the only writer; runtime sides only read + listen for config-changed.
static inline BOOL MTPhotosMaxZoomEnabled(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("photosMaxZoomEnabled"),
        (__bridge CFStringRef)MTConfigDomain);
    id object = CFBridgingRelease(value);
    return [object isKindOfClass:NSNumber.class] && [object boolValue];
}

static inline void MTSetPhotosMaxZoomEnabled(BOOL enabled) {
    CFPreferencesSetAppValue(CFSTR("photosMaxZoomEnabled"), (__bridge CFBooleanRef)@(enabled),
        (__bridge CFStringRef)MTConfigDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)MTConfigDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)MTConfigChangedNotification, NULL, NULL, YES);
}

static inline BOOL MTPhotosSkipDeleteConfirmEnabled(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("photosSkipDeleteConfirmEnabled"),
        (__bridge CFStringRef)MTConfigDomain);
    id object = CFBridgingRelease(value);
    return [object isKindOfClass:NSNumber.class] && [object boolValue];
}

static inline void MTSetPhotosSkipDeleteConfirmEnabled(BOOL enabled) {
    CFPreferencesSetAppValue(CFSTR("photosSkipDeleteConfirmEnabled"), (__bridge CFBooleanRef)@(enabled),
        (__bridge CFStringRef)MTConfigDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)MTConfigDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)MTConfigChangedNotification, NULL, NULL, YES);
}
