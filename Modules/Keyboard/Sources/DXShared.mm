#import "DXShared.h"
#import "DXPanelRegistry.h"

BOOL preferencesBool(NSString* key, BOOL fallback) {
    NSNumber* value;
    if (prefs) value = prefs[key];
    return value ? [value boolValue] : fallback;
}

float preferencesFloat(NSString* key, float fallback) {
    NSNumber* value;
    if (prefs) value = prefs[key];
    return value ? [value floatValue] : fallback;
}

int preferencesInt(NSString* key, int fallback) {
    NSNumber* value;
    if (prefs) value = prefs[key];
    return value ? [value intValue] : fallback;
}

NSDictionary *preferencesLinkActionForSelector(NSString *selector) {
    if (!DXIsLinkActionSelector(selector)) return nil;
    id stored = prefs[kLinkActionskey];
    if (![stored isKindOfClass:[NSArray class]]) return nil;
    for (NSDictionary *entry in (NSArray *)stored) {
        if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"selector"] isEqual:selector]) {
            return entry;
        }
    }
    return nil;
}

BOOL preferencesIsConfiguredActionSelector(NSString *selector) {
    return DXPanelAllowed(prefs, selector, DXPanelKeyboardKind) || [DXShortcutsGenerator isVisibleShortcutSelector:selector] ||
           preferencesLinkActionForSelector(selector) != nil;
}

NSString *preferencesSelectorForIdentifierScoped(NSString* identifier, int selectorNum, int gestureType, NSString *fallback, NSString *configuration) {
    //0-long press, 1-swipe up, 2-swipe down, 3-swipe left, 4-swipe right
    NSString *k = DXCustomActionsKeyForGesture(gestureType, configuration);
    
    NSString *selector = fallback;
    if (selectorNum == 1 && [prefs[k] isKindOfClass:[NSArray class]]) {
        for (NSDictionary *entry in prefs[k]) {
            if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"identifier"] isEqual:identifier]) continue;

            // Old two-action preferences stored the action that survives the UI
            // simplification as selector2.  Prefer it whenever the legacy key is
            // present (including an intentionally empty value).
            id storedSelector = entry[@"selector2"] ?: entry[@"selector"];
            if ([storedSelector isKindOfClass:[NSString class]]) selector = storedSelector;
            break;
        }
    }
    // Reject unknown selectors while still allowing supported legacy actions
    // that are intentionally hidden from the current picker.
    return (DXPanelAllowed(prefs, selector, DXPanelKeyboardKind) || [DXShortcutsGenerator isAvailableShortcutSelector:selector] ||
            preferencesLinkActionForSelector(selector) != nil) ? selector : fallback;
}

NSString *preferencesSelectorForIdentifier(NSString* identifier, int selectorNum, int gestureType, NSString *fallback) {
    return preferencesSelectorForIdentifierScoped(identifier, selectorNum, gestureType, fallback, @"bottom");
}

// Validate resolved gesture lists before installing recognizers or dispatching.
NSArray<NSString *> *preferencesGestureActionSelectors(NSString *identifier, int gestureType, NSString *configuration) {
    NSMutableArray<NSString *> *selectors = [NSMutableArray array];
    for (NSString *selector in DXGestureActionSelectors(prefs, identifier, gestureType, configuration)) {
        if (preferencesIsConfiguredActionSelector(selector)) [selectors addObject:selector];
    }
    return selectors;
}
