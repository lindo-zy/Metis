#import "MTPrefsRootController.h"
#import "MTPrefsModuleController.h"
#import "MTPrefsAboutController.h"
#import "MTCore.h"
#import <objc/message.h>

@implementation MTPrefsModuleInfo

+ (NSArray<MTPrefsModuleInfo *> *)allModules {
    NSArray *configs = @[
        @[@"capture", @"截图与标注", @"模式、编辑、输出", @"MetisCapturePrefs", @"MTCaptureRootListController"],
        @[@"keyboard", @"键盘与操作", @"工具栏、面板、输入", @"MetisKeyboardPrefs", @"MTPRootListController"],
        @[@"clipboard", @"剪贴板", @"历史、收藏、悬浮预览", @"MetisClipboardPrefs", @"MTPrefsClipboardRootController"],
    ];
    NSMutableArray *modules = [NSMutableArray array];
    for (NSArray *config in configs) {
        MTPrefsModuleInfo *info = [[MTPrefsModuleInfo alloc] init];
        info.moduleID = config[0];
        info.title = config[1];
        info.subtitle = config[2];
        info.subBundle = config[3];
        info.subController = config[4];
        [modules addObject:info];
    }
    return modules;
}

- (BOOL)subBundleAvailable {
    NSString *path = MTResolvePath(
        [NSString stringWithFormat:@"/Library/PreferenceBundles/%@.bundle", self.subBundle]);
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
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

        PSSpecifier *status = [PSSpecifier preferenceSpecifierNamed:@"状态"
            target:self
            set:@selector(mtNoopSetter:forSpecifier:)
            get:@selector(mtStatusLineText)
            detail:nil
            cell:PSTitleValueCell
            edit:nil];
        status.identifier = @"metis-status";
        [specs addObject:status];

        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"功能模块"];
        [specs addObject:group];

        for (MTPrefsModuleInfo *info in [MTPrefsModuleInfo allModules]) {
            Class moduleClass = [MTPrefsModuleController classForModule:info.moduleID];
            PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:info.title
                target:self
                set:@selector(mtNoopSetter:forSpecifier:)
                get:@selector(mtModuleSubtitle:forSpecifier:)
                detail:moduleClass
                cell:PSLinkCell
                edit:nil];
            link.identifier = [NSString stringWithFormat:@"module-%@", info.moduleID];
            [link setProperty:info forKey:@"metis-module-info"];
            [specs addObject:link];
        }

        PSSpecifier *supportGroup = [PSSpecifier groupSpecifierWithName:@"管理与支持"];
        [specs addObject:supportGroup];

        PSSpecifier *about = [PSSpecifier preferenceSpecifierNamed:@"关于"
            target:self
            set:@selector(mtNoopSetter:forSpecifier:)
            get:@selector(aboutSummary)
            detail:[MTPrefsAboutController class]
            cell:PSLinkCell
            edit:nil];
        [specs addObject:about];

        _specifiers = specs;
    }
    return _specifiers;
}

- (NSString *)mtStatusLineText {
    NSUInteger enabled = [MTModuleGate enabledModuleCount];
    NSString *state = [MTModuleGate globalEnabled]
        ? [NSString stringWithFormat:@"已启用 %lu/3 模块", (unsigned long)enabled]
        : @"Metis 已停用";
    return [state stringByAppendingString:@" · 等待运行状态"];
}

- (BOOL)globalEnabledForSpecifier:(PSSpecifier *)specifier {
    (void)specifier;
    return [MTModuleGate globalEnabled];
}

- (void)setGlobalEnabled:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier {
    (void)specifier;
    [MTConfigService setGlobalEnabled:value.boolValue];
    [MTConfigService flush];
    [MTModuleGate reload];
    [self reloadSpecifierByID:@"metis-status"];
}

- (NSString *)mtModuleSubtitle:(PSSpecifier *)specifier {
    MTPrefsModuleInfo *info = [specifier propertyForKey:@"metis-module-info"];
    return info.subtitle;
}

- (void)mtNoopSetter:(id)value forSpecifier:(PSSpecifier *)specifier {
    (void)value; (void)specifier;
}

- (NSString *)aboutSummary {
    return [NSString stringWithFormat:@"版本 %@ · 三模块统一管理", MTCoreVersionString];
}

- (void)reloadSpecifierByID:(NSString *)identifier {
    if (![self respondsToSelector:@selector(reloadSpecIndex:)]) return;
    NSUInteger index = [self.specifiers indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return [identifier isEqualToString:((PSSpecifier *)obj).identifier];
    }];
    if (index != NSNotFound) {
        ((void ( *)(id, SEL, NSUInteger))objc_msgSend)(self, @selector(reloadSpecIndex:), index);
    }
}

@end
