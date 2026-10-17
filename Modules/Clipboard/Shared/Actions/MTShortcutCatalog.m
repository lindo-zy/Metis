//
//  MTShortcutCatalog.m
//  Mt
//

#import "MTShortcutCatalog.h"

#import <CoreFoundation/CoreFoundation.h>

NSString *const kMTShortcutDarwinNotificationRefreshRequest = @"com.lindo.metis.clipboard.shortcut.refresh";
NSString *const kMTShortcutDarwinNotificationSnapshotChanged = @"com.lindo.metis.clipboard.shortcut.changed";

// One domain for request, status and snapshot; values are replaced as whole
// generations so removed apps and actions cannot survive an incremental merge.
static NSString *const kMTShortcutCatalogDomain = @"com.lindo.metis.clipboard.quickactions";
static NSString *const kMTShortcutCatalogRequestKey = @"request-v1";
static NSString *const kMTShortcutCatalogSnapshotKey = @"snapshot-v1";
static NSInteger const kMTShortcutCatalogFormatVersion = 1;

@implementation MTShortcutItem
@end

static id MTShortcutCatalogValue(NSString *key) {
    CFStringRef domain = (__bridge CFStringRef)kMTShortcutCatalogDomain;
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key, domain, kCFPreferencesCurrentUser,
                                                    kCFPreferencesAnyHost));
}

static void MTShortcutCatalogPostDarwinNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)name, NULL, NULL, YES);
}

@implementation MTShortcutCatalog

+ (NSDictionary<NSString *, NSDictionary *> *)snapshotGroups {
    @try {
        NSDictionary *root = MTShortcutCatalogValue(kMTShortcutCatalogSnapshotKey);
        if (![root isKindOfClass:[NSDictionary class]]) {
            return @{};
        }
        id format = root[@"format"];
        if (![format isKindOfClass:[NSNumber class]] || [format integerValue] != kMTShortcutCatalogFormatVersion) {
            return @{};
        }
        NSDictionary *apps = root[@"apps"];
        if (![apps isKindOfClass:[NSDictionary class]]) {
            return @{};
        }
        return apps;
    } @catch (NSException *exception) {
        NSLog(@"[Mt] shortcut catalogue unreadable (%@)", exception);
        return @{};
    }
}

+ (NSArray<NSDictionary *> *)displayGroups {
    NSDictionary<NSString *, NSDictionary *> *snapshotGroups = [self snapshotGroups];
    if ([snapshotGroups count] == 0) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *groups = [NSMutableArray array];
    for (NSString *bundleID in snapshotGroups) {
        if (![bundleID isKindOfClass:[NSString class]] || [bundleID length] == 0) continue;
        NSDictionary *entry = snapshotGroups[bundleID];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSArray *rawItems = entry[@"items"];
        if (![rawItems isKindOfClass:[NSArray class]]) continue;

        NSMutableArray<MTShortcutItem *> *items = [NSMutableArray array];
        NSMutableSet<NSString *> *seenTypes = [NSMutableSet set];
        for (NSDictionary *raw in rawItems) {
            if (![raw isKindOfClass:[NSDictionary class]]) continue;
            NSString *type = raw[@"type"];
            if (![type isKindOfClass:[NSString class]] || [type length] == 0) continue;
            if ([seenTypes containsObject:type]) continue;
            [seenTypes addObject:type];

            MTShortcutItem *item = [[MTShortcutItem alloc] init];
            item.type = type;
            item.title = [raw[@"title"] isKindOfClass:[NSString class]] && [raw[@"title"] length] > 0
                ? raw[@"title"]
                : type;
            item.subtitle = [raw[@"subtitle"] isKindOfClass:[NSString class]] ? raw[@"subtitle"] : nil;
            item.dynamic = [raw[@"source"] isEqualToString:@"dynamic"];
            [items addObject:item];
        }
        if ([items count] == 0) continue;

        NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] && [entry[@"name"] length] > 0
            ? entry[@"name"]
            : bundleID;
        [groups addObject:@{@"name" : name, @"bundleID" : bundleID, @"items" : [items copy]}];
    }
    [groups sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
      return [[left objectForKey:@"name"] localizedStandardCompare:[right objectForKey:@"name"]];
    }];
    return [groups copy];
}

+ (void)requestSnapshotRefreshForBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers {
    NSDictionary *request = @{
        @"format" : @(kMTShortcutCatalogFormatVersion),
        @"requestID" : [[NSUUID UUID] UUIDString],
        @"bundles" : [bundleIdentifiers copy] ?: @[]
    };
    CFStringRef domain = (__bridge CFStringRef)kMTShortcutCatalogDomain;
    CFPreferencesSetValue((__bridge CFStringRef)kMTShortcutCatalogRequestKey,
                          (__bridge CFPropertyListRef)request, domain, kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    MTShortcutCatalogPostDarwinNotification(kMTShortcutDarwinNotificationRefreshRequest);
}

+ (nullable NSString *)readRefreshRequestID {
    NSDictionary *request = [self readRefreshRequest];
    NSString *requestID = request[@"requestID"];
    return [requestID isKindOfClass:[NSString class]] ? requestID : nil;
}

+ (NSDictionary *)readRefreshRequest {
    NSDictionary *request = MTShortcutCatalogValue(kMTShortcutCatalogRequestKey);
    return [request isKindOfClass:[NSDictionary class]] ? request : @{};
}

+ (void)storeSnapshotWithApps:(NSDictionary<NSString *, NSDictionary *> *)apps
                    requestID:(NSString *)requestID {
    NSDictionary *snapshot = @{
        @"format" : @(kMTShortcutCatalogFormatVersion),
        @"generation" : requestID ?: @"",
        @"updated" : @([NSDate timeIntervalSinceReferenceDate]),
        @"apps" : apps ?: @{}
    };
    CFStringRef domain = (__bridge CFStringRef)kMTShortcutCatalogDomain;
    CFPreferencesSetValue((__bridge CFStringRef)kMTShortcutCatalogSnapshotKey,
                          (__bridge CFPropertyListRef)snapshot, domain, kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    MTShortcutCatalogPostDarwinNotification(kMTShortcutDarwinNotificationSnapshotChanged);
}

@end
