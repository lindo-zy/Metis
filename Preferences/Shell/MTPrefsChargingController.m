#import "MTPrefsChargingController.h"
#import "MTChargingPreferences.h"

@implementation MTPrefsChargingController
- (void)prepareSettingsModel {
    if (self.model) return;
    MTSettingsRow *toggle = [MTSettingsRow linkRowWithIdentifier:@"charging-details-enabled" title:@"锁屏充电详情"];
    toggle.kind = MTSettingsRowKindToggle;
    toggle.iconName = @"bolt.batteryblock.fill";
    toggle.colorName = @"green";
    toggle.subtitle = @"充电时在锁屏底部显示详情";
    toggle.userInfo = @(MTChargingDetailsEnabled());
    toggle.toggleHandler = ^(BOOL on) { MTSetChargingDetailsEnabled(on); };
    MTSettingsSection *section = [MTSettingsSection sectionWithRows:@[toggle]];
    section.footerText = @"默认关闭，开启后立即生效；也受 Metis 总开关控制。";
    MTSettingsRow *info = [MTSettingsRow linkRowWithIdentifier:@"charging-details-info" title:@"实时充电数据"];
    info.kind = MTSettingsRowKindInfo;
    info.subtitle = @"电池侧功率、近 60 秒曲线、电量、电压、电流、电池温度和充满预估。设备未提供的数据以 — 显示；电池侧功率不等于充电器输出功率。";
    self.model = [MTSettingsPageModel new];
    self.model.sections = @[section, [MTSettingsSection sectionWithRows:@[info]]];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"充电";
    [self prepareSettingsModel];
    [self render];
}
@end
