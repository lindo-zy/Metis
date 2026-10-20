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
    PSSpecifier *quickGroup = [PSSpecifier groupSpecifierWithName:MTFloatingLocalized(@"QUICK_TITLE")];
    [quickGroup setProperty:MTFloatingLocalized(@"QUICK_SETTINGS_FOOTER") forKey:@"footerText"];
    PSSpecifier *launcherSide = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"QUICK_SIDE") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSStaticTextCell edit:nil];
    [launcherSide setProperty:kKbdLauncherSideKey forKey:@"key"];
    [launcherSide setProperty:@1 forKey:@"default"];
    [launcherSide setProperty:MTPPanelSegmentCell.class forKey:@"cellClass"];
    [launcherSide setProperty:@[MTFloatingLocalized(@"FLOATING_APP_POSITION_LEFT"), MTFloatingLocalized(@"FLOATING_APP_POSITION_RIGHT")]
        forKey:@"titles"];
    // 面板大小：80%~100% 等比缩放，5% 步进（读取侧同样夹回该范围）。
    PSSpecifier *launcherScale = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"QUICK_SIZE") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSStaticTextCell edit:nil];
    [launcherScale setProperty:kKbdLauncherScaleKey forKey:@"key"];
    [launcherScale setProperty:@(kKbdLauncherScaleDefault) forKey:@"default"];
    [launcherScale setProperty:MTPPanelSliderCell.class forKey:@"cellClass"];
    [launcherScale setProperty:@(kKbdLauncherScaleMinimum) forKey:@"min"];
    [launcherScale setProperty:@(kKbdLauncherScaleMaximum) forKey:@"max"];
    [launcherScale setProperty:@5 forKey:@"step"];
    // 拖动摆放后的复位入口：清掉归一化摆放位，回到 kbdlauncherside 的贴边底对齐。
    PSSpecifier *launcherReset = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"QUICK_RESET") target:self
        set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    launcherReset->action = @selector(resetLauncherPosition:);
    PSSpecifier *manage = [PSSpecifier preferenceSpecifierNamed:MTFloatingLocalized(@"QUICK_MANAGE") target:self
        set:nil get:nil detail:MTPLauncherAppsController.class cell:PSLinkCell edit:nil];
    manage.identifier = @"quick-launcher-apps";
    _specifiers = [@[group, scale, positionGroup, position,
        quickGroup, launcherSide, launcherScale, launcherReset, manage] mutableCopy];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *preferences = [MTPrefsManager.sharedInstance readPrefs];
    if ([[specifier propertyForKey:@"key"] isEqual:kKbdLauncherScaleKey]) {
        return @(MTKbdLauncherScaleFromPreferences(preferences));
    }
    id value = preferences[[specifier propertyForKey:@"key"]];
    return [value respondsToSelector:@selector(floatValue)] ? value : [specifier propertyForKey:@"default"];
}
// 与 MTPKeyboardPanelController 相同：滑杆与分段单元都是自绘 80pt 行高。
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    Class cellClass = [[self specifierAtIndexPath:path] propertyForKey:@"cellClass"];
    if (cellClass == MTPPanelSliderCell.class || cellClass == MTPPanelSegmentCell.class) return 80;
    return [super tableView:table heightForRowAtIndexPath:path];
}
// 只写摆放标记与坐标；SpringBoard 侧收到 prefschanged 后按「未摆放」重排。
- (void)resetLauncherPosition:(__unused PSSpecifier *)specifier {
    [MTPrefsManager.sharedInstance setValue:@NO forKey:kKbdLauncherPlacedKey];
    [MTPrefsManager.sharedInstance setValue:@0.5 forKey:kKbdLauncherOriginXKey];
    [MTPrefsManager.sharedInstance setValue:@0.5 forKey:kKbdLauncherOriginYKey];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if (![value isKindOfClass:NSNumber.class]) return;
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqual:kFloatingShelfEnabledKey]) {
        [MTPrefsManager.sharedInstance setValue:@([value boolValue]) forKey:key]; return;
    }
    if ([key isEqual:kKbdLauncherScaleKey]) {
        // 面板大小：与滑杆 5% 步进一致；越界值夹回 80~100，避免写快照后触发读取侧缺省回退。
        double scale = [value doubleValue];
        if (!isfinite(scale)) scale = kKbdLauncherScaleDefault;
        scale = lround(scale / 5) * 5;
        [MTPrefsManager.sharedInstance setValue:@(MIN(MAX(scale, kKbdLauncherScaleMinimum),
            kKbdLauncherScaleMaximum)) forKey:key];
        return;
    }
    NSInteger stored;
    if ([key isEqual:kFloatingCardPositionKey]) {
        stored = MIN(2, MAX(0, lround([value doubleValue])));
    } else if ([key isEqual:kKbdLauncherSideKey]) {
        stored = MIN(1, MAX(0, lround([value doubleValue])));
    } else {
        // 与滑杆 5% 步进一致；越界值夹回，避免写进快照后触发读取侧缺省回退。
        stored = MIN(100, MAX(30, lround([value doubleValue] / 5) * 5));
    }
    [MTPrefsManager.sharedInstance setValue:@(stored) forKey:key];
}
@end
