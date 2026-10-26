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

#pragma mark - Capture rules

static NSString *MTClipboardRuleAlwaysMatchSource(NSString *kind) {
    // 迁移产物：恒匹配（调用方已按槽位/类型圈定适用范围），保留 match(text, meta) 签名。
    return [NSString stringWithFormat:@"function match(text, meta) {\n  return meta && meta.kind === '%@';\n}", kind];
}

+ (NSArray<NSDictionary *> *)ruleDictionariesInDocument:(NSDictionary *)document {
    id raw = document[@"clipboardRules"];
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *entry in raw) {
        if ([entry isKindOfClass:NSDictionary.class]) [result addObject:entry];
    }
    return result;
}

+ (NSDictionary *)document:(NSDictionary *)document settingRuleDictionaries:(NSArray<NSDictionary *> *)rules {
    NSMutableDictionary *next = [document mutableCopy];
    next[@"clipboardRules"] = [rules isKindOfClass:NSArray.class] ? rules : @[];
    // 显式规则一旦存在，旧槽位迁移不得再覆盖 clipboardRules。
    NSMutableDictionary *migration = [next[@"migration"] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (!migration[@"clipboardRulesV1"]) migration[@"clipboardRulesV1"] = @YES;
    next[@"migration"] = migration;
    return next;
}

+ (BOOL)migrateLegacySlotRulesIfNeeded:(NSError **)error {
    NSDictionary *current = [MTSharedResourceStore readSnapshotError:error];
    if (!current) return NO;
    if ([current[@"migration"][@"clipboardRulesV1"] boolValue]) return YES;
    // 旧双击语义 = 执行槽位第一个动作；按 image-double-tap → image → text 的
    // 顺序转成恒匹配规则，原有配置行为保留（未命中仍不执行任何动作）。
    NSArray<NSDictionary *> *legacyRules = @[
        @{ @"slot": @"image-double-tap", @"kind": @"image" },
        @{ @"slot": @"image", @"kind": @"image" },
        @{ @"slot": @"text", @"kind": @"text" }
    ];
    NSMutableArray *rules = [NSMutableArray array];
    for (NSDictionary *legacy in legacyRules) {
        NSArray<NSDictionary *> *actions = [self actionsInDocument:current slot:legacy[@"slot"]];
        if (actions.count == 0) continue;
        NSMutableArray *ids = [NSMutableArray array];
        for (NSDictionary *action in actions) [ids addObject:action[@"id"]];
        [rules addObject:@{ @"id": MTSharedDeterministicUUID([@"clipboard-rule|" stringByAppendingString:legacy[@"slot"]]),
                            @"name": [legacy[@"slot"] isEqual:@"text"] ? @"文字动作" :
                                     ([legacy[@"slot"] isEqual:@"image"] ? @"图片动作" : @"图片双击动作"),
                            @"enabled": @YES, @"auto": @NO,
                            @"source": MTClipboardRuleAlwaysMatchSource(legacy[@"kind"]),
                            @"actions": ids }];
    }
    return [MTSharedResourceStore commitSnapshot:[self document:current settingRuleDictionaries:rules]
                                expectedRevision:[MTSharedResourceStore currentRevision] error:error];
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
