#import "MTClipboardActionCreation.h"
#import "MTSharedResourceStore.h"
#import "MTPrefsManager.h"
#import "MTPActionGroups.h"
#import "MTPreferenceKeys.h"
#import "common.h"

// The global library is owned by the legacy view: appending the definition to
// kLinkActionskey and writing through MTPrefsManager lets the bridge commit it
// to the shared resource store, which is also what makes it visible to the
// keyboard's own pickers.
BOOL MTClipboardPersistCustomActionDefinition(NSDictionary *definition) {
    if (![definition isKindOfClass:NSDictionary.class]) return NO;
    NSMutableDictionary *prefs = [[[MTPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSArray *stored = [prefs[kLinkActionskey] isKindOfClass:NSArray.class] ? prefs[kLinkActionskey] : @[];
    NSMutableArray *definitions = [NSMutableArray array];
    for (id raw in stored) {
        NSMutableDictionary *entry = [raw isKindOfClass:NSDictionary.class] ? [raw mutableCopy] : [NSMutableDictionary dictionary];
        if ([entry[@"selector"] isEqual:definition[@"selector"]]) continue;
        [definitions addObject:entry];
    }
    [definitions addObject:definition];
    prefs[kLinkActionskey] = definitions;

    NSString *group = MTActionGroupNormalizedName(definition[kCustomActionGroupKey]);
    if (group.length) {
        NSArray *storedGroups = [prefs[kLinkActionGroupsKey] isKindOfClass:NSArray.class] ? prefs[kLinkActionGroupsKey] : @[];
        NSMutableArray *groups = [storedGroups mutableCopy];
        if (![groups containsObject:group]) [groups addObject:group];
        prefs[kLinkActionGroupsKey] = groups;
    }
    [[MTPrefsManager sharedInstance] writePrefs:prefs];
    return YES;
}

// The bridge derives the store UUID deterministically from the legacy
// selector, so the freshly committed action is matched through legacyRef.
NSString *MTClipboardStoredActionIDForSelector(NSString *selector) {
    if (selector.length == 0) return nil;
    NSDictionary *snapshot = [MTSharedResourceStore readSnapshot];
    for (NSDictionary *action in snapshot[@"actions"]) {
        NSDictionary *legacyRef = action[@"legacyRef"];
        if ([legacyRef isKindOfClass:NSDictionary.class] && [legacyRef[@"selector"] isEqual:selector]) return action[@"id"];
    }
    return nil;
}
