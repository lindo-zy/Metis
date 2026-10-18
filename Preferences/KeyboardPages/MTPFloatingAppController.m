#import "MTPFloatingAppController.h"
#import "MTPPanelSliderCell.h"
#import "MTPPanelSegmentCell.h"
#import "MTPLauncherAppsController.h"
#import "MTHelper.h"
#import "common.h"
#import <Preferences/PSSpecifier.h>

static NSString *MTFloatingLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}

// 悬浮打开应用小窗的全局设置。比例与位置键由 MTFloatingCardMaxScaleFromPreferences /
// MTFloatingCardPositionFromPreferences 消费（SpringBoard 托管卡片读取同一份快照）。
@implementation MTPFloatingAppController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTFloatingLocalized(@"FLOATING_APP_SETTINGS");
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:MTFloatingLocalized(@"FLOATING_APP_SIZE_GROUP")];
    [group setProperty:MTFloatingLocalized(@"FLOATING_APP_SCALE_FOOTER") forKey:@"footerText"];
    PSSpecifier *scale = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"FLOATING_APP_MAX_SCALE") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSStaticTextCell edit:nil];
    [scale setProperty:kFloatingCardMaxScaleKey forKey:@"key"];
    [scale setProperty:@72 forKey:@"default"];
    [scale setProperty:MTPPanelSliderCell.class forKey:@"cellClass"];
    [scale setProperty:@30 forKey:@"min"];
    [scale setProperty:@100 forKey:@"max"];
    [scale setProperty:@YES forKey:@"showValue"];
    PSSpecifier *positionGroup = [PSSpecifier groupSpecifierWithName:MTFloatingLocalized(@"FLOATING_APP_POSITION_GROUP")];
    [positionGroup setProperty:MTFloatingLocalized(@"FLOATING_APP_POSITION_FOOTER") forKey:@"footerText"];
    PSSpecifier *position = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"FLOATING_APP_POSITION") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSStaticTextCell edit:nil];
    [position setProperty:kFloatingCardPositionKey forKey:@"key"];
    [position setProperty:@1 forKey:@"default"];
    [position setProperty:MTPPanelSegmentCell.class forKey:@"cellClass"];
    [position setProperty:@[MTFloatingLocalized(@"FLOATING_APP_POSITION_LEFT"), MTFloatingLocalized(@"FLOATING_APP_POSITION_CENTER"),
        MTFloatingLocalized(@"FLOATING_APP_POSITION_RIGHT")] forKey:@"titles"];
    PSSpecifier *shelfGroup = [PSSpecifier groupSpecifierWithName:MTFloatingLocalized(@"FLOATING_SHELF_GROUP")];
    [shelfGroup setProperty:MTFloatingLocalized(@"FLOATING_SHELF_FOOTER") forKey:@"footerText"];
    PSSpecifier *shelf = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"FLOATING_SHELF_SWITCH") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [shelf setProperty:kFloatingShelfEnabledKey forKey:@"key"]; [shelf setProperty:@NO forKey:@"default"];
    PSSpecifier *handleGroup = [PSSpecifier groupSpecifierWithName:MTFloatingLocalized(@"FLOATING_HANDLE_GROUP")];
    [handleGroup setProperty:MTFloatingLocalized(@"FLOATING_HANDLE_FOOTER") forKey:@"footerText"];
    PSSpecifier *handleSwitch = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"FLOATING_HANDLE_SWITCH") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [handleSwitch setProperty:kKbdHandleEnabledKey forKey:@"key"]; [handleSwitch setProperty:@NO forKey:@"default"];
    PSSpecifier *handlePosition = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"FLOATING_HANDLE_POSITION") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSStaticTextCell edit:nil];
    [handlePosition setProperty:kKbdHandlePositionKey forKey:@"key"];
    [handlePosition setProperty:@0 forKey:@"default"];
    [handlePosition setProperty:MTPPanelSegmentCell.class forKey:@"cellClass"];
    [handlePosition setProperty:@[MTFloatingLocalized(@"FLOATING_APP_POSITION_LEFT"), MTFloatingLocalized(@"FLOATING_APP_POSITION_RIGHT")] forKey:@"titles"];
    PSSpecifier *autoHideSwitch = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"FLOATING_HANDLE_AUTO_HIDE") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [autoHideSwitch setProperty:kKbdHandleAutoHideKey forKey:@"key"]; [autoHideSwitch setProperty:@NO forKey:@"default"];
    PSSpecifier *autoHideSeconds = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"FLOATING_HANDLE_AUTO_HIDE_SECONDS") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSStaticTextCell edit:nil];
    [autoHideSeconds setProperty:kKbdHandleAutoHideSecondsKey forKey:@"key"];
    [autoHideSeconds setProperty:@(kKbdHandleAutoHideSecondsDefault) forKey:@"default"];
    [autoHideSeconds setProperty:MTPPanelSliderCell.class forKey:@"cellClass"];
    [autoHideSeconds setProperty:@(kKbdHandleAutoHideSecondsMinimum) forKey:@"min"];
    [autoHideSeconds setProperty:@(kKbdHandleAutoHideSecondsMaximum) forKey:@"max"];
    // 0.5 秒步进 + 秒值格式串由 MTPPanelSliderCell 的通用 step/valueFormat 路径消费。
    [autoHideSeconds setProperty:@(0.5) forKey:@"step"];
    [autoHideSeconds setProperty:MTFloatingLocalized(@"FLOATING_HANDLE_AUTO_HIDE_FORMAT") forKey:@"valueFormat"];
    PSSpecifier *quickGroup = [PSSpecifier groupSpecifierWithName:MTFloatingLocalized(@"QUICK_TITLE")];
    [quickGroup setProperty:MTFloatingLocalized(@"QUICK_SETTINGS_FOOTER") forKey:@"footerText"];
    PSSpecifier *quick = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"QUICK_SWITCH") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [quick setProperty:kKbdQuickLauncherKey forKey:@"key"]; [quick setProperty:@NO forKey:@"default"];
    PSSpecifier *manage = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"QUICK_MANAGE") target:self
        set:nil get:nil detail:MTPLauncherAppsController.class cell:PSLinkCell edit:nil];
    _specifiers = [@[shelfGroup, shelf, group, scale, positionGroup, position,
        handleGroup, handleSwitch, handlePosition, autoHideSwitch, autoHideSeconds, quickGroup, quick, manage] mutableCopy];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *preferences = [MTPrefsManager.sharedInstance readPrefs];
    id value = preferences[[specifier propertyForKey:@"key"]];
    return [value respondsToSelector:@selector(floatValue)] ? value : [specifier propertyForKey:@"default"];
}
// 与 MTPKeyboardPanelController 相同：滑杆与分段单元都是自绘 80pt 行高。
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    Class cellClass = [[self specifierAtIndexPath:path] propertyForKey:@"cellClass"];
    if (cellClass == MTPPanelSliderCell.class || cellClass == MTPPanelSegmentCell.class) return 80;
    return [super tableView:table heightForRowAtIndexPath:path];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if (![value isKindOfClass:NSNumber.class]) return;
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqual:kFloatingShelfEnabledKey] || [key isEqual:kKbdHandleEnabledKey] ||
        [key isEqual:kKbdHandleAutoHideKey] || [key isEqual:kKbdQuickLauncherKey]) {
        [MTPrefsManager.sharedInstance setValue:@([value boolValue]) forKey:key]; return;
    }
    if ([key isEqual:kKbdHandleAutoHideSecondsKey]) {
        // 与滑杆 0.5 秒步进一致；越界值夹回读取侧同款范围，写快照即合法值。
        double seconds = [value doubleValue];
        if (!isfinite(seconds)) seconds = kKbdHandleAutoHideSecondsDefault;
        seconds = lround(seconds * 2) / 2.0;
        [MTPrefsManager.sharedInstance setValue:@(MIN(MAX(seconds, kKbdHandleAutoHideSecondsMinimum),
            kKbdHandleAutoHideSecondsMaximum)) forKey:key];
        return;
    }
    NSInteger stored;
    if ([key isEqual:kFloatingCardPositionKey]) {
        stored = MIN(2, MAX(0, lround([value doubleValue])));
    } else if ([key isEqual:kKbdHandlePositionKey]) {
        stored = MIN(1, MAX(0, lround([value doubleValue])));
    } else {
        // 与滑杆 5% 步进一致；越界值夹回，避免写进快照后触发读取侧缺省回退。
        stored = MIN(100, MAX(30, lround([value doubleValue] / 5) * 5));
    }
    [MTPrefsManager.sharedInstance setValue:@(stored) forKey:key];
}
@end
