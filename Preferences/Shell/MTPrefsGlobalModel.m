#import "MTPrefsGlobalModel.h"

// 功能开关沿用键盘细节域（com.lindo.metis.keyboard）：迁页面不改键名与
// prefschanged 通知，运行端零改动（02 §6：原有具体功能开关仍按功能语义保留）。
static NSString *const MTGlobalPrefsDomain = @"com.lindo.metis.keyboard";
static NSString *const MTGlobalPrefsChanged = @"com.lindo.metis.keyboard/prefschanged";
static NSString *const MTSmsCodeCopyKey = @"smscodecopyBOOL";
static NSString *const MTBrowserRedirectKey = @"browserredirectBOOL";

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

// 原「其他」页「全局手势」「悬浮与应用」两组：链接条目视觉对齐全局页。
+ (NSArray<MTSettingsRow *> *)gestureAndFloatingRows {
    MTSettingsRow *dock = [MTSettingsRow linkRowWithIdentifier:@"global-dock-gesture" title:@"Dock 手势"];
    dock.iconName = @"rectangle.bottomthird.inset.filled";
    dock.colorName = @"orange";
    dock.routeKind = MTSettingsRouteSubbundle;
    dock.subBundle = @"MetisKeyboardPrefs";
    dock.className = @"MTPDockGestureController";

    MTSettingsRow *statusBar = [MTSettingsRow linkRowWithIdentifier:@"global-statusbar-gesture" title:@"状态栏手势"];
    statusBar.iconName = @"arrow.up.square";
    statusBar.colorName = @"orange";
    statusBar.routeKind = MTSettingsRouteSubbundle;
    statusBar.subBundle = @"MetisKeyboardPrefs";
    statusBar.className = @"MTPStatusBarGestureController";

    MTSettingsRow *edge = [MTSettingsRow linkRowWithIdentifier:@"global-screenedge-gesture" title:@"屏幕边缘手势"];
    edge.iconName = @"arrow.left.and.right.square";
    edge.colorName = @"orange";
    edge.routeKind = MTSettingsRouteSubbundle;
    edge.subBundle = @"MetisKeyboardPrefs";
    edge.className = @"MTPEdgeGestureController";

    MTSettingsRow *arc = [MTSettingsRow linkRowWithIdentifier:@"global-cornerarc-gesture" title:@"边缘划弧手势"];
    arc.iconName = @"arrow.up.left.square";
    arc.colorName = @"orange";
    arc.routeKind = MTSettingsRouteSubbundle;
    arc.subBundle = @"MetisKeyboardPrefs";
    arc.className = @"MTPArcGestureController";

    MTSettingsRow *floatingApp = [MTSettingsRow linkRowWithIdentifier:@"global-floating-app" title:@"悬浮应用"];
    floatingApp.iconName = @"macwindow.on.rectangle";
    floatingApp.colorName = @"blue";
    floatingApp.routeKind = MTSettingsRouteSubbundle;
    floatingApp.subBundle = @"MetisKeyboardPrefs";
    floatingApp.className = @"MTPFloatingAppController";

    return @[dock, statusBar, edge, arc, floatingApp];
}

// 原「其他」页「自动化」区：AI 问答链接 + 两个功能开关（各自独立成行，
// 不合并；缺省关与运行端默认一致）。
+ (NSArray<MTSettingsRow *> *)automationRows {
    MTSettingsRow *aiChat = [MTSettingsRow linkRowWithIdentifier:@"global-ai-chat" title:@"AI 问答"];
    aiChat.iconName = @"bubble.left.and.bubble.right";
    aiChat.colorName = @"indigo";
    aiChat.routeKind = MTSettingsRouteSubbundle;
    aiChat.subBundle = @"MetisKeyboardPrefs";
    aiChat.className = @"MTPAIChatController";

    MTSettingsRow *sms = [MTSettingsRow linkRowWithIdentifier:@"global-sms-code-copy" title:@"短信验证码自动复制"];
    sms.kind = MTSettingsRowKindToggle;
    sms.iconName = @"message.badge.fill";
    sms.colorName = @"green";
    sms.userInfo = @([self smsCodeCopyEnabled]);

    MTSettingsRow *redirect = [MTSettingsRow linkRowWithIdentifier:@"global-browser-redirect" title:@"浏览器重定向"];
    redirect.kind = MTSettingsRowKindToggle;
    redirect.iconName = @"arrow.uturn.forward.circle.fill";
    redirect.colorName = @"teal";
    redirect.userInfo = @([self browserRedirectEnabled]);

    return @[aiChat, sms, redirect];
}

