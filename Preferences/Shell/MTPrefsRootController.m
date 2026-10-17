#import "MTPrefsRootController.h"
#import "MTPrefsAboutController.h"
#import "MTPrefsGlobalController.h"
#import "MTPrefsOtherController.h"
#import "MTPrefsSubbundleLoader.h"
#import "MTCore.h"
#import <objc/message.h>

@implementation MTPrefsCategoryInfo

+ (NSArray<MTPrefsCategoryInfo *> *)allCategories {
    // 五分类固定顺序与摘要（02-settings-ux §1）；
    // 全局与其他在 Shell 内，键盘/剪切板/截图直达各子包根控制器。
    NSArray *configs = @[
        @[@"global",    @"全局",   @"自定义动作、面板与入口绑定", @"globe",
          [NSNull null], NSStringFromClass(MTPrefsGlobalController.class)],
        @[@"keyboard",  @"键盘",   @"工具栏、输入与键盘手势", @"keyboard",
          @"MetisKeyboardPrefs", @"MTPRootListController"],
        @[@"clipboard", @"剪切板", @"历史、收藏与悬浮预览", @"doc.on.doc",
          @"MetisClipboardPrefs", @"MTClipboardRootListController"],
        @[@"capture",   @"截图",   @"截取、标注与长截图", @"camera.viewfinder",
          @"MetisCapturePrefs", @"MTCaptureRootListController"],
        @[@"other",     @"其他",   @"全局手势、悬浮应用与自动化", @"square.grid.2x2",
          [NSNull null], NSStringFromClass(MTPrefsOtherController.class)],
    ];
    NSMutableArray *categories = [NSMutableArray array];
    for (NSArray *config in configs) {
        MTPrefsCategoryInfo *info = [[MTPrefsCategoryInfo alloc] init];
        info.categoryID = config[0];
        info.title = config[1];
        info.subtitle = config[2];
        info.iconName = config[3];
        info.subBundle = [config[4] isKindOfClass:NSString.class] ? config[4] : nil;
        info.subController = config[5];
        [categories addObject:info];
    }
    return categories;
}

@end

@implementation MTPrefsRootController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *globalSwitch = [PSSpecifier preferenceSpecifierNamed:@"启用 Metis"
            target:self
            set:@selector(setGlobalEnabled:forSpecifier:)
            get:@selector(globalEnabledForSpecifier:)
            detail:nil
            cell:PSSwitchCell
            edit:nil];
        [globalSwitch setProperty:@YES forKey:@"enabled"];
        [specs addObject:globalSwitch];

        // 总开关关闭时仍允许配置，仅显示一条整体暂停提示（02 §1）。
        if (![MTModuleGate globalEnabled]) {
            PSSpecifier *paused = [PSSpecifier preferenceSpecifierNamed:@"Metis 已暂停"
                target:self
                set:@selector(mtNoopSetter:forSpecifier:)
                get:@selector(mtPausedSummary:)
                detail:nil
                cell:PSTitleValueCell
                edit:nil];
            paused.identifier = @"metis-paused-notice";
            [specs addObject:paused];
        }

        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"功能分类"];
        [specs addObject:group];

        for (MTPrefsCategoryInfo *info in [MTPrefsCategoryInfo allCategories]) {
            PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:info.title
                target:self
                set:@selector(mtNoopSetter:forSpecifier:)
                get:@selector(mtCategorySubtitle:)
                detail:nil
                cell:PSLinkCell
                edit:nil];
            link.identifier = [NSString stringWithFormat:@"category-%@", info.categoryID];
            [link setProperty:info forKey:@"metis-category-info"];
            UIImage *icon = [UIImage systemImageNamed:info.iconName];
            if (icon) [link setProperty:icon forKey:@"iconImage"];
            // 分类直达实际配置：经 action 加载目标控制器并压栈（子包与 Shell 同路径）。
            link->action = @selector(openCategory:);
            [specs addObject:link];
        }

        PSSpecifier *supportGroup = [PSSpecifier groupSpecifierWithName:@"管理与支持"];
        [specs addObject:supportGroup];

        PSSpecifier *about = [PSSpecifier preferenceSpecifierNamed:@"关于"
            target:self
            set:@selector(mtNoopSetter:forSpecifier:)
            get:@selector(aboutSummary:)
            detail:[MTPrefsAboutController class]
            cell:PSLinkCell
            edit:nil];
        [specs addObject:about];

        _specifiers = specs;
        MTLogInfo(MTLogModulePrefs, @"state=root-specifiers-ready count=%lu", (unsigned long)specs.count);
    }
    return _specifiers;
}

- (NSString *)mtPausedSummary:(PSSpecifier *)specifier {
    (void)specifier;
    return @"所有入口已停止；配置仍可修改，重新开启后生效";
}

- (NSNumber *)globalEnabledForSpecifier:(PSSpecifier *)specifier {
    (void)specifier;
    return @([MTModuleGate globalEnabled]);
}

- (void)setGlobalEnabled:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier {
    (void)specifier;
    [MTConfigService setGlobalEnabled:value.boolValue];
    [MTConfigService flush];
    [MTModuleGate reload];
    // 暂停提示行的显隐随开关变化：重建整个 specifier 表（getter 保持对象返回 ABI）。
    @try {
        self->_specifiers = nil;
        [self reloadSpecifiers];
    } @catch (__unused NSException *exception) {
        // 个别宿主不支持全量重建：退回仅刷新开关行。
    }
}

- (NSString *)mtCategorySubtitle:(PSSpecifier *)specifier {
    MTPrefsCategoryInfo *info = [specifier propertyForKey:@"metis-category-info"];
    return info.subtitle;
}

- (void)mtNoopSetter:(id)value forSpecifier:(PSSpecifier *)specifier {
    (void)value; (void)specifier;
}

- (NSString *)aboutSummary:(PSSpecifier *)specifier {
    (void)specifier;
    return [NSString stringWithFormat:@"版本 %@", MTCoreVersionString];
}

// 分类直达：子包缺失/加载失败给出明确提示，不静默跳过（02 §7）。
- (void)openCategory:(PSSpecifier *)specifier {
    MTPrefsCategoryInfo *info = [specifier propertyForKey:@"metis-category-info"];
    if (!info) return;
    Class controllerClass = nil;
    if (info.subBundle.length > 0) {
        NSError *error = nil;
        controllerClass = [MTPrefsSubbundleLoader loadControllerClassFromBundle:info.subBundle
                                                                       classNamed:info.subController
                                                                            error:&error];
        if (!controllerClass) {
            MTLogError(MTLogModulePrefs, @"state=category-load-failed bundle=%@ error=%@",
                       info.subBundle, error.localizedDescription);
        }
    } else {
        controllerClass = NSClassFromString(info.subController);
    }
    if (!controllerClass) {
        [self mtPresentUnavailableAlertWithTitle:info.title];
        return;
    }
    id controller = [[controllerClass alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)mtPresentUnavailableAlertWithTitle:(NSString *)title {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:@"无法载入该分类的设置页面，请重新安装当前版本后重试。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
