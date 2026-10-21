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
#define kContextGroupTypesKey @"contextgrouptypes"
#define kContextConfigVersionKey @"contextconfigversion"
#define kContextDeleteGroupKey @"contextgroupdeleteBOOL"

static inline double MTContextNumber(NSDictionary *prefs, NSString *key, double fallback, double low, double high) {
    id value = prefs[key];
    if (![value isKindOfClass:NSNumber.class]) return fallback;
    double number = [value doubleValue];
    return number >= low && number <= high ? number : fallback;
}
static inline NSInteger MTContextSlots(NSDictionary *prefs) {
    return (NSInteger)MTContextNumber(prefs, kContextSlotsKey, 3, 1, 8);
}
/// 悬浮底栏总开关已在设置页移除，底栏恒开：保留函数以免改动所有调用点，
/// 任何偏好组合都不能再关掉底栏（动作组占用的是底栏预留区，关掉等于整条链路停摆）。
static inline BOOL MTBottomToolbarEnabled(NSDictionary *prefs) {
    (void)prefs;
    return YES;
}
// The fixed buttons keep three reserved cells, even when the contextual group changes.
// 分母不再含「更多」格：固定 3 格 + 上下文 slots 格，左右两区等宽、单格同宽。
static inline double MTBottomFixedFraction(NSDictionary *prefs) {
    return 3.0 / (3.0 + MTContextSlots(prefs));
}
