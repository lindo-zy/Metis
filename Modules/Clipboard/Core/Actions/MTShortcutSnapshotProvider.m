//
//  MTShortcutSnapshotProvider.m
//  Mt
//

#import "MTShortcutSnapshotProvider.h"

#import "MTNotificationKeys.h"
#import "MTShortcutCatalog.h"
#import "MTAppInfo.h"

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

@interface SBApplication (MTShortcuts)
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *applicationIdentifier;
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, copy) NSString *applicationDisplayName;
@end

static NSString *MTReadString(id object, NSString *propertyName) {
    SEL selector = NSSelectorFromString(propertyName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        return [value isKindOfClass:[NSString class]] ? value : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id MTReadObject(id object, NSString *propertyName) {
    SEL selector = NSSelectorFromString(propertyName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id MTShortcutApplicationController(void) {
    Class controllerClass = NSClassFromString(@"SBApplicationController");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if (!controllerClass || ![controllerClass respondsToSelector:sharedSelector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(controllerClass, sharedSelector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id MTShortcutApplication(id controller, NSString *bundleIdentifier) {
    SEL selector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if (!controller || ![controller respondsToSelector:selector] || [bundleIdentifier length] == 0) return nil;
    @try {
        return ((id (*)(id, SEL, id))objc_msgSend)(controller, selector, bundleIdentifier);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSArray *MTShortcutArray(id value) {
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static NSArray *MTStaticShortcutItems(id application) {
    id info = MTReadObject(application, @"info");
    NSArray *items = MTShortcutArray(MTReadObject(info, @"staticApplicationShortcutItems"));
    if ([items count] == 0) {
        items = MTShortcutArray(MTReadObject(application, @"staticApplicationShortcutItems"));
    }
    return items;
}

static NSArray *MTDynamicShortcutItems(id application) {
    return MTShortcutArray(MTReadObject(application, @"dynamicApplicationShortcutItems"));
}

// Dynamic items precede static items, matching the order of the system menu.
// A type is the stable app-defined identity; duplicate types are exposed once.
static NSArray<NSDictionary *> *MTShortcutDescriptors(id application) {
    NSMutableArray<NSDictionary *> *descriptors = [NSMutableArray array];
    NSMutableSet<NSString *> *seenTypes = [NSMutableSet set];
    for (NSDictionary *sourceGroup in @[ @{@"source" : @"dynamic", @"items" : MTDynamicShortcutItems(application)},
                                         @{@"source" : @"static", @"items" : MTStaticShortcutItems(application)} ]) {
        for (id item in sourceGroup[@"items"]) {
            NSString *type = MTReadString(item, @"type");
            if ([type length] == 0 || [type hasPrefix:@"com.apple.springboard."]) continue;
            if ([seenTypes containsObject:type]) continue;
            [seenTypes addObject:type];

            NSString *title = MTReadString(item, @"localizedTitle") ?: MTReadString(item, @"title");
            NSString *subtitle = MTReadString(item, @"localizedSubtitle") ?: MTReadString(item, @"subtitle");
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

static id MTCurrentShortcutItem(id application, NSString *shortcutType) {
    for (NSArray *items in @[ MTDynamicShortcutItems(application), MTStaticShortcutItems(application) ]) {
        for (id item in items) {
            if ([MTReadString(item, @"type") isEqualToString:shortcutType]) return item;
        }
    }
    return nil;
}

static dispatch_queue_t MTShortcutRefreshQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      queue = dispatch_queue_create("com.lindo.metis.clipboard.shortcut.snapshot", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void mtShortcutRefreshRequestCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                 const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    // Always rebuild on the process main queue so UIKit-backed SpringBoard
    // state is read serially and never from the posting thread.
    dispatch_async(dispatch_get_main_queue(), ^{
      [MTShortcutSnapshotProvider handleRefreshRequest];
    });
}

@implementation MTShortcutSnapshotProvider

+ (void)installObserver {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    mtShortcutRefreshRequestCallback,
                                    (__bridge CFStringRef)kMTShortcutDarwinNotificationRefreshRequest, NULL,
                                    (CFNotificationSuspensionBehavior)CFNotificationSuspensionBehaviorDeliverImmediately);
}

+ (void)handleRefreshRequest {
    static NSString *lastRequestID = nil;
    NSString *requestID = [MTShortcutCatalog readRefreshRequestID];
    if ([requestID length] == 0) return;
    @synchronized([self class]) {
        if ([lastRequestID isEqualToString:requestID]) return;
        lastRequestID = [requestID copy];
    }

    id controller = MTShortcutApplicationController();
    if (!controller) {
        NSLog(@"[Mt] shortcuts: SBApplicationController unavailable");
        return;
    }

    NSDictionary *request = [MTShortcutCatalog readRefreshRequest];
    NSArray *rawBundles = [request objectForKey:@"bundles"];
    NSMutableOrderedSet<NSString *> *bundleIdentifiers = [NSMutableOrderedSet orderedSet];
    for (NSString *bundleIdentifier in [rawBundles isKindOfClass:[NSArray class]] ? rawBundles : @[]) {
        if ([MTAppInfo isValidBundleIdentifier:bundleIdentifier]) {
            [bundleIdentifiers addObject:bundleIdentifier];
        }
    }
    if ([bundleIdentifiers count] == 0) {
        // SpringBoard-side fallback: enumerate the application registry.
        NSArray *applications = MTReadObject(controller, @"allApplications");
        if ([applications isKindOfClass:[NSSet class]]) applications = [(NSSet *)applications allObjects];
        for (id application in [applications isKindOfClass:[NSArray class]] ? applications : @[]) {
            NSString *bundleID = MTReadString(application, @"bundleIdentifier")
                ?: MTReadString(application, @"applicationIdentifier");
            if ([MTAppInfo isValidBundleIdentifier:bundleID]) [bundleIdentifiers addObject:bundleID];
        }
    }

    NSMutableDictionary<NSString *, NSDictionary *> *apps = [NSMutableDictionary dictionary];
    for (NSString *bundleIdentifier in bundleIdentifiers) {
        @autoreleasepool {
            id application = MTShortcutApplication(controller, bundleIdentifier);
            if (!application) continue;
            NSArray<NSDictionary *> *items = MTShortcutDescriptors(application);
            if ([items count] == 0) continue;
            NSString *name = MTReadString(application, @"displayName")
                ?: MTReadString(application, @"applicationDisplayName") ?: bundleIdentifier;
            [apps setObject:@{ @"name" : name, @"items" : items } forKey:bundleIdentifier];
        }
    }

    dispatch_async(MTShortcutRefreshQueue(), ^{
      [MTShortcutCatalog storeSnapshotWithApps:[apps copy] requestID:requestID];
    });
}

+ (void)activateShortcutWithType:(NSString *)shortcutType forBundleIdentifier:(NSString *)bundleIdentifier {
    if (![MTAppInfo isValidBundleIdentifier:bundleIdentifier] || [shortcutType length] == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      id application = MTShortcutApplication(MTShortcutApplicationController(), bundleIdentifier);
      id item = MTCurrentShortcutItem(application, shortcutType);
      if (!item) {
          NSLog(@"[Mt] shortcuts: current item missing for %@/%@", bundleIdentifier, shortcutType);
          return;
      }

      Class iconViewClass = NSClassFromString(@"SBIconView");
      SEL activateSelector = NSSelectorFromString(@"activateShortcut:withBundleIdentifier:forIconView:");
      if (!iconViewClass || ![iconViewClass respondsToSelector:activateSelector]) {
          NSLog(@"[Mt] shortcuts: SBIconView activation entry unavailable for %@/%@", bundleIdentifier, shortcutType);
          return;
      }
      @try {
          ((void (*)(id, SEL, id, id, id))objc_msgSend)(iconViewClass, activateSelector, item, bundleIdentifier, nil);
      } @catch (NSException *exception) {
          NSLog(@"[Mt] shortcuts: activation failed for %@/%@ (%@)", bundleIdentifier, shortcutType, exception);
      }
    });
}

@end
