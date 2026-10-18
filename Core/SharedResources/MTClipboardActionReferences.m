#import "MTClipboardActionReferences.h"
#import "MTSharedResourceStore.h"
#import "MTSharedResourceIDs.h"

static NSString *MTClipboardPrefix(NSString *slot) {
    return [NSString stringWithFormat:@"clipboard.%@.", slot];
}

@implementation MTClipboardActionReferences

+ (BOOL)supportsEntry:(NSDictionary *)entry {
    NSString *type = entry[@"type"] ?: @"";
    if ([type isEqual:@"javascript"]) {
        return [entry[@"jsInput"] isEqual:@"clipboard"] && [entry[@"jsOutput"] isEqual:@"copy"];
    }
    // Text insertion requires a live editor; clipboard panels have no input session.
    return [@[@"", @"url", @"urlscheme", @"openapp", @"shortcut", @"system"] containsObject:type];
}

+ (NSArray<NSDictionary *> *)actionsInDocument:(NSDictionary *)document slot:(NSString *)slot {
    NSMutableDictionary *byID = [NSMutableDictionary dictionary];
    for (NSDictionary *action in document[@"actions"]) byID[action[@"id"]] = action[@"entry"];
    NSString *prefix = MTClipboardPrefix(slot);
    NSMutableArray *bindings = [NSMutableArray array];
    for (NSDictionary *binding in document[@"bindings"]) {
        if ([binding[@"id"] hasPrefix:prefix]) [bindings addObject:binding];
    }
    [bindings sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [(a[@"order"] ?: @0) compare:(b[@"order"] ?: @0)];
    }];
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *binding in bindings) {
        if (![binding[@"target"][@"kind"] isEqual:MTSharedTargetKindAction]) continue;
        NSString *uuid = binding[@"target"][@"id"];
        NSDictionary *entry = byID[uuid];
        if (!entry || ![self supportsEntry:entry]) continue;
        NSMutableDictionary *resolved = [entry mutableCopy];
        resolved[@"id"] = uuid;
        resolved[@"title"] = entry[@"name"] ?: @"未命名动作";
        resolved[@"icon"] = entry[@"icon"] ?: @"link";
        [result addObject:resolved];
    }
    return result;
}

+ (NSDictionary *)document:(NSDictionary *)document settingActionIDs:(NSArray<NSString *> *)ids slot:(NSString *)slot {
    NSMutableDictionary *next = [document mutableCopy];
    NSMutableArray *bindings = [NSMutableArray array];
    NSString *prefix = MTClipboardPrefix(slot);
    for (NSDictionary *binding in document[@"bindings"]) {
        if (![binding[@"id"] hasPrefix:prefix]) [bindings addObject:binding];
    }
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *uuid in ids) {
        if ([seen containsObject:uuid]) continue;
        [seen addObject:uuid];
        [bindings addObject:@{ @"id": [prefix stringByAppendingString:uuid],
            @"source": MTSharedResourceSourceClipboard, @"order": @(seen.count - 1),
            @"target": @{ @"kind": MTSharedTargetKindAction, @"id": uuid } }];
        if ([slot isEqual:@"image-double-tap"]) break;
    }
    next[@"bindings"] = bindings;
    return next;
}

+ (BOOL)setActionIDs:(NSArray<NSString *> *)ids slot:(NSString *)slot expectedRevision:(uint64_t)revision error:(NSError **)error {
    NSDictionary *current = [MTSharedResourceStore readSnapshotError:error];
    if (!current) return NO;
    return [MTSharedResourceStore commitSnapshot:[self document:current settingActionIDs:ids slot:slot]
                                expectedRevision:revision error:error];
}

+ (NSDictionary *)document:(NSDictionary *)document importingText:(NSArray *)text image:(NSArray *)image doubleTapURL:(NSString *)url {
    if ([document[@"migration"][@"clipboardActionReferencesV1"] boolValue]) return document;
    NSMutableDictionary *next = [document mutableCopy];
    NSMutableArray *actions = [document[@"actions"] mutableCopy];
    NSArray *doubleTap = url.length ? @[@{ @"uuid": @"double-tap", @"title": @"图片双击动作", @"link": url }] : @[];
    NSArray *slots = @[@"text", @"image", @"image-double-tap"];
    NSArray *lists = @[text, image, doubleTap];
    for (NSUInteger index = 0; index < slots.count; index++) {
        NSString *slot = slots[index];
        NSMutableArray *ids = [NSMutableArray array];
        NSUInteger position = 0;
        for (NSDictionary *old in lists[index]) {
            if (![old isKindOfClass:NSDictionary.class] || ![old[@"link"] isKindOfClass:NSString.class]) continue;
            NSString *selector = [@"__typex_link_action_clipboard_" stringByAppendingString:
                MTSharedDeterministicUUID([NSString stringWithFormat:@"%@|%@|%lu", slot, old[@"uuid"] ?: @"", (unsigned long)position++])];
            NSString *uuid = MTSharedDeterministicUUID([@"keyboard|action|" stringByAppendingString:selector]);
            NSMutableDictionary *entry = [old mutableCopy];
            [entry removeObjectForKey:@"uuid"];
            [entry removeObjectForKey:@"title"];
            entry[@"name"] = old[@"title"] ?: @"未命名动作";
            entry[@"type"] = old[@"type"] ?: @"urlscheme";
            [actions addObject:@{ @"id": uuid, @"entry": entry,
                @"legacyRef": @{ @"source": MTSharedResourceSourceKeyboard, @"selector": selector } }];
            [ids addObject:uuid];
        }
        next[@"actions"] = actions;
        // Do not overwrite bindings already configured in the shared library.
        BOOL configured = NO;
        for (NSDictionary *binding in next[@"bindings"]) {
            if ([binding[@"id"] hasPrefix:MTClipboardPrefix(slot)]) configured = YES;
        }
        if (!configured) next = [[self document:next settingActionIDs:ids slot:slot] mutableCopy];
    }
    NSMutableDictionary *migration = [document[@"migration"] mutableCopy] ?: [NSMutableDictionary dictionary];
    migration[@"clipboardActionReferencesV1"] = @YES;
    next[@"migration"] = migration;
    return next;
}
@end
