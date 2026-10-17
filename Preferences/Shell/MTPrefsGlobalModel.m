#import "MTPrefsGlobalModel.h"

@implementation MTPrefsGlobalModel

+ (NSArray<MTSettingsRow *> *)resourceRows {
    MTSettingsRow *actions = [MTSettingsRow linkRowWithIdentifier:@"global-custom-actions" title:@"自定义动作"];
    actions.subtitle = @"打开应用、URL Scheme、JS 脚本等";
    actions.iconName = @"arrow.triangle.branch";
    actions.colorName = @"purple";
    actions.routeKind = MTSettingsRouteSubbundle;
    actions.subBundle = @"MetisKeyboardPrefs";
    actions.className = @"MTPCustomActionsController";

    MTSettingsRow *panels = [MTSettingsRow linkRowWithIdentifier:@"global-panels" title:@"面板管理"];
    panels.subtitle = @"内容、顺序与外观";
    panels.iconName = @"square.stack.3d.up.fill";
    panels.colorName = @"blue";
    panels.routeKind = MTSettingsRouteSubbundle;
    panels.subBundle = @"MetisKeyboardPrefs";
    panels.className = @"MTPKeyboardPanelController";

    return @[actions, panels];
}

+ (MTSettingsPageModel *)globalPageModel {
    MTSettingsSection *resourceSection = [[MTSettingsSection alloc] init];
    resourceSection.headerTitle = @"共享资源";
    resourceSection.rows = [self resourceRows];

    MTSettingsRow *references = [MTSettingsRow linkRowWithIdentifier:@"global-references" title:@"引用管理"];
    references.iconName = @"internaldrive";
    references.colorName = @"gray";
    references.routeKind = MTSettingsRouteShellClass;
    references.className = @"MTPrefsReferencesController";

    MTSettingsSection *maintenanceSection = [[MTSettingsSection alloc] init];
    maintenanceSection.headerTitle = @"配置维护";
    maintenanceSection.rows = @[references];

    MTSettingsPageModel *model = [[MTSettingsPageModel alloc] init];
    model.sections = @[resourceSection, maintenanceSection];
    model.footerText = @"创建一次，多个入口共用";
    return model;
}

@end
