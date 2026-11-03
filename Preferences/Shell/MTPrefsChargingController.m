#import "MTPrefsChargingController.h"
#import "MTChargingPreferences.h"
#import "MTChargingCardView.h"
#import "MTChargingSnapshot.h"
#include <math.h>

// 锁屏效果预览：直接复用锁屏模块的绘制代码（MTChargingCardView），按页面宽度
// 等比缩放。数据固定为示意值——设置页不读电池服务，既不与 SpringBoard 抢
// IOKit 注册表，也不会把一次采样误呈现成实时读数。
static const CGFloat MTPrefsChargingPreviewSideInset = 20.0;
static const CGFloat MTPrefsChargingPreviewMaxWidth = 430.0;
static const CGFloat MTPrefsChargingPreviewTopInset = 10.0;
static const CGFloat MTPrefsChargingPreviewCaptionGap = 8.0;
static const CGFloat MTPrefsChargingPreviewCaptionHeight = 16.0;
static const CGFloat MTPrefsChargingPreviewBottomInset = 12.0;

@interface MTPrefsChargingPreviewView : UIView
+ (CGFloat)heightForWidth:(CGFloat)width;
- (void)setPreviewEnabled:(BOOL)enabled;
@end

@implementation MTPrefsChargingPreviewView {
    MTChargingCardView *_card;
    UILabel *_caption;
}

+ (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat available = MAX(width - MTPrefsChargingPreviewSideInset * 2.0, 0.0);
    CGFloat cardWidth = MIN(available, MTPrefsChargingPreviewMaxWidth);
    return MTPrefsChargingPreviewTopInset + cardWidth * MTChargingCardDesignHeight /
        MTChargingCardDesignWidth + MTPrefsChargingPreviewCaptionGap +
        MTPrefsChargingPreviewCaptionHeight + MTPrefsChargingPreviewBottomInset;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _card = [[MTChargingCardView alloc] initWithFrame:CGRectZero];
        [self addSubview:_card];
        _caption = [[UILabel alloc] initWithFrame:CGRectZero];
        _caption.font = [UIFont systemFontOfSize:12.0];
        _caption.textColor = UIColor.secondaryLabelColor;
        _caption.adjustsFontForContentSizeCategory = YES;
        [self addSubview:_caption];
        [self mtApplySampleData];
    }
    return self;
}

// 示意数据：与设备电量、充电状态无关，保证设置页在任何状态下都显示同一张卡片。
- (void)mtApplySampleData {
    NSDictionary *properties = @{@"ExternalConnected": @YES, @"IsCharging": @YES,
        @"CurrentCapacity": @62, @"MaxCapacity": @100, @"Voltage": @4020,
        @"InstantAmperage": @2090, @"Temperature": @3320,
        @"AppleRawMaxCapacity": @3279, @"AppleRawCurrentCapacity": @2033, @"DesignCapacity": @3181, @"AvgTimeToFull": @48};
    MTChargingSnapshot *snapshot = [MTChargingSnapshot snapshotWithProperties:properties
        fallbackLevel:0.62 connected:YES charging:YES];
    snapshot.sessionGainMilliampHours = 420; // fixed preview, never live telemetry
    [_card updateSnapshot:snapshot];
}

- (void)setPreviewEnabled:(BOOL)enabled {
    // 关闭态压暗而不是隐藏：用户仍能看到开启后的样式，同时不会误以为已生效。
    _card.alpha = enabled ? 1.0 : 0.55;
    _caption.text = @"锁屏效果预览 · 示意数据";
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat available = MAX(CGRectGetWidth(self.bounds) - MTPrefsChargingPreviewSideInset * 2.0, 0.0);
    CGFloat cardWidth = MIN(available, MTPrefsChargingPreviewMaxWidth);
    CGFloat cardHeight = cardWidth * MTChargingCardDesignHeight / MTChargingCardDesignWidth;
    CGRect cardFrame = CGRectMake((CGRectGetWidth(self.bounds) - cardWidth) / 2.0,
        MTPrefsChargingPreviewTopInset, cardWidth, cardHeight);
    _card.frame = cardFrame;
    // 卡片圆角按设计稿比例缩放，描边宽度保持 0.5pt 不随缩放变粗。
    _card.layer.cornerRadius = 28.0 * cardWidth / MTChargingCardDesignWidth;
    _caption.frame = CGRectMake(CGRectGetMinX(cardFrame), CGRectGetMaxY(cardFrame) + MTPrefsChargingPreviewCaptionGap,
        cardWidth, MTPrefsChargingPreviewCaptionHeight);
}
@end

@interface MTPrefsChargingController ()
@property(nonatomic, strong) MTPrefsChargingPreviewView *preview;
@end

@implementation MTPrefsChargingController
- (void)prepareSettingsModel {
    if (self.model) return;
    MTSettingsRow *toggle = [MTSettingsRow linkRowWithIdentifier:@"charging-details-enabled" title:@"锁屏充电详情"];
    toggle.kind = MTSettingsRowKindToggle;
    toggle.iconName = @"bolt.batteryblock.fill";
    toggle.colorName = @"green";
    toggle.userInfo = @(MTChargingDetailsEnabled());
    __weak typeof(self) weakSelf = self;
    toggle.toggleHandler = ^(BOOL on) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        MTSetChargingDetailsEnabled(on);
        // 开关写值后重建模型：cell 的初值来自 row.userInfo，不重建则重新配置
        // cell 时开关会回弹到旧值（与全局页/首页开关同一写法）。
        strongSelf.model = nil;
        [strongSelf prepareSettingsModel];
        [strongSelf render];
        [strongSelf.preview setPreviewEnabled:MTChargingDetailsEnabled()];
    };
    MTSettingsSection *section = [MTSettingsSection sectionWithRows:@[toggle]];
    self.model = [MTSettingsPageModel new];
    self.model.sections = @[section];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"充电";
    [self prepareSettingsModel];
    [self mtInstallPreviewHeader];
    [self render];
}

#pragma mark - Preview

// 表头是设置框架既有的扩展点：预览放在最上方，先看效果再决定是否开启。
// 行类型只有链接/开关/说明三种，无法承载自定义绘制，故不新增行类型。
- (void)mtInstallPreviewHeader {
    MTPrefsChargingPreviewView *preview =
        [[MTPrefsChargingPreviewView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 0)];
    [preview setPreviewEnabled:MTChargingDetailsEnabled()];
    self.preview = preview;
    self.tableView.tableHeaderView = preview;
    [self mtSizePreviewHeader];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self mtSizePreviewHeader];
}

- (void)mtSizePreviewHeader {
    MTPrefsChargingPreviewView *preview = self.preview;
    if (!preview) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    CGFloat height = [MTPrefsChargingPreviewView heightForWidth:width];
    if (fabs(CGRectGetWidth(preview.frame) - width) < 0.5 && fabs(CGRectGetHeight(preview.frame) - height) < 0.5) return;
    preview.frame = CGRectMake(0, 0, width, height);
    [preview setNeedsLayout];
    // 表头高度不参与自动布局，赋值同一个视图是让 UITableView 重新量取的标准做法。
    self.tableView.tableHeaderView = preview;
}
@end
