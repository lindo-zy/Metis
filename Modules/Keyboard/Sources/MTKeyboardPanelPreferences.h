#import <Foundation/Foundation.h>
#include <math.h>

#define kMTPanelTopEnabled @"keyboardpaneltopBOOL"
#define kMTPanelBottomEnabled @"keyboardpanelbottomBOOL"
// 手势面板恒定启用，此键只作旧配置迁移与读取兼容标记，运行时不再作为开关。
#define kMTPanelGlobalEnabled @"keyboardpanelglobalBOOL"
#define kMTPanelDockSwipeEnabled @"keyboardpaneldockswipeBOOL"
#define kMTPanelSystemTogglesVisible @"keyboardpanelsystemtogglesBOOL"
#define kMTPanelSystemSlidersVisible @"keyboardpanelsystemslidersBOOL"
#define kMTPanelColumns @"keyboardpanelcolumns"
#define kMTPanelScale @"keyboardpanelscale"
#define kMTPanelLeftItems @"keyboardpanelleftitems"
#define kMTPanelRightItems @"keyboardpanelrightitems"
#define kMTPanelCommonItems @"keyboardpanelcommonitems"

// Legacy profile helpers are read-only inputs for registry migration.
// New panels persist independent options inside their definitions.
static inline NSString *MTKeyboardPanelProfileKey(NSString *key, NSString *side) {
    if (![@[@"left", @"right", @"common"] containsObject:side] || ![key hasPrefix:@"keyboardpanel"]) return nil;
    return [@"keyboardpanel" stringByAppendingFormat:@"%@%@", side, [key substringFromIndex:13]];
}

static inline NSDictionary *MTKeyboardPanelProfilePreferences(NSDictionary *preferences, NSString *side) {
    NSMutableDictionary *profile = [preferences isKindOfClass:NSDictionary.class] ? [preferences mutableCopy] : [NSMutableDictionary dictionary];
    for (NSString *key in @[kMTPanelSystemTogglesVisible, kMTPanelSystemSlidersVisible, kMTPanelColumns, kMTPanelScale]) {
        NSString *scopedKey = MTKeyboardPanelProfileKey(key, side);
        id value = scopedKey ? profile[scopedKey] : nil;
        if (value) profile[key] = value;
    }
    return profile;
}

static inline NSString *MTKeyboardPanelItemsKey(NSString *side) {
    if ([side isEqualToString:@"right"]) return kMTPanelRightItems;
    if ([side isEqualToString:@"common"]) return kMTPanelCommonItems;
    return kMTPanelLeftItems;
}

static inline NSArray<NSDictionary *> *MTKeyboardPanelItems(NSDictionary *preferences, NSString *side) {
    if (![preferences isKindOfClass:NSDictionary.class]) return @[];
    id stored = preferences[MTKeyboardPanelItemsKey(side)];
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

static inline double MTKeyboardPanelNumber(NSDictionary *preferences, NSString *key,
                                         double fallback, double minimum, double maximum) {
    id value = preferences[key];
    double number = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    if (!isfinite(number)) number = fallback;
    return MIN(maximum, MAX(minimum, number));
}

static inline BOOL MTKeyboardPanelBool(NSDictionary *preferences, NSString *key, BOOL fallback) {
    id value = preferences[key];
    return value ? ([value isKindOfClass:NSNumber.class] && [value boolValue]) : fallback;
}
