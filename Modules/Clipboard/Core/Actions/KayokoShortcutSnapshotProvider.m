//
//  KayokoShortcutSnapshotProvider.m
//  Kayoko
//

#import "KayokoShortcutSnapshotProvider.h"

#import "KayokoNotificationKeys.h"
#import "KayokoShortcutCatalog.h"
#import "KayokoAppInfo.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Not in the SDK.
@interface SBApplication : NSObject
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface SBApplication (KayokoShortcuts)
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *applicationIdentifier;
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, copy) NSString *applicationDisplayName;
@end

static NSString *KayokoReadString(id object, NSString *propertyName) {
    SEL selector = NSSelectorFromString(propertyName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        return [value isKindOfClass:[NSString class]] ? value : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id KayokoReadObject(id object, NSString *propertyName) {
    SEL selector = NSSelectorFromString(propertyName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id KayokoShortcutApplicationController(void) {
    Class controllerClass = NSClassFromString(@"SBApplicationController");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if (!controllerClass || ![controllerClass respondsToSelector:sharedSelector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(controllerClass, sharedSelector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id KayokoShortcutApplication(id controller, NSString *bundleIdentifier) {
    SEL selector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if (!controller || ![controller respondsToSelector:selector] || [bundleIdentifier length] == 0) return nil;
    @try {
        return ((id (*)(id, SEL, id))objc_msgSend)(controller, selector, bundleIdentifier);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSArray *KayokoShortcutArray(id value) {
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static NSArray *KayokoStaticShortcutItems(id application) {
    id info = KayokoReadObject(application, @"info");
    NSArray *items = KayokoShortcutArray(KayokoReadObject(info, @"staticApplicationShortcutItems"));
    if ([items count] == 0) {
        items = KayokoShortcutArray(KayokoReadObject(application, @"staticApplicationShortcutItems"));
    }
    return items;
}

static NSArray *KayokoDynamicShortcutItems(id application) {
    return KayokoShortcutArray(KayokoReadObject(application, @"dynamicApplicationShortcutItems"));
}

// Dynamic items precede static items, matching the order of the system menu.
// A type is the stable app-defined identity; duplicate types are exposed once.
static NSArray<NSDictionary *> *KayokoShortcutDescriptors(id application) {
    NSMutableArray<NSDictionary *> *descriptors = [NSMutableArray array];
    NSMutableSet<NSString *> *seenTypes = [NSMutableSet set];
    for (NSDictionary *sourceGroup in @[ @{@"source" : @"dynamic", @"items" : KayokoDynamicShortcutItems(application)},
                                         @{@"source" : @"static", @"items" : KayokoStaticShortcutItems(application)} ]) {
        for (id item in sourceGroup[@"items"]) {
            NSString *type = KayokoReadString(item, @"type");
            if ([type length] == 0 || [type hasPrefix:@"com.apple.springboard."]) continue;
            if ([seenTypes containsObject:type]) continue;
            [seenTypes addObject:type];

            NSString *title = KayokoReadString(item, @"localizedTitle") ?: KayokoReadString(item, @"title");
            NSString *subtitle = KayokoReadString(item, @"localizedSubtitle") ?: KayokoReadString(item, @"subtitle");
            NSMutableDictionary *descriptor = [NSMutableDictionary
                dictionaryWithDictionary:@{ @"type" : type,
                                            @"title" : [title length] > 0 ? title : type,
                                            @"source" : sourceGroup[@"source"] }];
            if ([subtitle length] > 0) descriptor[@"subtitle"] = subtitle;
            [descriptors addObject:descriptor];
        }
    }
    return descriptors;
}

static id KayokoCurrentShortcutItem(id application, NSString *shortcutType) {
    for (NSArray *items in @[ KayokoDynamicShortcutItems(application), KayokoStaticShortcutItems(application) ]) {
        for (id item in items) {
            if ([KayokoReadString(item, @"type") isEqualToString:shortcutType]) return item;
        }
    }
    return nil;
}

static dispatch_queue_t KayokoShortcutRefreshQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      queue = dispatch_queue_create("com.lindo.kayoko.shortcut.snapshot", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void kayokoShortcutRefreshRequestCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                 const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    // Always rebuild on the process main queue so UIKit-backed SpringBoard
    // state is read serially and never from the posting thread.
    dispatch_async(dispatch_get_main_queue(), ^{
      [KayokoShortcutSnapshotProvider handleRefreshRequest];
    });
}

@implementation KayokoShortcutSnapshotProvider

+ (void)installObserver {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    kayokoShortcutRefreshRequestCallback,
                                    (__bridge CFStringRef)kKayokoShortcutDarwinNotificationRefreshRequest, NULL,
                                    (CFNotificationSuspensionBehavior)CFNotificationSuspensionBehaviorDeliverImmediately);
}

+ (void)handleRefreshRequest {
    static NSString *lastRequestID = nil;
    NSString *requestID = [KayokoShortcutCatalog readRefreshRequestID];
    if ([requestID length] == 0) return;
    @synchronized([self class]) {
        if ([lastRequestID isEqualToString:requestID]) return;
        lastRequestID = [requestID copy];
    }

    id controller = KayokoShortcutApplicationController();
    if (!controller) {
        NSLog(@"[Kayoko] shortcuts: SBApplicationController unavailable");
        return;
    }

    NSDictionary *request = [KayokoShortcutCatalog readRefreshRequest];
    NSArray *rawBundles = [request objectForKey:@"bundles"];
    NSMutableOrderedSet<NSString *> *bundleIdentifiers = [NSMutableOrderedSet orderedSet];
    for (NSString *bundleIdentifier in [rawBundles isKindOfClass:[NSArray class]] ? rawBundles : @[]) {
        if ([KayokoAppInfo isValidBundleIdentifier:bundleIdentifier]) {
            [bundleIdentifiers addObject:bundleIdentifier];
        }
    }
    if ([bundleIdentifiers count] == 0) {
        // SpringBoard-side fallback: enumerate the application registry.
        NSArray *applications = KayokoReadObject(controller, @"allApplications");
        if ([applications isKindOfClass:[NSSet class]]) applications = [(NSSet *)applications allObjects];
        for (id application in [applications isKindOfClass:[NSArray class]] ? applications : @[]) {
            NSString *bundleID = KayokoReadString(application, @"bundleIdentifier")
                ?: KayokoReadString(application, @"applicationIdentifier");
            if ([KayokoAppInfo isValidBundleIdentifier:bundleID]) [bundleIdentifiers addObject:bundleID];
        }
    }

    NSMutableDictionary<NSString *, NSDictionary *> *apps = [NSMutableDictionary dictionary];
    for (NSString *bundleIdentifier in bundleIdentifiers) {
        @autoreleasepool {
            id application = KayokoShortcutApplication(controller, bundleIdentifier);
            if (!application) continue;
            NSArray<NSDictionary *> *items = KayokoShortcutDescriptors(application);
            if ([items count] == 0) continue;
            NSString *name = KayokoReadString(application, @"displayName")
                ?: KayokoReadString(application, @"applicationDisplayName") ?: bundleIdentifier;
            [apps setObject:@{ @"name" : name, @"items" : items } forKey:bundleIdentifier];
        }
    }

    dispatch_async(KayokoShortcutRefreshQueue(), ^{
      [KayokoShortcutCatalog storeSnapshotWithApps:[apps copy] requestID:requestID];
    });
}

+ (void)activateShortcutWithType:(NSString *)shortcutType forBundleIdentifier:(NSString *)bundleIdentifier {
    if (![KayokoAppInfo isValidBundleIdentifier:bundleIdentifier] || [shortcutType length] == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      id application = KayokoShortcutApplication(KayokoShortcutApplicationController(), bundleIdentifier);
      id item = KayokoCurrentShortcutItem(application, shortcutType);
      if (!item) {
          NSLog(@"[Kayoko] shortcuts: current item missing for %@/%@", bundleIdentifier, shortcutType);
          return;
      }

      Class iconViewClass = NSClassFromString(@"SBIconView");
      SEL activateSelector = NSSelectorFromString(@"activateShortcut:withBundleIdentifier:forIconView:");
      if (!iconViewClass || ![iconViewClass respondsToSelector:activateSelector]) {
          NSLog(@"[Kayoko] shortcuts: SBIconView activation entry unavailable for %@/%@", bundleIdentifier, shortcutType);
          return;
      }
      @try {
          ((void (*)(id, SEL, id, id, id))objc_msgSend)(iconViewClass, activateSelector, item, bundleIdentifier, nil);
      } @catch (NSException *exception) {
          NSLog(@"[Kayoko] shortcuts: activation failed for %@/%@ (%@)", bundleIdentifier, shortcutType, exception);
      }
    });
}

@end
