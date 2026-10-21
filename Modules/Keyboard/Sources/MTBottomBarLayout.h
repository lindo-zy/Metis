#pragma once
#import <Foundation/Foundation.h>
#import "MTContextGroupPreferences.h"
#import "MTContextGroupTypes.h"

#define kBottomBarLayoutKey @"bottomBarLayoutV1"
#define MTBottomBarSegmentCapacity 8

// One validated schema for Settings, previews and injected hosts. An explicit
// empty segment stays empty; malformed/unknown versions fall back to legacy.
static inline NSDictionary *MTBottomBarEntry(id raw) {
    if (![raw isKindOfClass:NSDictionary.class]) return nil;
    NSString *kind = raw[@"kind"], *value = raw[@"value"];
    if (![kind isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class] || !value.length || value.length > 512) return nil;
    if (![@[@"action", @"context", @"app"] containsObject:kind]) return nil;
    if ([kind isEqual:@"context"] && ![@[@"auto", @"selection", @"clipboard", @"paste", @"input", @"idle"] containsObject:value]) return nil;
    if ([kind isEqual:@"app"] && [value rangeOfString:@"^[A-Za-z0-9_-]+(?:\\.[A-Za-z0-9_-]+)+$" options:NSRegularExpressionSearch].location == NSNotFound) return nil;
    NSInteger index = [raw[@"index"] isKindOfClass:NSNumber.class] ? [raw[@"index"] integerValue] : 0;
    return @{@"kind":kind, @"value":value, @"index":@(MAX(0, MIN(2, index))),
        @"title":[raw[@"title"] isKindOfClass:NSString.class] ? [raw[@"title"] substringToIndex:MIN((NSUInteger)128, [raw[@"title"] length])] : @"",
        @"fallback":@([raw[@"fallback"] isKindOfClass:NSNumber.class] && [raw[@"fallback"] boolValue])};
}
static inline NSArray *MTBottomBarEntries(id raw) {
    NSMutableArray *entries = [NSMutableArray array];
    for (id item in [raw isKindOfClass:NSArray.class] ? raw : @[]) {
        NSDictionary *entry = MTBottomBarEntry(item);
        if (entry) [entries addObject:entry];
        if (entries.count == MTBottomBarSegmentCapacity) break;
    }
    return entries;
}
static inline NSDictionary *MTBottomBarLayout(NSDictionary *prefs) {
    id stored = prefs[kBottomBarLayoutKey];
    BOOL valid = [stored isKindOfClass:NSDictionary.class] && [stored[@"version"] isEqual:@1] &&
        [stored[@"left"] isKindOfClass:NSArray.class] && [stored[@"right"] isKindOfClass:NSArray.class];
    NSMutableArray *left = [NSMutableArray array], *right = [NSMutableArray array];
    if (valid) {
        [left addObjectsFromArray:MTBottomBarEntries(stored[@"left"])];
        [right addObjectsFromArray:MTBottomBarEntries(stored[@"right"])];
    } else {
        id old = prefs[@"shortcuts"];
        NSArray *items = [old isKindOfClass:NSArray.class] && [old count] && [old[0] isKindOfClass:NSArray.class] ? old[0] : @[];
        if (!old) items = @[@{@"selector":@"selectAllAction:"}, @{@"selector":@"copyAction:"}, @{@"selector":@"pasteAction:"}];
        for (id item in items) {
            if (![item isKindOfClass:NSDictionary.class] || ([item[@"disabled"] isKindOfClass:NSNumber.class] && [item[@"disabled"] boolValue])) continue;
            NSDictionary *entry = MTBottomBarEntry(@{@"kind":@"action", @"value":item[@"selector"] ?: @""});
            if (entry) [left addObject:entry];
            if (left.count == 3) break;
        }
        for (NSInteger i = 0; i < MTContextSlots(prefs); i++)
            [right addObject:MTBottomBarEntry(@{@"kind":@"context", @"value":@"auto", @"index":@(i), @"fallback":@YES})];
    }
    BOOL single = valid && [stored[@"single"] isKindOfClass:NSNumber.class] && [stored[@"single"] boolValue];
    BOOL equal = !valid || ![stored[@"equal"] isKindOfClass:NSNumber.class] || [stored[@"equal"] boolValue];
    return @{@"version":@1, @"left":left, @"right":right, @"single":@(single), @"equal":@(equal)};
}
static inline double MTBottomBarWeight(NSArray *entries, BOOL equal) {
    if (equal) return entries.count;
    double result = 0;
    for (NSDictionary *entry in entries) result += [entry[@"kind"] isEqual:@"context"] ? 1.55 : ([entry[@"kind"] isEqual:@"app"] ? 1.0 : 1.15);
    return result;
}
static inline double MTBottomBarLeftFraction(NSDictionary *layout) {
    if ([layout[@"single"] boolValue]) return 1;
    double left = MTBottomBarWeight(layout[@"left"], [layout[@"equal"] boolValue]);
    double right = MTBottomBarWeight(layout[@"right"], [layout[@"equal"] boolValue]);
    return left + right > 0 ? left / (left + right) : 0.5;
}

// A group occupies a stable cell even when its trigger is inactive. Only the
// winning group may supply actions; rendering never reads clipboard/input.
static inline MTContextAction *MTBottomBarContextAction(NSDictionary *entry, MTContextDecision *decision) {
    if (![entry[@"kind"] isEqual:@"context"] || !decision) return nil;
    NSString *group = entry[@"value"];
    if (![group isEqual:@"auto"] && ![group isEqual:MTContextGroupKey(decision.group)]) return nil;
    NSUInteger index = [entry[@"index"] unsignedIntegerValue];
    return index < decision.actions.count ? decision.actions[index] : nil;
}
