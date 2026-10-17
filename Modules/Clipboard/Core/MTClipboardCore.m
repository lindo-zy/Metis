//
//  MTClipboardCore.m
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import "MTClipboardCore.h"
#import "MTClipboardCoreRuntime.h"
#import "MTNotificationKeys.h"
#import "MTShortcutSnapshotProvider.h"
#import "MTSpringBoardHooks.h"

#import <CoreFoundation/CoreFoundation.h>

typedef NS_ENUM(NSUInteger, MTClipboardCoreProcessKind) {
    MTClipboardCoreProcessKindUnsupported = 0,
    MTClipboardCoreProcessKindSpringBoard,
    MTClipboardCoreProcessKindDruidOrPasted,
};

@interface MTClipboardCoreProcessContext : NSObject

@property(nonatomic, assign, readonly) MTClipboardCoreProcessKind kind;

+ (instancetype)currentContext;

- (instancetype)initWithKind:(MTClipboardCoreProcessKind)kind;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MTClipboardCoreBootstrap : NSObject

+ (void)installForSpringBoard;
+ (void)installForDruidOrPasted;

@end

@implementation MTClipboardCoreProcessContext

#pragma mark - Lifecycle

+ (instancetype)currentContext {
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
        return [[self alloc] initWithKind:MTClipboardCoreProcessKindSpringBoard];
    }

    NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
    NSString *processName = [[NSProcessInfo processInfo] processName];
    NSString *executablePath = [args firstObject];
    BOOL isSystemExecutable =
        [executablePath hasPrefix:@"/System/Library/"] || [executablePath hasPrefix:@"/usr/libexec/"];
    BOOL isPasteTipProcess = [processName isEqualToString:@"druid"] || [processName isEqualToString:@"pasted"];
    if (isSystemExecutable && isPasteTipProcess) {
        return [[self alloc] initWithKind:MTClipboardCoreProcessKindDruidOrPasted];
    }

    return [[self alloc] initWithKind:MTClipboardCoreProcessKindUnsupported];
}

- (instancetype)initWithKind:(MTClipboardCoreProcessKind)kind {
    self = [super init];
    if (self) {
        _kind = kind;
    }
    return self;
}

@end

#pragma mark - Darwin Callbacks

static void mtCorePasteboardChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] capturePasteboardChange];
}

static void mtCoreShowCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] show];
}

static void mtCoreHideCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] hideForExternalRequest];
}

static void mtCoreToggleCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                     const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    MTClipboardCoreRuntime *runtime = [MTClipboardCoreRuntime sharedRuntime];
    if (runtime.panelVisible) {
        [runtime hideForExternalRequest];
    } else {
        [runtime show];
    }
}

static void mtCoreReloadCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                     const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] reloadHistory];
}

static void mtCoreCheckpointHistoryCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] checkpointHistoryDatabase];
}

static void mtCorePrepareMaintenanceCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                 const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] prepareForPackageMaintenance];
}

static void mtCoreResetThumbnailMemoryCacheCallback(CFNotificationCenterRef center, void *observer,
                                                        CFStringRef name, const void *object,
                                                        CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] resetThumbnailMemoryCache];
}

static void mtCoreClearFavoritesCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                             const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] clearFavorites];
}

static void mtCoreClearHistoryCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                           const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] clearHistory];
}

static void mtCorePreferencesReloadCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    // Darwin notifications may be delivered off the main thread. Preference reloads
    // update UIKit-owned windows and controllers, so serialize the work on main.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[MTClipboardCoreRuntime sharedRuntime] loadPreferences];
    });
}

static void mtCoreHeightPreferenceReloadCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                     const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] loadHeightPreference];
}

static void mtCoreHelperPasteCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                          const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] playPasteFeedback];
}

static void mtCorePasteFeedbackCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                            const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] playPasteFeedback];
}

static void mtCorePasteWillStartCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                             const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] markPasteWillStart];
}

