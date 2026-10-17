#import "MTPrefsGlobalController.h"
#import "MTPrefsSubbundleLoader.h"
#import "MTPrefsBindingsController.h"
#import "MTPrefsReferencesController.h"
#import "MTCore.h"

@implementation MTPrefsGlobalController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"全局";
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *resourceGroup = [PSSpecifier groupSpecifierWithName:@"共享资源"];
        [resourceGroup setProperty:@"动作与面板在键盘、剪切板、手势之间共用一份定义。" forKey:@"footerText"];
        [specs addObject:resourceGroup];

        [specs addObject:[self mtSubbundleLinkWithTitle:@"自定义动作"
                                               subtitle:@"URL Scheme、文本、打开应用、应用快捷方式、系统动作、JavaScript 脚本"
                                                  icon:@"square.and.pencil"
                                                  bundle:@"MetisKeyboardPrefs"
                                              className:@"MTPCustomActionsController"]];
        [specs addObject:[self mtSubbundleLinkWithTitle:@"面板管理"
                                               subtitle:@"面板内容、顺序与外观"
                                                  icon:@"square.grid.2x2"
                                                  bundle:@"MetisKeyboardPrefs"
                                              className:@"MTPKeyboardPanelController"]];

        PSSpecifier *invocationGroup = [PSSpecifier groupSpecifierWithName:@"调用配置"];
        [specs addObject:invocationGroup];

        PSSpecifier *bindings = [PSSpecifier preferenceSpecifierNamed:@"入口绑定"
            target:self
            set:@selector(mtNoopSetter:forSpecifier:)
            get:@selector(mtBindingsSummary:)
            detail:MTPrefsBindingsController.class
            cell:PSLinkCell
            edit:nil];
        UIImage *bindingsIcon = [UIImage systemImageNamed:@"arrow.triangle.branch"];
        if (bindingsIcon) [bindings setProperty:bindingsIcon forKey:@"iconImage"];
        [specs addObject:bindings];

        PSSpecifier *maintenanceGroup = [PSSpecifier groupSpecifierWithName:@"配置维护"];
        [specs addObject:maintenanceGroup];

        PSSpecifier *references = [PSSpecifier preferenceSpecifierNamed:@"引用管理"
            target:self
            set:@selector(mtNoopSetter:forSpecifier:)
            get:@selector(mtReferencesSummary:)
            detail:MTPrefsReferencesController.class
            cell:PSLinkCell
            edit:nil];
        UIImage *referencesIcon = [UIImage systemImageNamed:@"link.circle"];
        if (referencesIcon) [references setProperty:referencesIcon forKey:@"iconImage"];
        [specs addObject:references];

        _specifiers = specs;
    }
    return _specifiers;
}

- (PSSpecifier *)mtSubbundleLinkWithTitle:(NSString *)title
                                 subtitle:(NSString *)subtitle
                                    icon:(NSString *)iconName
                                  bundle:(NSString *)bundleName
                              className:(NSString *)className {
    PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:title
        target:self
        set:@selector(mtNoopSetter:forSpecifier:)
        get:@selector(mtSubbundleSubtitle:)
        detail:nil
        cell:PSLinkCell
        edit:nil];
    [link setProperty:subtitle forKey:@"subtitle"];
    [link setProperty:bundleName forKey:@"metis-subbundle"];
    [link setProperty:className forKey:@"metis-controller"];
    UIImage *icon = [UIImage systemImageNamed:iconName];
    if (icon) [link setProperty:icon forKey:@"iconImage"];
    link->action = @selector(openSubbundleController:);
    return link;
}

- (NSString *)mtSubbundleSubtitle:(PSSpecifier *)specifier {
    return [specifier propertyForKey:@"subtitle"];
}

- (NSString *)mtBindingsSummary:(PSSpecifier *)specifier {
    (void)specifier;
    return @"按键盘 / 手势分组查看入口";
}

- (NSString *)mtReferencesSummary:(PSSpecifier *)specifier {
    (void)specifier;
    return @"资源到入口的反向索引";
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
        MTLogError(MTLogModulePrefs, @"state=global-page-load-failed bundle=%@ error=%@",
                   bundleName, error.localizedDescription);
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:[specifier name]
                             message:@"无法载入编辑器，请重新安装当前版本后重试。"
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    id controller = [[controllerClass alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
