#pragma once
#import <Foundation/Foundation.h>

#define kFloatingShelfEnabledKey @"floatingappshelfBOOL"
#define kContextGroupsEnabledKey @"contextgroupsBOOL"
#define kContextSelectionGroupKey @"contextgroupselectionBOOL"
#define kContextClipboardGroupKey @"contextgroupclipboardBOOL"
#define kContextPasteGroupKey @"contextgrouppasteBOOL"
#define kContextInputGroupKey @"contextgroupinputBOOL"
// 剪贴板新鲜期 / 粘贴后新鲜期（秒），以及「算一次粘贴」的最少插入字数。
#define kContextClipboardFreshnessKey @"contextclipboardfreshness"
#define kContextPasteFreshnessKey @"contextpastefreshness"
#define kContextPasteMinLengthKey @"contextpasteminlength"
#define kBottomToolbarEnabledKey @"bottomtoolbarBOOL"
#define kContextIdleGroupKey @"contextgroupidleBOOL"
#define kContextPriorityKey @"contextgrouppriority"
#define kContextActionsKey @"contextgroupactions"
#define kContextDebounceKey @"contextdebounce"
#define kContextLockKey @"contextactionlock"
#define kContextSlotsKey @"contextslots"

static inline double MTContextNumber(NSDictionary *prefs, NSString *key, double fallback, double low, double high) {
    id value = prefs[key];
    if (![value isKindOfClass:NSNumber.class]) return fallback;
    double number = [value doubleValue];
    return number >= low && number <= high ? number : fallback;
}
static inline NSInteger MTContextSlots(NSDictionary *prefs) {
    return (NSInteger)MTContextNumber(prefs, kContextSlotsKey, 3, 1, 3);
}
static inline BOOL MTBottomToolbarEnabled(NSDictionary *prefs) {
    return [prefs[kBottomToolbarEnabledKey] isKindOfClass:NSNumber.class] && [prefs[kBottomToolbarEnabledKey] boolValue];
}
// The fixed buttons keep three reserved cells, even when the contextual group changes.
// 分母不再含「更多」格：固定 3 格 + 上下文 slots 格，左右两区等宽、单格同宽。
static inline double MTBottomFixedFraction(NSDictionary *prefs) {
    return 3.0 / (3.0 + MTContextSlots(prefs));
}
