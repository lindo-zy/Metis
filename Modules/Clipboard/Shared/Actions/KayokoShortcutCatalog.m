//
//  KayokoShortcutCatalog.m
//  Kayoko
//

#import "KayokoShortcutCatalog.h"

#import <CoreFoundation/CoreFoundation.h>

NSString *const kKayokoShortcutDarwinNotificationRefreshRequest = @"com.lindo.kayoko.shortcut.refresh";
NSString *const kKayokoShortcutDarwinNotificationSnapshotChanged = @"com.lindo.kayoko.shortcut.changed";

// One domain for request, status and snapshot; values are replaced as whole
// generations so removed apps and actions cannot survive an incremental merge.
static NSString *const kKayokoShortcutCatalogDomain = @"com.lindo.kayoko.quickactions";
static NSString *const kKayokoShortcutCatalogRequestKey = @"request-v1";
static NSString *const kKayokoShortcutCatalogSnapshotKey = @"snapshot-v1";
static NSInteger const kKayokoShortcutCatalogFormatVersion = 1;

@implementation KayokoShortcutItem
@end

static id KayokoShortcutCatalogValue(NSString *key) {
    CFStringRef domain = (__bridge CFStringRef)kKayokoShortcutCatalogDomain;
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key, domain, kCFPreferencesCurrentUser,
                                                    kCFPreferencesAnyHost));
}

static void KayokoShortcutCatalogPostDarwinNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)name, NULL, NULL, YES);
}

@implementation KayokoShortcutCatalog

+ (NSDictionary<NSString *, NSDictionary *> *)snapshotGroups {
    @try {
        NSDictionary *root = KayokoShortcutCatalogValue(kKayokoShortcutCatalogSnapshotKey);
        if (![root isKindOfClass:[NSDictionary class]]) {
            return @{};
        }
        id format = root[@"format"];
        if (![format isKindOfClass:[NSNumber class]] || [format integerValue] != kKayokoShortcutCatalogFormatVersion) {
            return @{};
        }
        NSDictionary *apps = root[@"apps"];
        if (![apps isKindOfClass:[NSDictionary class]]) {
            return @{};
        }
        return apps;
    } @catch (NSException *exception) {
        NSLog(@"[Kayoko] shortcut catalogue unreadable (%@)", exception);
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

        NSMutableArray<KayokoShortcutItem *> *items = [NSMutableArray array];
        NSMutableSet<NSString *> *seenTypes = [NSMutableSet set];
        for (NSDictionary *raw in rawItems) {
            if (![raw isKindOfClass:[NSDictionary class]]) continue;
            NSString *type = raw[@"type"];
            if (![type isKindOfClass:[NSString class]] || [type length] == 0) continue;
            if ([seenTypes containsObject:type]) continue;
            [seenTypes addObject:type];

            KayokoShortcutItem *item = [[KayokoShortcutItem alloc] init];
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
        @"format" : @(kKayokoShortcutCatalogFormatVersion),
        @"requestID" : [[NSUUID UUID] UUIDString],
        @"bundles" : [bundleIdentifiers copy] ?: @[]
    };
    CFStringRef domain = (__bridge CFStringRef)kKayokoShortcutCatalogDomain;
    CFPreferencesSetValue((__bridge CFStringRef)kKayokoShortcutCatalogRequestKey,
                          (__bridge CFPropertyListRef)request, domain, kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    KayokoShortcutCatalogPostDarwinNotification(kKayokoShortcutDarwinNotificationRefreshRequest);
}

+ (nullable NSString *)readRefreshRequestID {
    NSDictionary *request = [self readRefreshRequest];
    NSString *requestID = request[@"requestID"];
    return [requestID isKindOfClass:[NSString class]] ? requestID : nil;
}

+ (NSDictionary *)readRefreshRequest {
    NSDictionary *request = KayokoShortcutCatalogValue(kKayokoShortcutCatalogRequestKey);
    return [request isKindOfClass:[NSDictionary class]] ? request : @{};
}

+ (void)storeSnapshotWithApps:(NSDictionary<NSString *, NSDictionary *> *)apps
                    requestID:(NSString *)requestID {
    NSDictionary *snapshot = @{
        @"format" : @(kKayokoShortcutCatalogFormatVersion),
        @"generation" : requestID ?: @"",
        @"updated" : @([NSDate timeIntervalSinceReferenceDate]),
        @"apps" : apps ?: @{}
    };
    CFStringRef domain = (__bridge CFStringRef)kKayokoShortcutCatalogDomain;
    CFPreferencesSetValue((__bridge CFStringRef)kKayokoShortcutCatalogSnapshotKey,
                          (__bridge CFPropertyListRef)snapshot, domain, kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    KayokoShortcutCatalogPostDarwinNotification(kKayokoShortcutDarwinNotificationSnapshotChanged);
}

@end
