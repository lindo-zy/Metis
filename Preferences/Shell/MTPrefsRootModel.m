#import "MTPrefsRootModel.h"
#import "MTCore.h"

// 五分类固定顺序与摘要（02 §1）；全局与其他在 Shell 内，键盘/剪切板/截图
// 直达各子包根控制器。行元组：[id, 标题, 摘要, SF Symbol, 色token,
// 子包(NSNull 或字符串), 控制器类名]。控制器一律字符串引用：模型不链接
// 子包/壳控制器类，宿主测试只编译模型不编译控制器。
// configs 供 Tests/Host/run-prefs-shell-tests.sh 的结构检查解析，勿改元组形态。
static NSArray *MTRootCategoryConfigs(void) {
    return @[
        @[@"global",    @"全局",   @"自定义动作与面板管理", @"circle.hexagongrid.fill", @"indigo",
          [NSNull null], @"MTPrefsGlobalController"],
        @[@"keyboard",  @"键盘",   @"工具栏、输入与键盘手势", @"keyboard", @"blue",
          @"MetisKeyboardPrefs", @"MTPRootListController"],
        @[@"clipboard", @"剪切板", @"历史、收藏与悬浮预览", @"doc.on.clipboard", @"green",
          @"MetisClipboardPrefs", @"MTClipboardRootListController"],
        @[@"capture",   @"截图",   @"截取、标注与长截图", @"crop", @"purple",
          @"MetisCapturePrefs", @"MTCaptureRootListController"],
        @[@"other",     @"其他",   @"全局手势、悬浮应用与自动化", @"square.grid.2x2.fill", @"orange",
          [NSNull null], @"MTPrefsOtherController"],
    ];
}

@implementation MTPrefsRootModel

+ (NSArray<MTSettingsRow *> *)categoryRows {
    NSMutableArray<MTSettingsRow *> *rows = [NSMutableArray array];
    for (NSArray *config in MTRootCategoryConfigs()) {
        // identifier 保留 category- 前缀：搜索定位/flash 与旧版 specifier ID 一致。
        MTSettingsRow *row = [MTSettingsRow linkRowWithIdentifier:[@"category-" stringByAppendingString:config[0]]
                                                            title:config[1]];
        row.subtitle = config[2];
        row.iconName = config[3];
        row.colorName = config[4];
        if ([config[5] isKindOfClass:NSString.class]) {
            row.routeKind = MTSettingsRouteSubbundle;
            row.subBundle = config[5];
        } else {
            row.routeKind = MTSettingsRouteShellClass;
        }
        row.className = config[6];
        [rows addObject:row];
    }
    return rows;
}

+ (MTSettingsPageModel *)rootPageModel {
    NSMutableArray<MTSettingsRow *> *toggleRows = [NSMutableArray array];

    MTSettingsRow *toggle = [MTSettingsRow linkRowWithIdentifier:@"global-enabled" title:@"启用 Metis"];
    toggle.kind = MTSettingsRowKindToggle;
    toggle.userInfo = @([self globalEnabled]); // 开关初始状态（cell 读取 boolValue）
    [toggleRows addObject:toggle];

    // 总开关关闭时仍允许配置，仅追加一条整体暂停提示（02 §1；非模块状态行）。
    if (![self globalEnabled]) {
        MTSettingsRow *paused = [MTSettingsRow linkRowWithIdentifier:@"metis-paused-notice" title:@"Metis 已暂停"];
        paused.kind = MTSettingsRowKindInfo;
        paused.subtitle = @"所有入口已停止；配置仍可修改，重新开启后生效";
        [toggleRows addObject:paused];
    }

    MTSettingsSection *toggleSection = [MTSettingsSection sectionWithRows:toggleRows];

    MTSettingsSection *categorySection = [[MTSettingsSection alloc] init];
    categorySection.headerTitle = @"功能模块";
    categorySection.rows = [self categoryRows];

    MTSettingsPageModel *model = [[MTSettingsPageModel alloc] init];
    model.sections = @[toggleSection, categorySection];
    model.footerText = @"按功能分类，统一配置";
    MTLogInfo(MTLogModulePrefs, @"state=root-model-ready paused=%@",
              [self globalEnabled] ? @"0" : @"1");
    return model;
}

+ (BOOL)globalEnabled {
    return [MTModuleGate globalEnabled];
}

+ (void)setGlobalEnabled:(BOOL)enabled {
    [MTConfigService setGlobalEnabled:enabled];
    [MTConfigService flush];
    [MTModuleGate reload];
    MTLogInfo(MTLogModulePrefs, @"state=global-enabled-set value=%@", enabled ? @"1" : @"0");
}

@end
