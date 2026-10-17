#import "MTQuickActionProvider.h"
#import "common.h"
#import <objc/message.h>

static NSString *MTQAReadString(id object, NSString *propertyName) {
    SEL selector = NSSelectorFromString(propertyName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        return [value isKindOfClass:[NSString class]] ? value : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id MTQAReadObject(id object, NSString *propertyName) {
    SEL selector = NSSelectorFromString(propertyName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static dispatch_queue_t MTQASnapshotWriterQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.lindo.metis.keyboard.quickactions.snapshot", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void MTQAWriteStatus(NSString *phase, NSString *requestID, NSDictionary *details) {
    NSMutableDictionary *status = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
    status[@"phase"] = phase ?: @"unknown";
    status[@"updated"] = @([NSDate timeIntervalSinceReferenceDate]);
    if (requestID.length > 0) status[@"requestID"] = requestID;
    MTSetQuickActionSharedValue(status, TypeXQuickActionStatusKey);
}

static id MTQAApplicationController(void) {
    Class controllerClass = NSClassFromString(@"SBApplicationController");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if (!controllerClass || ![controllerClass respondsToSelector:sharedSelector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(controllerClass, sharedSelector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id MTQAApplication(id controller, NSString *bundleIdentifier) {
    SEL selector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if (!controller || ![controller respondsToSelector:selector] || bundleIdentifier.length == 0) return nil;
    @try {
        return ((id (*)(id, SEL, id))objc_msgSend)(controller, selector, bundleIdentifier);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSArray<NSString *> *MTQABundleIdentifiersFromController(id controller) {
    NSArray *applications = MTQAReadObject(controller, @"allApplications");
    if ([applications isKindOfClass:[NSSet class]]) applications = [(NSSet *)applications allObjects];
    if (![applications isKindOfClass:[NSArray class]]) return @[];

    NSMutableOrderedSet<NSString *> *bundleIdentifiers = [NSMutableOrderedSet orderedSet];
    for (id application in applications) {
        NSString *bundleIdentifier = MTQAReadString(application, @"bundleIdentifier")
            ?: MTQAReadString(application, @"applicationIdentifier");
        if (MTIsValidBundleIdentifier(bundleIdentifier)) [bundleIdentifiers addObject:bundleIdentifier];
    }
    return bundleIdentifiers.array;
}

static NSArray *MTQAArray(id value) {
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static NSArray *MTQAStaticItems(id application) {
    id info = MTQAReadObject(application, @"info");
    NSArray *items = MTQAArray(MTQAReadObject(info, @"staticApplicationShortcutItems"));
    if (items.count == 0) {
        items = MTQAArray(MTQAReadObject(application, @"staticApplicationShortcutItems"));
    }
    return items;
}

static NSArray *MTQADynamicItems(id application) {
    return MTQAArray(MTQAReadObject(application, @"dynamicApplicationShortcutItems"));
}

static NSDictionary *MTQADescriptor(id item, NSString *source) {
    NSString *type = MTQAReadString(item, @"type");
    if (type.length == 0 || [type hasPrefix:@"com.apple.springboard."]) return nil;

    NSString *title = MTQAReadString(item, @"localizedTitle") ?: MTQAReadString(item, @"title");
    NSString *subtitle = MTQAReadString(item, @"localizedSubtitle") ?: MTQAReadString(item, @"subtitle");
    NSMutableDictionary *descriptor = [NSMutableDictionary dictionaryWithDictionary:@{
        @"type": type,
        @"title": title.length > 0 ? title : type,
        @"source": source,
    }];
    if (subtitle.length > 0) descriptor[@"subtitle"] = subtitle;
    return descriptor;
}

// Dynamic items precede static items, matching the order used by the system
// menu. A type is the stable app-defined identity; duplicate types are exposed
// once and always resolve to the current first matching object at activation.
static NSArray<NSDictionary *> *MTQADescriptors(id application) {
    NSMutableArray<NSDictionary *> *descriptors = [NSMutableArray array];
    NSMutableSet<NSString *> *seenTypes = [NSMutableSet set];
    for (NSDictionary *sourceGroup in @[
        @{@"source": @"dynamic", @"items": MTQADynamicItems(application)},
        @{@"source": @"static", @"items": MTQAStaticItems(application)},
    ]) {
        for (id item in sourceGroup[@"items"]) {
            NSDictionary *descriptor = MTQADescriptor(item, sourceGroup[@"source"]);
            NSString *type = descriptor[@"type"];
            if (type.length == 0 || [seenTypes containsObject:type]) continue;
            [seenTypes addObject:type];
            [descriptors addObject:descriptor];
        }
    }
    return descriptors;
}

static id MTQACurrentItem(id application, NSString *shortcutType) {
    for (NSArray *items in @[MTQADynamicItems(application), MTQAStaticItems(application)]) {
        for (id item in items) {
            if ([MTQAReadString(item, @"type") isEqualToString:shortcutType]) return item;
        }
    }
    return nil;
}

@implementation MTQuickActionProvider

+ (void)refreshSnapshotForBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                                   requestID:(NSString *)requestID {
    NSString *resolvedRequestID = requestID.length > 0 ? requestID : [NSUUID UUID].UUIDString;
    dispatch_async(dispatch_get_main_queue(), ^{
        id controller = MTQAApplicationController();
        if (!controller) {
            MTQAWriteStatus(@"failed", resolvedRequestID, @{@"error": @"SBApplicationController unavailable"});
            NSLog(@"[MetisKeyboard] quickactions: SBApplicationController unavailable");
            return;
        }

        NSMutableOrderedSet<NSString *> *requested = [NSMutableOrderedSet orderedSet];
        for (id value in bundleIdentifiers) {
            if (MTIsValidBundleIdentifier(value)) [requested addObject:value];
        }
        if (requested.count == 0) {
            [requested addObjectsFromArray:MTQABundleIdentifiersFromController(controller)];
        }
        if (requested.count == 0) {
            MTQAWriteStatus(@"failed", resolvedRequestID, @{@"error": @"No applications available"});
            return;
        }

        MTQAWriteStatus(@"building", resolvedRequestID, @{@"requestedApps": @(requested.count)});
        NSMutableDictionary<NSString *, NSDictionary *> *apps = [NSMutableDictionary dictionary];
        NSUInteger staticCount = 0;
        NSUInteger dynamicCount = 0;
        for (NSString *bundleIdentifier in requested) {
            @autoreleasepool {
                id application = MTQAApplication(controller, bundleIdentifier);
                if (!application) continue;
                NSArray *staticItems = MTQAStaticItems(application);
                NSArray *dynamicItems = MTQADynamicItems(application);
                staticCount += staticItems.count;
                dynamicCount += dynamicItems.count;
                NSArray *items = MTQADescriptors(application);
                if (items.count == 0) continue;
                NSString *name = MTQAReadString(application, @"displayName")
                    ?: MTQAReadString(application, @"applicationDisplayName")
                    ?: bundleIdentifier;
                apps[bundleIdentifier] = @{@"name": name, @"items": items};
            }
        }

        NSDictionary *snapshot = @{
            @"format": @3,
            @"generation": resolvedRequestID,
            @"updated": @([NSDate timeIntervalSinceReferenceDate]),
            @"apps": [apps copy],
        };
        NSDictionary *stats = @{
            @"requestedApps": @(requested.count),
            @"appsWithShortcuts": @(apps.count),
            @"staticItems": @(staticCount),
            @"dynamicItems": @(dynamicCount),
        };
        dispatch_async(MTQASnapshotWriterQueue(), ^{
            if (!MTSetQuickActionSharedValue(snapshot, TypeXQuickActionSnapshotKey)) {
                MTQAWriteStatus(@"failed", resolvedRequestID, @{@"error": @"Snapshot write failed"});
                NSLog(@"[MetisKeyboard] quickactions: failed to write snapshot %@", resolvedRequestID);
                return;
            }
            MTQAWriteStatus(@"complete", resolvedRequestID, stats);
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 (__bridge CFStringRef)kShortcutSnapshotChangedIdentifier,
                                                 NULL, NULL, YES);
            NSLog(@"[MetisKeyboard] quickactions: snapshot %@ complete (%lu apps, %lu static, %lu dynamic)",
                  resolvedRequestID, (unsigned long)apps.count,
                  (unsigned long)staticCount, (unsigned long)dynamicCount);
        });
    });
}

// Synchronous dispatch on SpringBoard's main queue so the broker's freshness
// check covers the actual invocation. Success means dispatched, not app completion.
+ (MTSystemOpenResult)activateShortcutWithBundleIdentifier:(NSString *)bundleIdentifier
                                                    type:(NSString *)shortcutType {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) {
        return MTSystemOpenUnavailable;
    }
    if (!MTIsValidBundleIdentifier(bundleIdentifier) || bundleIdentifier.length > 256 ||
        !MTIsValidAppShortcutType(shortcutType)) return MTSystemOpenInvalid;
    id application = MTQAApplication(MTQAApplicationController(), bundleIdentifier);
    id item = MTQACurrentItem(application, shortcutType);
    if (!item) {
        NSLog(@"[TypeXSB] quickaction current item missing bundleID=%@", bundleIdentifier);
        return MTSystemOpenFailed;
    }
    Class iconViewClass = NSClassFromString(@"SBIconView");
    SEL activate = NSSelectorFromString(@"activateShortcut:withBundleIdentifier:forIconView:");
    NSMethodSignature *signature = [iconViewClass methodSignatureForSelector:activate];
    if (![iconViewClass respondsToSelector:activate] || signature.numberOfArguments != 5 ||
        !signature.methodReturnType || strcmp(signature.methodReturnType, @encode(void)) != 0) {
        return MTSystemOpenUnavailable;
    }
    @try {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(iconViewClass, activate, item, bundleIdentifier, nil);
        NSLog(@"[TypeXSB] quickaction dispatched bundleID=%@", bundleIdentifier);
        return MTSystemOpenSucceeded;
    } @catch (NSException *exception) {
        NSLog(@"[TypeXSB] quickaction exception=%@", exception.name);
        return MTSystemOpenFailed;
    }
}

@end
