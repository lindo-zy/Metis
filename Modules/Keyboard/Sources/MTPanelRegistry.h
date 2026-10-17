#pragma once
#import "MTKeyboardPanelPreferences.h"

#define kMTPanels @"panels"
#define kMTToolbarBindings @"toolbarpanelbindings"
#define MTPanelLinkSelectorPrefix @"__typex_link_action_"
#define MTPanelSelectorPrefix @"__typex_panel_"
#define MTPanelKeyboardKind @"keyboard"
#define MTPanelGestureKind @"gesture"

static inline NSString *MTPanelString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static inline BOOL MTPanelKindValid(id kind) { return [@[MTPanelKeyboardKind, MTPanelGestureKind] containsObject:kind ?: NSNull.null]; }
static inline NSString *MTPanelDefaultIconName(id kind) {
    return [kind isEqual:MTPanelKeyboardKind] ? @"keyboard" : @"hand.draw";
}
static inline NSString *MTPanelSelector(NSString *identifier) {
    return MTPanelString(identifier).length ? [MTPanelSelectorPrefix stringByAppendingString:identifier] : nil;
}
static inline BOOL MTIsPanelSelector(id selector) {
    return [selector isKindOfClass:NSString.class] && [selector hasPrefix:MTPanelSelectorPrefix] && [selector length] > MTPanelSelectorPrefix.length;
}
static inline NSArray<NSDictionary *> *MTPanelDefinitions(NSDictionary *preferences, NSString *kind) {
    id stored = preferences[kMTPanels];
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *panels = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id entry in stored) {
        if (![entry isKindOfClass:NSDictionary.class] || !MTPanelKindValid(entry[@"kind"])) continue;
        NSString *identifier = MTPanelString(entry[@"id"]);
        if (!identifier.length || identifier.length > 128 || [seen containsObject:identifier]) continue;
        [seen addObject:identifier];
        if (!kind || [entry[@"kind"] isEqual:kind]) [panels addObject:entry];
    }
    return panels;
}
static inline NSDictionary *MTPanelDefinition(NSDictionary *preferences, NSString *selector) {
    if (!MTIsPanelSelector(selector)) return nil;
    for (NSDictionary *panel in MTPanelDefinitions(preferences, nil))
        if ([MTPanelSelector(panel[@"id"]) isEqual:selector]) return panel;
    return nil;
}
// Display uses the type's icon; keep the stored definition intact for updates
// and deletion, including configurations with a legacy custom icon.
static inline NSDictionary *MTPanelDisplayDefinition(NSDictionary *preferences, NSString *selector) {
    NSDictionary *panel = MTPanelDefinition(preferences, selector);
    if (!panel) return nil;
    NSMutableDictionary *display = [panel mutableCopy];
    display[@"icon"] = MTPanelDefaultIconName(panel[@"kind"]);
    return display;
}
static inline BOOL MTPanelAllowed(NSDictionary *preferences, NSString *selector, NSString *kind) {
    return [MTPanelDefinition(preferences, selector)[@"kind"] isEqual:kind];
}
static inline NSDictionary *MTPanelActionDefinition(NSDictionary *preferences, NSString *selector) {
    if (![MTPanelString(selector) hasPrefix:MTPanelLinkSelectorPrefix] || MTPanelString(selector).length <= MTPanelLinkSelectorPrefix.length) return nil;
    id stored = preferences[@"linkactions"];
    if (![stored isKindOfClass:NSArray.class]) return nil;
    for (id entry in stored) if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return entry;
    return nil;
}
// Input-dependent custom actions remain selectable in gesture panels; execution
// must reject them with an error, never substitute text from another process.
static inline BOOL MTPanelCustomActionSelectable(NSDictionary *entry, NSString *kind) {
    if (![entry isKindOfClass:NSDictionary.class]) return NO;
    if ([kind isEqual:MTPanelKeyboardKind]) return YES;
    NSString *type = MTPanelString(entry[@"type"]);
    return !type.length || [@[@"url", @"urlscheme", @"openapp", @"shortcut", @"system"] containsObject:type];
}
static inline BOOL MTPanelItemAllowed(NSDictionary *preferences, NSString *selector, NSString *kind) {
    if (MTIsPanelSelector(selector)) return MTPanelAllowed(preferences, selector, kind);
    NSDictionary *entry = MTPanelActionDefinition(preferences, selector);
    if (entry) return MTPanelCustomActionSelectable(entry, kind);
    // Runtime additionally resolves built-in selectors against the action catalog.
    return [kind isEqual:MTPanelKeyboardKind] && [MTPanelString(selector) hasSuffix:@":"] && ![selector hasPrefix:@"__"];
}
static inline NSArray<NSDictionary *> *MTPanelItems(NSDictionary *preferences, NSString *selector) {
    NSDictionary *panel = MTPanelDefinition(preferences, selector);
    id stored = panel[@"items"];
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *items = [NSMutableArray array];
    for (id item in stored) {
        if (![item isKindOfClass:NSDictionary.class] || !MTPanelItemAllowed(preferences, item[@"selector"], panel[@"kind"])) continue;
        NSMutableDictionary *sanitized = [NSMutableDictionary dictionary];
        // Item icons always follow the referenced action or panel definition.
        for (NSString *field in @[@"selector", @"id", @"name"])
            if ([item[field] isKindOfClass:NSString.class]) sanitized[field] = item[field];
        [items addObject:sanitized];
    }
    return items;
}
static inline NSDictionary *MTPanelPreferences(NSDictionary *preferences, NSString *selector) {
    NSMutableDictionary *result = [preferences mutableCopy] ?: [NSMutableDictionary dictionary];
    id values = MTPanelDefinition(preferences, selector)[@"preferences"];
    if ([values isKindOfClass:NSDictionary.class])
        for (NSString *key in @[kMTPanelColumns, kMTPanelScale, kMTPanelDark, kMTPanelSystemTogglesVisible, kMTPanelSystemSlidersVisible])
            if (values[key]) result[key] = values[key];
    return result;
}
static inline void MTPanelUpdate(NSMutableDictionary *preferences, NSString *selector, NSDictionary *changes) {
    NSDictionary *original = MTPanelDefinition(preferences, selector);
    if (!original || !changes) return; // A stale editor cannot resurrect a deleted panel.
    NSMutableArray *panels = [preferences[kMTPanels] mutableCopy];
    NSUInteger index = [panels indexOfObject:original];
    if (index == NSNotFound) return;
    NSMutableDictionary *panel = [original mutableCopy];
    [panel addEntriesFromDictionary:changes];
    panels[index] = panel;
    preferences[kMTPanels] = panels;
}
static inline NSString *MTToolbarBindingSlot(NSString *configuration, NSString *direction) {
    if (![@[@"top", @"bottom"] containsObject:configuration] || ![@[@"left", @"right"] containsObject:direction]) return nil;
    return [configuration stringByAppendingFormat:@".%@", direction];
}
static inline NSString *MTToolbarAction(NSDictionary *preferences, NSString *configuration, NSString *direction) {
    id stored = preferences[kMTToolbarBindings];
    NSString *slot = MTToolbarBindingSlot(configuration, direction);
    NSString *selector = [stored isKindOfClass:NSDictionary.class] && slot ? MTPanelString(stored[slot]) : @"";
    return MTPanelItemAllowed(preferences, selector, MTPanelKeyboardKind) ? selector : nil;
}
static inline void MTPanelRemoveReferences(NSMutableDictionary *preferences, NSString *selector) {
    id stored = preferences[kMTToolbarBindings];
    if ([stored isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *bindings = [stored mutableCopy];
        for (NSString *slot in bindings.allKeys) if ([bindings[slot] isEqual:selector]) bindings[slot] = @"";
        preferences[kMTToolbarBindings] = bindings;
    }
    NSMutableArray *panels = [NSMutableArray array];
    for (NSDictionary *original in MTPanelDefinitions(preferences, nil)) {
        NSMutableDictionary *panel = [original mutableCopy];
        NSMutableArray *items = [NSMutableArray array];
        id storedItems = panel[@"items"];
        for (id item in [storedItems isKindOfClass:NSArray.class] ? storedItems : @[])
            if (![item isKindOfClass:NSDictionary.class] || ![item[@"selector"] isEqual:selector]) [items addObject:item];
        panel[@"items"] = items;
        [panels addObject:panel];
    }
    preferences[kMTPanels] = panels;
}
// Deterministic IDs make read-time migration consistent in Settings, apps and
// SpringBoard. Presence (even an empty/invalid registry) is the migration marker.
static inline NSDictionary *MTPanelMigratePreferences(NSDictionary *preferences) {
    if (![preferences isKindOfClass:NSDictionary.class] || preferences.count == 0 || preferences[kMTPanels]) return preferences;
    NSMutableDictionary *result = [preferences mutableCopy];
    NSMutableArray *panels = [NSMutableArray array];
    BOOL hasLegacy = NO;
    for (NSString *key in preferences) if ([key hasPrefix:@"keyboardpanel"] && ![key isEqual:kMTPanelTopEnabled] &&
        ![key isEqual:kMTPanelBottomEnabled] && ![key isEqual:kMTPanelDockSwipeEnabled] && ![key isEqual:kMTPanelGlobalEnabled]) hasLegacy = YES;
    NSDictionary *dock = [preferences[@"dockgesturebindings"] isKindOfClass:NSDictionary.class] ? preferences[@"dockgesturebindings"] : @{};
    NSDictionary *status = [preferences[@"statusbargesturebindings"] isKindOfClass:NSDictionary.class] ? preferences[@"statusbargesturebindings"] : @{};
    for (id selector in dock.allValues) if ([MTPanelString(selector) hasPrefix:@"__typex_dock_panel_"]) hasLegacy = YES;
    for (id binding in status.allValues) if ([binding isKindOfClass:NSDictionary.class] && [MTPanelString(binding[@"selector"]) hasPrefix:@"__typex_statusbar_panel_"]) hasLegacy = YES;
    if (hasLegacy) {
        NSUInteger number = 0;
        for (NSString *side in @[@"left", @"right", @"common"]) {
            number++;
            NSDictionary *profile = MTKeyboardPanelProfilePreferences(preferences, side);
            NSMutableDictionary *options = [NSMutableDictionary dictionary];
            for (NSString *key in @[kMTPanelColumns, kMTPanelScale, kMTPanelDark, kMTPanelSystemTogglesVisible, kMTPanelSystemSlidersVisible])
                if (profile[key]) options[key] = profile[key];
            for (NSString *kind in @[MTPanelKeyboardKind, MTPanelGestureKind]) {
                NSString *identifier = [NSString stringWithFormat:@"legacy-%@-%@", kind, side];
                [panels addObject:@{@"id": identifier, @"kind": kind,
                    @"name": [NSString stringWithFormat:@"%@ %lu", [kind isEqual:MTPanelKeyboardKind] ? @"键盘面板" : @"手势面板", (unsigned long)number],
                    @"icon": MTPanelDefaultIconName(kind), @"items": MTKeyboardPanelItems(preferences, side), @"preferences": options}];
            }
        }
        NSMutableDictionary *bindings = [dock mutableCopy];
        for (NSString *direction in @[@"up", @"left", @"right"]) {
            NSString *old = MTPanelString(bindings[direction]);
            if (!bindings[direction] && [direction isEqual:@"up"]) old = @"__typex_dock_panel_common";
            for (NSString *side in @[@"left", @"right", @"common"])
                if ([old isEqual:[@"__typex_dock_panel_" stringByAppendingString:side]]) bindings[direction] = MTPanelSelector([@"legacy-gesture-" stringByAppendingString:side]);
        }
        result[@"dockgesturebindings"] = bindings;
        bindings = [status mutableCopy];
        for (NSString *slot in bindings.allKeys) {
            if (![bindings[slot] isKindOfClass:NSDictionary.class]) continue;
            NSMutableDictionary *binding = [bindings[slot] mutableCopy];
            for (NSString *side in @[@"left", @"right", @"common"])
                if ([binding[@"selector"] isEqual:[@"__typex_statusbar_panel_" stringByAppendingString:side]]) binding[@"selector"] = MTPanelSelector([@"legacy-gesture-" stringByAppendingString:side]);
            bindings[slot] = binding;
        }
        result[@"statusbargesturebindings"] = bindings;
    }
    result[kMTPanels] = panels;
    // No implicit toolbar actions: a new binding must be explicitly selected.
    if (!result[kMTToolbarBindings]) result[kMTToolbarBindings] = @{};
    return result;
}