+ (MTSettingsPageModel *)globalPageModel {
    MTSettingsSection *resourceSection = [[MTSettingsSection alloc] init];
    resourceSection.headerTitle = @"共享资源";
    resourceSection.rows = [self resourceRows];

    MTSettingsSection *gestureSection = [[MTSettingsSection alloc] init];
    gestureSection.headerTitle = @"手势与悬浮";
    // 沿用原「其他」页分区脚注：合并后动作/面板就在本页「共享资源」。
    gestureSection.footerText = @"在任意界面触发；动作与面板在「共享资源」中定义。";
    gestureSection.rows = [self gestureAndFloatingRows];

    MTSettingsSection *automationSection = [[MTSettingsSection alloc] init];
    automationSection.headerTitle = @"自动化";
    automationSection.rows = [self automationRows];

    // 「配置维护」区：备份/恢复（本版本新增）+ 引用管理（资源反向索引）。
    MTSettingsRow *backup = [MTSettingsRow linkRowWithIdentifier:@"global-config-backup" title:@"配置备份"];
    backup.subtitle = @"导出全部配置，可分享";
    backup.iconName = @"square.and.arrow.up";
    backup.colorName = @"blue";
    backup.routeKind = MTSettingsRouteShellClass;
    backup.className = @"MTPrefsBackupController";

    MTSettingsRow *restore = [MTSettingsRow linkRowWithIdentifier:@"global-config-restore" title:@"配置恢复"];
    restore.subtitle = @"从备份还原，自动保留安全网";
    restore.iconName = @"clock.arrow.circlepath";
    restore.colorName = @"green";
    restore.routeKind = MTSettingsRouteShellClass;
    restore.className = @"MTPrefsRestoreController";

    MTSettingsRow *references = [MTSettingsRow linkRowWithIdentifier:@"global-references" title:@"引用管理"];
    references.iconName = @"internaldrive";
    references.colorName = @"gray";
    references.routeKind = MTSettingsRouteShellClass;
    references.className = @"MTPrefsReferencesController";

    MTSettingsSection *maintenanceSection = [[MTSettingsSection alloc] init];
    maintenanceSection.headerTitle = @"配置维护";
    maintenanceSection.rows = @[backup, restore, references];

    MTSettingsPageModel *model = [[MTSettingsPageModel alloc] init];
    model.sections = @[resourceSection, gestureSection, automationSection, maintenanceSection];
    model.footerText = @"创建一次，多个入口共用";
    return model;
}

#pragma mark - Feature switches (com.lindo.metis.keyboard domain)

+ (BOOL)smsCodeCopyEnabled {
    return [self mtBooleanForKey:MTSmsCodeCopyKey];
}

+ (BOOL)browserRedirectEnabled {
    return [self mtBooleanForKey:MTBrowserRedirectKey];
}

+ (void)setSmsCodeCopyEnabled:(BOOL)enabled {
    [self mtSetBoolean:enabled forKey:MTSmsCodeCopyKey];
}

+ (void)setBrowserRedirectEnabled:(BOOL)enabled {
    [self mtSetBoolean:enabled forKey:MTBrowserRedirectKey];
}

// 读取缺省关，与运行端默认一致（MTSMSCodePolicy / MTBrowserRedirectHooks）。
+ (BOOL)mtBooleanForKey:(NSString *)key {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)MTGlobalPrefsDomain);
    BOOL enabled = NO;
    if (value) {
        if (CFGetTypeID(value) == CFBooleanGetTypeID()) enabled = CFBooleanGetValue((CFBooleanRef)value);
        CFRelease(value);
    }
    return enabled;
}

// 写入权威域 + 广播 prefschanged：与 PS 开关 PostNotification 等效
// （MTPRootListController 同款双发无害），键盘进程即时重载。
+ (void)mtSetBoolean:(BOOL)value forKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             value ? kCFBooleanTrue : kCFBooleanFalse,
                             (__bridge CFStringRef)MTGlobalPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)MTGlobalPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)MTGlobalPrefsChanged,
                                         NULL, NULL, YES);
}

@end
