#pragma once
#import "common.h"
#import "MTHelper.h"
#import "MTShortcutsGenerator.h"
#import "MTPanelRegistry.h"

static inline NSArray<NSDictionary *> *MTPPanelBuiltInActions(void) {
    MTShortcutsGenerator *generator = MTShortcutsGenerator.sharedInstance;
    NSArray *selectors = generator.selectorNames, *icons = [generator imageNameArrayForiOS:1];
    NSMutableArray *actions = [NSMutableArray array];
    for (NSUInteger i = 0; i < selectors.count; i++) {
        NSString *selector = selectors[i];
        if (![MTShortcutsGenerator isVisibleShortcutSelector:selector]) continue;
        if ([selector isEqual:@"shellxScreenshotAction:"] && ![MTShortcutsGenerator isShellXScreenshotAvailable]) continue;
        if ([selector isEqual:@"clipboardAction:"] && ![MTShortcutsGenerator isMtInstalled]) continue;
        // 全屏截图依赖 SpringBoard 侧的 MetisCapture：未安装时通知无人接收，不进候选列表。
        if ([selector isEqual:@"captureFullScreenshotAction:"] && ![MTShortcutsGenerator isCaptureScreenshotAvailable]) continue;
        if ([selector isEqual:@"pulloverWakeAction:"] && ![MTShortcutsGenerator isPullOverXInstalled]) continue;
        NSString *name = [MTHelper localizedStringForActionNamed:selector shortName:NO bundle:[NSBundle bundleWithPath:bundlePath]];
        NSString *icon = i < icons.count ? icons[i] : @"square.grid.2x2";
        [actions addObject:@{@"selector": selector, @"label": name ?: selector, @"name": name ?: selector, @"icon": icon, @"images12": icon, @"images13": icon}];
    }
    return actions;
}
static inline NSDictionary *MTPPanelDisplayDefinition(NSDictionary *preferences, NSString *selector) {
    NSDictionary *entry = MTPanelDisplayDefinition(preferences, selector) ?: MTPanelActionDefinition(preferences, selector);
    if (entry) return entry;
    for (NSDictionary *action in MTPPanelBuiltInActions()) if ([action[@"selector"] isEqual:selector]) return action;
    return nil;
}
