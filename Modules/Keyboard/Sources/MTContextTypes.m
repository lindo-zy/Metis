#import "MTContextTypes.h"
#import "MTBottomBarLayout.h"
#import "MTPanelRegistry.h"
#import <objc/message.h>
#import <JavaScriptCore/JavaScriptCore.h>

NSString *MTContextCanonicalGroup(NSString *key) {
    if ([key isEqual:@"clipboard"]) return @"copy";
    if ([key isEqual:@"input"]) return @"typing";
    return key;
}
NSArray<NSString *> *MTContextGroupKeys(void) { return @[@"delete", @"selection", @"paste", @"copy", @"typing", @"idle"]; }
NSString *MTContextTypeTitle(NSString *identifier) {
    NSDictionary *keys = @{@"text":@"CTX_TEXT", @"url":@"CTX_URL", @"image":@"CTX_IMAGE", @"number":@"CTX_NUMBER", @"address":@"CTX_ADDRESS", @"phone":@"CTX_PHONE", @"date":@"CTX_DATE", @"mixed":@"CTX_MIXED", @"chinese":@"CTX_CHINESE", @"fallback":@"CTX_FALLBACK"};
    NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.lindo.metis.prefs.keyboard"];
    NSString *key = keys[identifier] ?: identifier;
    return [bundle localizedStringForKey:key value:key table:nil];
}
BOOL MTContextActionAllowed(NSString *action, NSDictionary *preferences) {
    if (![action isKindOfClass:NSString.class] || !action.length) return NO;
    if ([@[@"url:open", @"url:search", @"ai:seed"] containsObject:action]) return YES;
    if (MTIsPanelSelector(action)) return MTPanelAllowed(preferences, action, MTPanelKeyboardKind);
    if ([action hasPrefix:MTPanelLinkSelectorPrefix]) return MTPanelActionDefinition(preferences, action) != nil;
    // Same catalog as canExecuteKeyboardPanelSelector:, without allocating UIKit on the classifier queue.
    Class generator = NSClassFromString(@"MTShortcutsGenerator");
    if (![generator respondsToSelector:@selector(isVisibleShortcutSelector:)]) return NO;
    BOOL (*visible)(id, SEL, id) = (void *)objc_msgSend;
    if (!visible(generator, @selector(isVisibleShortcutSelector:), action)) return NO;
    NSDictionary *dependencies = @{@"clipboardAction:":@"isMtInstalled", @"shellxScreenshotAction:":@"isShellXScreenshotAvailable", @"pulloverWakeAction:":@"isPullOverXInstalled"};
    NSString *dependency = dependencies[action];
    return !dependency || ((BOOL (*)(id, SEL))objc_msgSend)(generator, NSSelectorFromString(dependency));
}
@implementation MTContextType
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *result = [@{@"kind":self.kind, @"id":self.identifier, @"enabled":@(self.enabled), @"actions":self.actions ?: @[]} mutableCopy];
    if ([self.kind isEqual:@"js"]) { result[@"name"] = self.name ?: @""; result[@"source"] = self.source ?: @""; }
    return result;
}
@end

