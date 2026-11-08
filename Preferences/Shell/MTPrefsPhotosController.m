#import "MTPrefsPhotosController.h"
#import "MTPhotosPreferences.h"
#import "MTLog.h"

// 相册增强页（Shell 内实现，模式与充电页一致）：两个独立开关不合并成行。
// 开关写权威域 + config-changed 广播；运行端在照片 App 内实时读键，改完从
// 任务切换器结束「照片」重开即生效（footer 同步说明）。
@implementation MTPrefsPhotosController

- (void)prepareSettingsModel {
    if (self.model) return;
    // 初值来自 row.userInfo；写值后重建模型，避免重新配置 cell 时开关回弹
    // （与首页/充电页开关同一写法）。
    __weak typeof(self) weakSelf = self;
    MTSettingsRow *maxZoom = [MTSettingsRow linkRowWithIdentifier:@"photos-max-zoom" title:@"启用最大缩放"];
    maxZoom.kind = MTSettingsRowKindToggle;
    maxZoom.iconName = @"plus.magnifyingglass";
    maxZoom.colorName = @"orange";
    maxZoom.userInfo = @(MTPhotosMaxZoomEnabled());
    maxZoom.toggleHandler = ^(BOOL on) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        MTSetPhotosMaxZoomEnabled(on);
        MTLogInfo(@"prefs", @"state=photos-max-zoom-set value=%@", on ? @"1" : @"0");
        strongSelf.model = nil;
        [strongSelf prepareSettingsModel];
        [strongSelf render];
    };

    MTSettingsRow *skipConfirm = [MTSettingsRow linkRowWithIdentifier:@"photos-skip-delete-confirm" title:@"跳过删除确认"];
    skipConfirm.kind = MTSettingsRowKindToggle;
    skipConfirm.iconName = @"trash";
    skipConfirm.colorName = @"orange";
    skipConfirm.userInfo = @(MTPhotosSkipDeleteConfirmEnabled());
    skipConfirm.toggleHandler = ^(BOOL on) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        MTSetPhotosSkipDeleteConfirmEnabled(on);
        MTLogInfo(@"prefs", @"state=photos-skip-confirm-set value=%@", on ? @"1" : @"0");
        strongSelf.model = nil;
        [strongSelf prepareSettingsModel];
        [strongSelf render];
    };

    MTSettingsSection *section = [MTSettingsSection sectionWithRows:@[maxZoom, skipConfirm]];
    self.model = [MTSettingsPageModel new];
    self.model.sections = @[section];
    self.model.footerText =
        @"仅作用于系统「照片」App：最大缩放解除照片查看器的缩放上限（最高 16 倍）；"
        "跳过删除确认后删除照片不再弹窗，直接删除。更改后从任务切换器结束「照片」"
        "再重新打开即可生效，无需注销。";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"相册增强";
    [self prepareSettingsModel];
    [self render];
}

@end
