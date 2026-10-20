#import "MTContextGroupTypes.h"
#import "MTContextGroupPreferences.h"

@implementation MTContextAction
+ (instancetype)actionWithIdentifier:(NSString *)identifier
                               title:(NSString *)title
                              symbol:(NSString *)symbol
                         payloadKind:(MTContextPayloadKind)payloadKind
                             payload:(NSString *)payload {
    MTContextAction *action = [MTContextAction new];
    if (action) {
        action->_identifier = [identifier copy];
        action->_title = [title copy];
        action->_symbol = [symbol copy];
        action->_payloadKind = payloadKind;
        action->_payload = [payload copy];
    }
    return action;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<MTContextAction %@ kind=%ld>", self.identifier, (long)self.payloadKind];
}
@end

@implementation MTContextDecision
+ (instancetype)decisionWithGroup:(MTContextGroup)group
                           reason:(NSString *)reason
                          actions:(NSArray<MTContextAction *> *)actions
                              ttl:(NSTimeInterval)ttl {
    MTContextDecision *decision = [MTContextDecision new];
    if (decision) {
        decision->_group = group;
        decision->_reason = [reason copy] ?: @"";
        decision->_actions = [actions copy] ?: @[];
        decision->_ttl = MAX(0, ttl);
    }
    return decision;
}
- (BOOL)isEquivalentToDecision:(MTContextDecision *)other {
    if (![other isKindOfClass:MTContextDecision.class]) return NO;
    if (other.group != self.group || ![other.reason isEqual:self.reason]) return NO;
    if (other.actions.count != self.actions.count) return NO;
    for (NSUInteger index = 0; index < self.actions.count; index++) {
        MTContextAction *a = self.actions[index], *b = other.actions[index];
        if (![b.identifier isEqual:a.identifier] || ![b.payload isEqual:a.payload] ||
            ![b.title isEqual:a.title] || ![b.symbol isEqual:a.symbol] || b.payloadKind != a.payloadKind) return NO;
    }
    return YES;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<MTContextDecision %@ reason=%@ actions=%lu ttl=%.1f>",
            MTContextGroupName(self.group), self.reason, (unsigned long)self.actions.count, self.ttl];
}
@end

NSString *MTContextGroupName(MTContextGroup group) {
    switch (group) {
        case MTContextGroupDefault: return @"G0-default";
        case MTContextGroupSelection: return @"G1-selection";
        case MTContextGroupClipboard: return @"G2-clipboard";
        case MTContextGroupPaste: return @"G3-paste";
        case MTContextGroupInput: return @"G4-input";
        case MTContextGroupIdle: return @"G5-idle";
        case MTContextGroupNone: return @"none";
    }
    return @"unknown";
}

NSString *MTContextGroupKey(MTContextGroup group) {
    switch (group) {
        case MTContextGroupSelection: return @"selection";
        case MTContextGroupClipboard: return @"clipboard";
        case MTContextGroupPaste: return @"paste";
        case MTContextGroupInput: return @"input";
        case MTContextGroupIdle: return @"idle";
        default: return @"default";
    }
}
NSArray<NSNumber *> *MTContextPriority(NSDictionary *preferences) {
    NSArray *defaults = @[@(MTContextGroupSelection), @(MTContextGroupPaste), @(MTContextGroupClipboard), @(MTContextGroupInput), @(MTContextGroupIdle)];
    NSMutableArray *result = [NSMutableArray array];
    id stored = preferences[kContextPriorityKey];
    for (id value in [stored isKindOfClass:NSArray.class] ? stored : @[]) {
        if ([value isKindOfClass:NSNumber.class] && [defaults containsObject:value] && ![result containsObject:value]) [result addObject:value];
    }
    for (NSNumber *value in defaults) if (![result containsObject:value]) [result addObject:value];
    return result;
}

@implementation MTContextSnapshot
- (NSString *)description {
    return [NSString stringWithFormat:@"<MTContextSnapshot sel=%lu/%lu clip=%d/%.1fs paste=%lu/%.1fs input=%lu secure=%d type=%@ kb=%ld>",
            (unsigned long)self.selectionLength, (unsigned long)self.selectionText.length,
            self.clipboardAvailable, self.clipboardAge, (unsigned long)self.pastedLength,
            self.pasteAge, (unsigned long)self.inputLength, self.secureInput,
            self.contentType ?: @"-", (long)self.keyboardType];
}
@end

static BOOL MTContextBoolValue(NSDictionary *preferences, NSString *key, BOOL fallback) {
    id value = preferences[key];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}

static double MTContextDoubleValue(NSDictionary *preferences, NSString *key, double fallback,
                                   double minimum, double maximum) {
    id value = preferences[key];
    if (![value isKindOfClass:NSNumber.class]) return fallback;
    double result = [value doubleValue];
    if (!(result >= minimum) || !(result <= maximum)) return fallback;
    return result;
}

@implementation MTContextGroupSettings
+ (instancetype)settingsFromPreferences:(NSDictionary *)preferences {
    MTContextGroupSettings *settings = [MTContextGroupSettings new];
    if (!settings) return nil;
    NSDictionary *source = [preferences isKindOfClass:NSDictionary.class] ? preferences : @{};
    settings.enabled = MTContextBoolValue(source, kContextGroupsEnabledKey, YES);
    settings.selectionEnabled = MTContextBoolValue(source, kContextSelectionGroupKey, YES);
    settings.clipboardEnabled = MTContextBoolValue(source, kContextClipboardGroupKey, YES);
    settings.pasteEnabled = MTContextBoolValue(source, kContextPasteGroupKey, YES);
    settings.inputEnabled = MTContextBoolValue(source, kContextInputGroupKey, YES);
    settings.idleEnabled = MTContextBoolValue(source, kContextIdleGroupKey, NO);
    settings.priority = MTContextPriority(source);
    settings.configuredActions = [source[kContextActionsKey] isKindOfClass:NSDictionary.class] ? source[kContextActionsKey] : @{};
    // 新鲜期越界一律回默认值：配置被写成 0 或负数时，组会永远不亮或永远不灭。
    settings.clipboardFreshness = MTContextDoubleValue(source, kContextClipboardFreshnessKey, 8, 2, 60);
    settings.pasteFreshness = MTContextDoubleValue(source, kContextPasteFreshnessKey, 3, 1, 15);
    settings.pasteMinLength = (NSUInteger)MTContextDoubleValue(source, kContextPasteMinLengthKey, 1, 1, 500);
    return settings;
}
@end
