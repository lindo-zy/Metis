#import "MTPrefsModuleController.h"
#import "MTCore.h"

// PSLinkCell 的 detail 实例化走 -init，无法带参；用类与模块 ID 的固定映射。
static MTPrefsModuleInfo *MTPendingModuleInfo;

@implementation MTPrefsModuleController {
    MTPrefsModuleInfo *_info;
}

+ (Class)classForModule:(NSString *)moduleID {
    if ([moduleID isEqualToString:MTModuleCapture]) return [MTPrefsCaptureModuleController class];
    if ([moduleID isEqualToString:MTModuleKeyboard]) return [MTPrefsKeyboardModuleController class];
    return [MTPrefsClipboardModuleController class];
}

- (instancetype)initWithModuleInfo:(MTPrefsModuleInfo *)info {
    self = [super init];
    if (self) _info = info;
    return self;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _info = _info ?: MTPendingModuleInfo;
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *moduleSwitch = [PSSpecifier preferenceSpecifierNamed:@"启用模块"
            target:self
            set:@selector(setModuleEnabled:forSpecifier:)
            get:@selector(moduleEnabledForSpecifier:)
            detail:nil
            cell:PSSwitchCell
            edit:nil];
        [specs addObject:moduleSwitch];

        PSSpecifier *status = [PSSpecifier preferenceSpecifierNamed:@"状态"
            target:self
            set:@selector(mtNoopSetter:forSpecifier:)
            get:@selector(mtStatusLineText:)
            detail:nil
            cell:PSTitleValueCell
            edit:nil];
        status.identifier = @"module-status";
        [specs addObject:status];

        PSSpecifier *detailGroup = [PSSpecifier groupSpecifierWithName:@"详细设置"];
        [specs addObject:detailGroup];

        PSSpecifier *detailLink = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@ · 详细设置", _info.title]
            target:self
            set:@selector(mtNoopSetter:forSpecifier:)
            get:@selector(mtDetailSummary:)
            detail:nil
            cell:PSLinkCell
            edit:nil];
        detailLink.identifier = @"module-detail";
        detailLink.target = self;
        detailLink->action = @selector(openDetailSettings:);
        [specs addObject:detailLink];

        _specifiers = specs;
    }
    return _specifiers;
}

- (NSString *)title {
    return _info.title;
}

- (NSString *)mtStatusLineText:(PSSpecifier *)specifier {
    (void)specifier;
    if (![MTModuleGate globalEnabled]) return @"Metis 总开关已关闭";
    return [MTModuleGate moduleEnabled:_info.moduleID] ? @"已启用 · 等待运行状态" : @"已关闭";
}

- (NSNumber *)moduleEnabledForSpecifier:(PSSpecifier *)specifier {
    (void)specifier;
    return @([MTModuleGate moduleSwitchRaw:_info.moduleID]);
}

- (void)setModuleEnabled:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier {
    (void)specifier;
    [MTConfigService setModule:_info.moduleID enabled:value.boolValue];
    [MTConfigService flush];
    [MTModuleGate reload];
}

- (NSString *)mtDetailSummary:(PSSpecifier *)specifier {
    (void)specifier;
    if ([_info subBundleAvailable]) return _info.subController;
    return @"此版本尚未提供";
}

- (void)mtNoopSetter:(id)value forSpecifier:(PSSpecifier *)specifier {
    (void)value; (void)specifier;
}

// 打开模块详细设置子包：加载子 bundle 后实例化其根控制器并压栈。
// 子包缺失/加载失败一律给出明确提示，不静默跳过。
- (void)openDetailSettings:(PSSpecifier *)specifier {
    (void)specifier;
    if (![_info subBundleAvailable]) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:_info.title
                             message:@"此版本尚未提供该模块的详细设置。"
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSString *bundlePath = MTResolvePath(
        [NSString stringWithFormat:@"/Library/PreferenceBundles/%@.bundle", _info.subBundle]);
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    Class controllerClass = nil;
    if ([bundle load]) {
        controllerClass = [bundle classNamed:_info.subController];
    }
    if (!controllerClass) {
        controllerClass = NSClassFromString(_info.subController);
    }
    if (!controllerClass) {
        MTLogError(MTLogModulePrefs, @"state=detail-load-failed bundle=%@", _info.subBundle);
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:_info.title
                             message:@"无法载入详细设置，请重新安装当前版本后重试。"
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    id controller = [[controllerClass alloc] init];
    UINavigationController *nav = [self navigationController];
    [nav pushViewController:controller animated:YES];
}

@end

@implementation MTPrefsCaptureModuleController
- (instancetype)init {
    MTPendingModuleInfo = nil;
    for (MTPrefsModuleInfo *info in [MTPrefsModuleInfo allModules]) {
        if ([info.moduleID isEqualToString:MTModuleCapture]) MTPendingModuleInfo = info;
    }
    return [self initWithModuleInfo:MTPendingModuleInfo];
}
@end

@implementation MTPrefsKeyboardModuleController
- (instancetype)init {
    MTPendingModuleInfo = nil;
    for (MTPrefsModuleInfo *info in [MTPrefsModuleInfo allModules]) {
        if ([info.moduleID isEqualToString:MTModuleKeyboard]) MTPendingModuleInfo = info;
    }
    return [self initWithModuleInfo:MTPendingModuleInfo];
}
@end

@implementation MTPrefsClipboardModuleController
- (instancetype)init {
    MTPendingModuleInfo = nil;
    for (MTPrefsModuleInfo *info in [MTPrefsModuleInfo allModules]) {
        if ([info.moduleID isEqualToString:MTModuleClipboard]) MTPendingModuleInfo = info;
    }
    return [self initWithModuleInfo:MTPendingModuleInfo];
}
@end
