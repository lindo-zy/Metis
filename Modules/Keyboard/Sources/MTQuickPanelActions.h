#import <Foundation/Foundation.h>
#import "MTGlobalPanelPolicy.h"

#define kKbdLauncherActionsKey @"kbdlauncheractions"

// Four stable slots store selectors, never copies of custom action definitions.
static inline NSArray<NSString *> *MTQuickPanelActionSlots(NSDictionary *preferences) {
    id raw = preferences[kKbdLauncherActionsKey];
    NSMutableArray *slots = [NSMutableArray array];
    for (NSUInteger i = 0; i < 4; i++) {
        id value = [raw isKindOfClass:NSArray.class] && i < [raw count] ? raw[i] : nil;
        [slots addObject:[value isKindOfClass:NSString.class] ? value : @""];
    }
    return slots;
}
static inline NSDictionary *MTQuickPanelActionDefinition(NSArray *definitions, NSString *selector) {
    if (!selector.length || ![definitions isKindOfClass:NSArray.class]) return nil;
    for (id entry in definitions) if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return entry;
    return nil;
}
static inline NSArray<NSDictionary *> *MTQuickPanelResolvedActions(NSDictionary *preferences, NSArray *definitions) {
    NSMutableArray *actions = [NSMutableArray array];
    for (NSString *selector in MTQuickPanelActionSlots(preferences)) {
        NSDictionary *entry = MTQuickPanelActionDefinition(definitions, selector);
        [actions addObject:MTGlobalCustomActionSupported(entry) ? entry : @{}];
    }
    return actions;
}
static inline void MTQuickPanelRemoveActionReferences(NSMutableDictionary *preferences, NSString *selector) {
    if (!preferences[kKbdLauncherActionsKey] || !selector.length) return;
    NSMutableArray *slots = [MTQuickPanelActionSlots(preferences) mutableCopy];
    for (NSUInteger i = 0; i < slots.count; i++) if ([slots[i] isEqual:selector]) slots[i] = @"";
    preferences[kKbdLauncherActionsKey] = slots;
}