static void mtCorePasteTipPreferencesReloadCallback(CFNotificationCenterRef center, void *observer,
                                                        CFStringRef name, const void *object,
                                                        CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[MTClipboardCoreRuntime sharedRuntime] refreshPasteTipPreferences];
}

@implementation MTClipboardCoreBootstrap

#pragma mark - Observers

+ (void)addDarwinObserverForName:(CFStringRef)name callback:(CFNotificationCallback)callback {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL, callback, name, NULL,
        (CFNotificationSuspensionBehavior)CFNotificationSuspensionBehaviorDeliverImmediately);
}

#pragma mark - Installation

+ (void)installForSpringBoard {
    MTClipboardCoreRuntime *runtime = [MTClipboardCoreRuntime sharedRuntime];
    // dyld 加载期只做轻量读取（门控 + 决定 hook 形态的两项参数）；
    // 完整偏好应用（40 项 registerDefaults/外观等）延后到主队列与
    // SB didFinishLaunching（MTSpringBoardHooks 侧）执行，遵守
    // 「constructor 只做门控」的包内约定（03-architecture §3）。
    [runtime loadHookShapePreferences];
    // Registered regardless of the enabled state: the preferences shortcut
    // picker needs the catalogue even while the tweak is switched off.
    [MTShortcutSnapshotProvider installObserver];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyCoreCheckpointHistory
                          callback:mtCoreCheckpointHistoryCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyCorePrepareMaintenance
                          callback:mtCorePrepareMaintenanceCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyCoreResetThumbnailMemoryCache
                          callback:mtCoreResetThumbnailMemoryCacheCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyCoreClearFavorites
                          callback:mtCoreClearFavoritesCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyCoreClearHistory
                          callback:mtCoreClearHistoryCallback];
    if (![runtime isEnabled]) {
        return;
    }

    [MTPasteTipHookInstaller installHooks];
    [MTSpringBoardHookInstaller installHooks];
    [runtime startLockStateObserver];

    [self addDarwinObserverForName:CFSTR("com.apple.pasteboard.notify.changed")
                          callback:mtCorePasteboardChangedCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyCoreShow
                          callback:mtCoreShowCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTLegacyNotificationKeyCoreShow
                          callback:mtCoreShowCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyCoreHide
                          callback:mtCoreHideCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTLegacyNotificationKeyCoreHide
                          callback:mtCoreHideCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyCoreToggle
                          callback:mtCoreToggleCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyCoreReload
                          callback:mtCoreReloadCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyPreferencesReload
                          callback:mtCorePreferencesReloadCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyPreferencesHeightReload
                          callback:mtCoreHeightPreferenceReloadCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyHelperPaste
                          callback:mtCoreHelperPasteCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyPasteFeedback
                          callback:mtCorePasteFeedbackCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyPasteWillStart
                          callback:mtCorePasteWillStartCallback];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[MTClipboardCoreRuntime sharedRuntime] loadPreferences];
    });
}

+ (void)installForDruidOrPasted {
    BOOL shouldInstallPasteTipHooks = [[MTClipboardCoreRuntime sharedRuntime] refreshPasteTipPreferences];
    if (!shouldInstallPasteTipHooks) {
        return;
    }

    [MTPasteTipHookInstaller installHooks];
    [self addDarwinObserverForName:(__bridge CFStringRef)kMTNotificationKeyPreferencesReload
                          callback:mtCorePasteTipPreferencesReloadCallback];
}

@end

#pragma mark - Entrypoint

__attribute((constructor)) static void initialize() {
    switch ([MTClipboardCoreProcessContext currentContext].kind) {
    case MTClipboardCoreProcessKindSpringBoard:
        [MTClipboardCoreBootstrap installForSpringBoard];
        return;
    case MTClipboardCoreProcessKindDruidOrPasted:
        [MTClipboardCoreBootstrap installForDruidOrPasted];
        return;
    case MTClipboardCoreProcessKindUnsupported:
        return;
    }
}
