#import "MTPrefsRootController.h"
#import "MTSettingsNavigation.h"
#import "MTPrefsRootModel.h"
#import "MTPrefsGlobalController.h"
#import "MTPrefsGlobalModel.h"
#import "MTPrefsChangelogModel.h"
#import "MTPrefsChangelogController.h"
#import "MTLog.h"

// 首页渲染：品牌头 + 卡片分区。模型与文案见 MTPrefsRootModel
// （宿主测试权威）；本文件只做 UIKit 传输（02 §8：系统 grouped 风格）。
// 导航栏右上角是「更新说明」入口：数据来自包内 Changelog.plist
// （MTPrefsChangelogModel），呈现为半屏 UISheetPresentationController。
@interface MTPrefsRootController ()
@end

@implementation MTPrefsRootController

- (void)prepareSettingsModel {
    if (self.model) return;
    self.model = [MTPrefsRootModel rootPageModel];
    [self mtAttachToggleHandler];
}

- (NSArray<NSString *> *)settingsPathComponents:(NSArray<NSString *> *)components {
    // QuickPrefs copies a row ID, rather than the complete ancestry. Keep the
    // standard category-global/... path and accept existing global-* shortcuts.
    if ([[MTPrefsGlobalModel globalPageModel] rowWithIdentifier:components.firstObject]) {
        return [@[@"category-global"] arrayByAddingObjectsFromArray:components];
    }
    return [super settingsPathComponents:components];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.backButtonTitle = @"Metis";
    [self prepareSettingsModel];
    [self mtInstallChangelogButton];
    [self render];
}

#pragma mark - Brand header

- (UIView *)makeTableHeaderView {
    // 品牌区和搜索框对齐系统分组边距；高度随标题/版本字号一起增长。
    UIView *container = [[UIView alloc] init];
    container.layoutMargins = self.tableView.layoutMargins;
    container.insetsLayoutMarginsFromSafeArea = NO;

    UIImageView *brandIcon = [[UIImageView alloc] initWithImage:[self mtBrandIconImage]];
    brandIcon.layer.cornerRadius = 12.0;
    brandIcon.layer.cornerCurve = kCACornerCurveContinuous;
    brandIcon.layer.masksToBounds = YES;
    brandIcon.contentMode = UIViewContentModeScaleAspectFit;
    brandIcon.isAccessibilityElement = NO;
    brandIcon.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *brandTitle = [[UILabel alloc] init];
    brandTitle.text = @"Metis";
    brandTitle.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle1]
        scaledFontForFont:[UIFont systemFontOfSize:28.0 weight:UIFontWeightBold]];
    brandTitle.textColor = UIColor.labelColor;
    brandTitle.adjustsFontForContentSizeCategory = YES;
    brandTitle.numberOfLines = 0;
    brandTitle.accessibilityTraits |= UIAccessibilityTraitHeader;

    UILabel *brandSubtitle = [[UILabel alloc] init];
    // 副标题带当前版本号：关于页移除后主页即版本信息的唯一展示位。
    brandSubtitle.text = MTCoreVersionString;
    brandSubtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    brandSubtitle.textColor = UIColor.secondaryLabelColor;
    brandSubtitle.adjustsFontForContentSizeCategory = YES;
    brandSubtitle.numberOfLines = 0;

    UIStackView *brandText = [[UIStackView alloc] initWithArrangedSubviews:@[brandTitle, brandSubtitle]];
    brandText.axis = UILayoutConstraintAxisVertical;
    brandText.alignment = UIStackViewAlignmentLeading;
    brandText.spacing = 2.0;

    UIStackView *brandRow = [[UIStackView alloc] initWithArrangedSubviews:@[brandIcon, brandText]];
    brandRow.axis = UILayoutConstraintAxisHorizontal;
    brandRow.alignment = UIStackViewAlignmentCenter;
    brandRow.spacing = 14.0;
    brandRow.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:brandRow];

    [NSLayoutConstraint activateConstraints:@[
        [brandRow.leadingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.leadingAnchor],
        [brandRow.trailingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.trailingAnchor],
        [brandRow.topAnchor constraintEqualToAnchor:container.topAnchor constant:8.0],
        [brandRow.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-24.0],
        [brandIcon.widthAnchor constraintEqualToConstant:56.0],
        [brandIcon.heightAnchor constraintEqualToConstant:56.0],
    ]];
    return container;
}