@interface MTContextGroupConfig ()
@property(nonatomic, copy, readwrite) NSDictionary *preferences;
@property(nonatomic, copy) NSDictionary<NSString *, NSArray<MTContextType *> *> *groups;
@end
static BOOL MTContextSourceHasValidSyntax(NSString *source) {
    JSGlobalContextRef context = JSGlobalContextCreate(NULL);
    NSString *wrapped = [NSString stringWithFormat:@"(function(){\n%@\n})", source];
    JSStringRef script = JSStringCreateWithCFString((__bridge CFStringRef)wrapped);
    BOOL valid = JSCheckScriptSyntax(context, script, NULL, 1, NULL);
    JSStringRelease(script); JSGlobalContextRelease(context); return valid;
}
@implementation MTContextGroupConfig
+ (NSArray *)defaultsForGroup:(NSString *)group {
    NSArray *ids = @[@"fallback"];
    if ([group isEqual:@"selection"]) ids = @[@"url", @"mixed", @"chinese", @"number", @"fallback"];
    if ([group isEqual:@"copy"]) ids = @[@"url", @"image", @"phone", @"date", @"number", @"text"];
    if ([group isEqual:@"paste"]) ids = @[@"url", @"address", @"number", @"image", @"text"];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *identifier in ids) {
        // Defaults only seed actions the catalog actually offers, so every
        // pre-filled slot can be re-added after the user deletes it. The
        // synthesized context actions (url:open / url:search / ai:seed) remain
        // executable for configurations that already reference them, but new
        // configurations start from catalog actions only.
        NSArray *actions = @[@"copyAction:", @"pasteAction:"];
        if ([group isEqual:@"delete"]) actions = @[@"undoAction:"];
        else if ([group isEqual:@"typing"]) actions = @[@"selectAllAction:", @"copyAction:", @"undoAction:"];
        else if ([group isEqual:@"idle"]) actions = @[];
        else if ([group isEqual:@"paste"]) actions = @[@"undoAction:", @"copyAction:"];
        else if ([group isEqual:@"copy"]) actions = @[@"pasteAction:", @"copyAction:"];
        if ([identifier isEqual:@"image"]) actions = @[@"pasteAction:", @"copyAction:"];
        [result addObject:@{@"kind":@"builtin", @"id":identifier, @"enabled":@YES, @"actions":actions}];
    }
    return result;
}
+ (NSDictionary *)migratePreferences:(NSDictionary *)preferences {
    NSDictionary *prefs = [preferences isKindOfClass:NSDictionary.class] ? preferences : @{};
    if ([prefs[kContextConfigVersionKey] respondsToSelector:@selector(integerValue)] && [prefs[kContextConfigVersionKey] integerValue] >= 2 && [prefs[kContextGroupTypesKey] isKindOfClass:NSDictionary.class]) return prefs;
    @try {
        NSMutableDictionary *result = [prefs mutableCopy], *groups = [NSMutableDictionary dictionary];
        NSDictionary *legacy = [prefs[kContextActionsKey] isKindOfClass:NSDictionary.class] ? prefs[kContextActionsKey] : @{};
        NSDictionary *reasonTypes = @{@"selection-url":@"url", @"selection-code":@"mixed", @"selection-phone":@"phone", @"selection-text":@"fallback", @"clipboard-url":@"url", @"clipboard-phone":@"phone", @"clipboard-text":@"text", @"paste-inserted":@"text"};
        for (NSString *group in MTContextGroupKeys()) {
            NSMutableArray *types = [NSMutableArray array];
            NSString *old = [group isEqual:@"copy"] ? @"clipboard" : ([group isEqual:@"typing"] ? @"input" : group);
            for (NSDictionary *entry in [self defaultsForGroup:group]) {
                NSMutableDictionary *type = [entry mutableCopy];
                id actions = legacy[old];
                for (NSString *reason in reasonTypes) if ([reasonTypes[reason] isEqual:type[@"id"]] && [reason hasPrefix:old] && legacy[reason]) actions = legacy[reason];
                if ([actions isKindOfClass:NSArray.class]) type[@"actions"] = actions;
                [types addObject:type];
            }
            groups[group] = types;
        }
        result[kContextGroupTypesKey] = groups; result[kContextConfigVersionKey] = @2;
        return result;
    } @catch (NSException *exception) { NSLog(@"[Metis][Context] migration failed: %@", exception.name); return prefs; }
}
+ (instancetype)configFromPreferences:(NSDictionary *)preferences {
    MTContextGroupConfig *config = [self new];
    config.preferences = [self migratePreferences:preferences];
    NSDictionary *stored = config.preferences[kContextGroupTypesKey];
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    for (NSString *group in MTContextGroupKeys()) {
        id raw = [stored isKindOfClass:NSDictionary.class] ? stored[group] : nil;
        NSArray *entries = [raw isKindOfClass:NSArray.class] ? raw : [self defaultsForGroup:group];
        NSMutableArray *types = [NSMutableArray array]; NSMutableSet *seen = [NSMutableSet set]; NSUInteger scripts = 0;
        NSArray *builtinIDs = @[@"text", @"url", @"image", @"number", @"address", @"phone", @"date", @"mixed", @"chinese", @"fallback"];
        for (id entry in entries) {
            if (![entry isKindOfClass:NSDictionary.class]) continue;
            NSString *kind = entry[@"kind"], *identifier = entry[@"id"];
            if (![@[@"builtin", @"js"] containsObject:kind ?: @""] || ![identifier isKindOfClass:NSString.class] || [identifier rangeOfString:@"^[A-Za-z0-9_-]{1,32}$" options:NSRegularExpressionSearch].location == NSNotFound || [seen containsObject:identifier]) { NSLog(@"[Metis][Context] invalid/duplicate type in %@", group); continue; }
            if ([kind isEqual:@"builtin"] && ![builtinIDs containsObject:identifier]) continue;
            if ([kind isEqual:@"js"] && ++scripts > 16) continue;
            [seen addObject:identifier];
            MTContextType *type = [MTContextType new]; type.kind = kind; type.identifier = identifier;
            type.name = [entry[@"name"] isKindOfClass:NSString.class] ? [entry[@"name"] substringToIndex:MIN((NSUInteger)128, [entry[@"name"] length])] : identifier;
            type.source = [entry[@"source"] isKindOfClass:NSString.class] ? entry[@"source"] : @"";
            type.enabled = ![entry[@"enabled"] isKindOfClass:NSNumber.class] || [entry[@"enabled"] boolValue];
            if ([kind isEqual:@"js"] && (!type.source.length || [type.source lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 8192 || !MTContextSourceHasValidSyntax(type.source))) {
                type.enabled = NO; NSLog(@"[Metis][Context] disabled invalid JS type %@/%@", group, identifier);
            }
            NSMutableArray *actions = [NSMutableArray array];
            for (id action in [entry[@"actions"] isKindOfClass:NSArray.class] ? entry[@"actions"] : @[]) {
                if (MTContextActionAllowed(action, config.preferences)) [actions addObject:action];
                if (actions.count == 8) break;
            }
            type.actions = actions; [types addObject:type];
        }
        groups[group] = types;
    }
    config.groups = groups; return config;
}
- (NSArray<MTContextType *> *)typesForGroup:(NSString *)group { return self.groups[MTContextCanonicalGroup(group)] ?: @[]; }
- (NSUInteger)slotsForGroup:(NSString *)group {
    NSDictionary *layout = MTBottomBarLayout(self.preferences); NSUInteger count = 0;
    NSArray *entries = [layout[@"left"] arrayByAddingObjectsFromArray:[layout[@"single"] boolValue] ? @[] : layout[@"right"]];
    for (NSDictionary *entry in entries) if ([entry[@"kind"] isEqual:@"context"] && ([entry[@"value"] isEqual:@"auto"] || [entry[@"value"] isEqual:MTContextCanonicalGroup(group)])) count++;
    return MIN((NSUInteger)8, count);
}
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    for (NSString *key in MTContextGroupKeys()) {
        NSMutableArray *types = [NSMutableArray array]; for (MTContextType *type in self.groups[key]) [types addObject:type.dictionaryRepresentation]; groups[key] = types;
    }
    return groups;
}
@end
