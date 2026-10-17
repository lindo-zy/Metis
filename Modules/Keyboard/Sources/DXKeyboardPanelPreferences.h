#import <Foundation/Foundation.h>
#include <math.h>

#define kDXPanelTopEnabled @"keyboardpaneltopBOOL"
#define kDXPanelBottomEnabled @"keyboardpanelbottomBOOL"
#define kDXPanelGlobalEnabled @"keyboardpanelglobalBOOL"
#define kDXPanelDockSwipeEnabled @"keyboardpaneldockswipeBOOL"
#define kDXPanelSystemTogglesVisible @"keyboardpanelsystemtogglesBOOL"
#define kDXPanelSystemSlidersVisible @"keyboardpanelsystemslidersBOOL"
#define kDXPanelColumns @"keyboardpanelcolumns"
#define kDXPanelScale @"keyboardpanelscale"
#define kDXPanelDark @"keyboardpaneldarkBOOL"
#define kDXPanelLeftItems @"keyboardpanelleftitems"
#define kDXPanelRightItems @"keyboardpanelrightitems"
#define kDXPanelCommonItems @"keyboardpanelcommonitems"

// Legacy profile helpers are read-only inputs for registry migration.
// New panels persist independent options inside their definitions.
static inline NSString *DXKeyboardPanelProfileKey(NSString *key, NSString *side) {
    if (![@[@"left", @"right", @"common"] containsObject:side] || ![key hasPrefix:@"keyboardpanel"]) return nil;
    return [@"keyboardpanel" stringByAppendingFormat:@"%@%@", side, [key substringFromIndex:13]];
}

static inline NSDictionary *DXKeyboardPanelProfilePreferences(NSDictionary *preferences, NSString *side) {
    NSMutableDictionary *profile = [preferences isKindOfClass:NSDictionary.class] ? [preferences mutableCopy] : [NSMutableDictionary dictionary];
    for (NSString *key in @[kDXPanelSystemTogglesVisible, kDXPanelSystemSlidersVisible, kDXPanelColumns, kDXPanelScale, kDXPanelDark]) {
        NSString *scopedKey = DXKeyboardPanelProfileKey(key, side);
        id value = scopedKey ? profile[scopedKey] : nil;
        if (value) profile[key] = value;
    }
    return profile;
}

static inline NSString *DXKeyboardPanelItemsKey(NSString *side) {
    if ([side isEqualToString:@"right"]) return kDXPanelRightItems;
    if ([side isEqualToString:@"common"]) return kDXPanelCommonItems;
    return kDXPanelLeftItems;
}

static inline NSArray<NSDictionary *> *DXKeyboardPanelItems(NSDictionary *preferences, NSString *side) {
    if (![preferences isKindOfClass:NSDictionary.class]) return @[];
    id stored = preferences[DXKeyboardPanelItemsKey(side)];
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *items = [NSMutableArray array];
    for (id entry in stored) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *selector = entry[@"selector"];
        if (![selector isKindOfClass:NSString.class] || !selector.length) continue;
        NSMutableDictionary *item = [@{@"selector": selector} mutableCopy];
        for (NSString *field in @[@"id", @"name", @"icon"]) {
            if ([entry[field] isKindOfClass:NSString.class]) item[field] = entry[field];
        }
        [items addObject:item];
    }
    return items;
}

static inline double DXKeyboardPanelNumber(NSDictionary *preferences, NSString *key,
                                         double fallback, double minimum, double maximum) {
    id value = preferences[key];
    double number = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    if (!isfinite(number)) number = fallback;
    return MIN(maximum, MAX(minimum, number));
}

static inline BOOL DXKeyboardPanelBool(NSDictionary *preferences, NSString *key, BOOL fallback) {
    id value = preferences[key];
    return value ? ([value isKindOfClass:NSNumber.class] && [value boolValue]) : fallback;
}