// 包内品牌图按屏幕倍率取最合适的一档。设置入口图（Metis.png 系列）已按
// PreferenceLoader 标准 29/58/87 缩小，与系统插件列表其他条目一致；页内
// 品牌头需要 56pt 展示，独立使用未缩放的 MetisBrand 系列，两者互不影响。
- (UIImage *)mtBrandIconImage {
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    CGFloat scale = self.view.window.screen.scale ?: UIScreen.mainScreen.scale ?: 2.0;
    for (NSNumber *candidate in @[@3.0, @2.0, @1.0]) {
        CGFloat candidateScale = candidate.doubleValue;
        if (candidateScale > scale && candidateScale != 1.0) continue;
        NSString *suffix = candidateScale == 3.0 ? @"@3x" : (candidateScale == 2.0 ? @"@2x" : @"");
        NSString *path = [bundle pathForResource:[NSString stringWithFormat:@"MetisBrand%@", suffix] ofType:@"png"];
        if (path) return [UIImage imageWithContentsOfFile:path];
    }
    NSString *fallback = [bundle pathForResource:@"MetisBrand" ofType:@"png"];
    return fallback ? [UIImage imageWithContentsOfFile:fallback] : nil;
}

#pragma mark - Model wiring

- (void)mtAttachToggleHandler {
    MTSettingsRow *toggle = [self.model rowWithIdentifier:@"global-enabled"];
    if (!toggle) return;
    __weak typeof(self) weakSelf = self;
    toggle.toggleHandler = ^(BOOL on) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        // 写入 + flush + gate reload 在模型层；随后重建模型刷新暂停提示行显隐。
        [MTPrefsRootModel setGlobalEnabled:on];
        strongSelf.model = [MTPrefsRootModel rootPageModel];
        [strongSelf mtAttachToggleHandler];
        [strongSelf render];
    };
}

#pragma mark - Changelog entry

// 右上角入口：44×44 热区 + 蓝色系统符号（与全库条目图标同色）。
// 不显示红点/未读态：标题里的「上一发布 → 当前发布」已表达增量，避免新增偏好键。
- (void)mtInstallChangelogButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:20.0
                                                        weight:UIImageSymbolWeightRegular];
    UIImage *symbol = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
    if (!symbol) symbol = [UIImage systemImageNamed:@"arrow.circlepath"];
    [button setImage:[symbol imageByApplyingSymbolConfiguration:configuration]
            forState:UIControlStateNormal];
    button.tintColor = UIColor.systemBlueColor;
    button.accessibilityLabel = @"更新说明";
    [button addTarget:self
               action:@selector(mtPresentChangelog:)
     forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
}

- (void)mtPresentChangelog:(id)sender {
    // 连点不叠层：半屏已在展示时直接忽略。
    if (self.presentedViewController) return;
    NSArray<MTChangelogEntry *> *entries = [MTPrefsChangelogModel entries];
    MTPrefsChangelogController *controller =
        [MTPrefsChangelogController controllerWithEntries:entries
                                                   title:[MTPrefsChangelogModel sheetTitleForEntries:entries]];
    [self mtConfigureChangelogSheetForController:controller];
    [self presentViewController:controller animated:YES completion:nil];
    MTLogInfo(MTLogModulePrefs, @"state=changelog-open entries=%lu",
              (unsigned long)entries.count);
}

// 0.72 自定义档 + large：首屏约 3 个版本，上拖全展开；iOS 15 退化为 medium/large。
- (void)mtConfigureChangelogSheetForController:(UIViewController *)controller {
    UISheetPresentationController *sheet = controller.sheetPresentationController;
    if (!sheet) return;
    sheet.prefersGrabberVisible = YES;
    sheet.preferredCornerRadius = 20.0;
    sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    if (@available(iOS 16.0, *)) {
        UISheetPresentationControllerDetent *compact = [UISheetPresentationControllerDetent
            customDetentWithIdentifier:@"MetisChangelogCompact"
                             resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return context.maximumDetentValue * 0.72;
        }];
        sheet.detents = @[compact, UISheetPresentationControllerDetent.largeDetent];
        sheet.selectedDetentIdentifier = @"MetisChangelogCompact";
    } else {
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                          UISheetPresentationControllerDetent.largeDetent];
    }
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    self.tableView.tableHeaderView.layoutMargins = self.tableView.layoutMargins;
    [super viewDidLayoutSubviews];
}
@end
