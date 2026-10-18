#import "MTPrefsOtherController.h"
#import "MTPrefsSubbundleLoader.h"
#import "MTLog.h"

// 细项键沿用键盘细节域（com.lindo.metis.keyboard）：迁分类不改键名与
// PostNotification，运行端零改动（02 §6：原有具体功能开关仍按功能语义保留）。
static NSString *const MTOtherKeyboardDomain = @"com.lindo.metis.keyboard";
static NSString *const MTOtherPrefsChanged = @"com.lindo.metis.keyboard/prefschanged";

@implementation MTPrefsOtherController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"其他";
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *gestureGroup = [PSSpecifier groupSpecifierWithName:@"全局手势"];
        [gestureGroup setProperty:@"在任意界面触发；动作与面板在全局分类中定义。" forKey:@"footerText"];
        [specs addObject:gestureGroup];
        [specs addObject:[self mtSubbundleLinkWithTitle:@"Dock 手势" icon:@"rectangle.bottomthird.inset.filled"
            bundle:@"MetisKeyboardPrefs" className:@"MTPDockGestureController"]];
        [specs addObject:[self mtSubbundleLinkWithTitle:@"状态栏手势" icon:@"arrow.up.square"
            bundle:@"MetisKeyboardPrefs" className:@"MTPStatusBarGestureController"]];

        PSSpecifier *floatingGroup = [PSSpecifier groupSpecifierWithName:@"悬浮与应用"];
        [specs addObject:floatingGroup];
        [specs addObject:[self mtSubbundleLinkWithTitle:@"悬浮应用" icon:@"macwindow.on.rectangle"
            bundle:@"MetisKeyboardPrefs" className:@"MTPFloatingAppController"]];

        // 自动化区：AI 问答保留分区头；两个功能开关各自独立成组（用户要求
        // 拆分成单独条目、不合并），与链接条目视觉对齐。
        PSSpecifier *automationGroup = [PSSpecifier groupSpecifierWithName:@"自动化"];
        [specs addObject:automationGroup];
        [specs addObject:[self mtSubbundleLinkWithTitle:@"AI 问答" icon:@"bubble.left.and.bubble.right"
            bundle:@"MetisKeyboardPrefs" className:@"MTPAIChatController"]];

        PSSpecifier *smsGroup = [PSSpecifier groupSpecifierWithName:nil];
        [specs addObject:smsGroup];
        [specs addObject:[self mtSwitchWithTitle:@"短信验证码自动复制" icon:@"message.badge.fill"
                                             key:@"smscodecopyBOOL" defaultValue:NO]];

        PSSpecifier *redirectGroup = [PSSpecifier groupSpecifierWithName:nil];
        [specs addObject:redirectGroup];
        [specs addObject:[self mtSwitchWithTitle:@"浏览器重定向" icon:@"arrow.uturn.forward.circle.fill"
                                             key:@"browserredirectBOOL" defaultValue:NO]];

        PSSpecifier *footer = [PSSpecifier groupSpecifierWithName:nil];
        [footer setProperty:@"JavaScript 动作源码在「全局 · 自定义动作」中编辑。" forKey:@"footerText"];
        [specs addObject:footer];

        _specifiers = specs;
    }
    return _specifiers;
}

- (PSSpecifier *)mtSubbundleLinkWithTitle:(NSString *)title icon:(NSString *)iconName
                                    bundle:(NSString *)bundleName className:(NSString *)className {
    PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:title
        target:self
        set:@selector(mtNoopSetter:forSpecifier:)
        get:@selector(mtNoopGetter:)
        detail:nil
        cell:PSLinkCell
        edit:nil];
    // 条目图标：Automatic symbol 经 PS imageView 默认 tint 渲染为蓝色，与全库
    // 条目统一；此处不套 MTSettingsStyle 的 22pt 配置——宿主测试只链接
    // Foundation（PrefsStubs 无 UIKit），Shell 控制器不得引用 MTSettingsStyle。
    UIImage *icon = [UIImage systemImageNamed:iconName];
    if (icon) [link setProperty:icon forKey:@"iconImage"];
    [link setProperty:bundleName forKey:@"metis-subbundle"];
    [link setProperty:className forKey:@"metis-controller"];
    link->action = @selector(openSubbundleController:);
    return link;
}

- (PSSpecifier *)mtSwitchWithTitle:(NSString *)title icon:(NSString *)iconName
                               key:(NSString *)key defaultValue:(BOOL)defaultValue {
    PSSpecifier *toggle = [PSSpecifier preferenceSpecifierNamed:title
        target:self
        set:@selector(setPreferenceValue:specifier:)
        get:@selector(readPreferenceValue:)
        detail:nil
        cell:PSSwitchCell
        edit:nil];
    [toggle setProperty:key forKey:@"key"];
    [toggle setProperty:MTOtherKeyboardDomain forKey:@"defaults"];
    [toggle setProperty:defaultValue ? @YES : @NO forKey:@"default"];
    [toggle setProperty:MTOtherPrefsChanged forKey:@"PostNotification"];
    // 与链接条目同一 iconImage 契约：PSSwitchCell 经 Preferences 默认渲染。
    UIImage *icon = [UIImage systemImageNamed:iconName];
    if (icon) [toggle setProperty:icon forKey:@"iconImage"];
    return toggle;
}

- (NSString *)mtNoopGetter:(PSSpecifier *)specifier {
    (void)specifier;
    return @"";
}

- (void)mtNoopSetter:(id)value forSpecifier:(PSSpecifier *)specifier {
    (void)value; (void)specifier;
}

- (void)openSubbundleController:(PSSpecifier *)specifier {
    NSString *bundleName = [specifier propertyForKey:@"metis-subbundle"];
    NSString *className = [specifier propertyForKey:@"metis-controller"];
    NSError *error = nil;
    Class controllerClass = [MTPrefsSubbundleLoader loadControllerClassFromBundle:bundleName
                                                                       classNamed:className
                                                                            error:&error];
    if (!controllerClass) {
        MTLogError(MTLogModulePrefs, @"state=other-page-load-failed bundle=%@ error=%@",
                   bundleName, error.localizedDescription);
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:[specifier name]
                             message:@"无法载入设置页面，请重新安装当前版本后重试。"
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    id controller = [[controllerClass alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
