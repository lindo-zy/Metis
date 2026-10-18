#import "MTPrefsRootController.h"
#import "MTPrefsRootModel.h"
#import "MTPrefsSearchIndex.h"
#import "MTPrefsGlobalController.h"
#import "MTLog.h"

// 首页渲染：品牌头 + 搜索设置 + 卡片分区。模型与文案见 MTPrefsRootModel
// （宿主测试权威）；本文件只做 UIKit 传输（02 §8：系统 grouped 风格）。
@interface MTPrefsRootController () <UISearchBarDelegate>
@end

@implementation MTPrefsRootController {
    UISearchBar *_searchBar;
    BOOL _searchActive;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Metis";
    self.model = [MTPrefsRootModel rootPageModel];
    [self mtAttachToggleHandler];
    [self render];
}

#pragma mark - Brand header + search

- (UIView *)makeTableHeaderView {
    // 设计稿头部：Metis 图标（包内 Metis.png）+「统一的效率工具」，下方搜索框。
    UIView *container = [[UIView alloc] init];

    UIImageView *brandIcon = [[UIImageView alloc] initWithImage:[self mtBrandIconImage]];
    brandIcon.layer.cornerRadius = 12.0;
    brandIcon.layer.cornerCurve = kCACornerCurveContinuous;
    brandIcon.layer.masksToBounds = YES;
    brandIcon.contentMode = UIViewContentModeScaleAspectFit;
    brandIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:brandIcon];

    UILabel *brandSubtitle = [[UILabel alloc] init];
    // 副标题带当前版本号：关于页移除后主页即版本信息的唯一展示位。
    brandSubtitle.text = [NSString stringWithFormat:@"统一的效率工具 · %@", MTCoreVersionString];
    brandSubtitle.font = [UIFont systemFontOfSize:15.0];
    brandSubtitle.textColor = UIColor.secondaryLabelColor;
    brandSubtitle.adjustsFontForContentSizeCategory = YES;
    brandSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:brandSubtitle];

    _searchBar = [[UISearchBar alloc] init];
    _searchBar.placeholder = @"搜索设置";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.delegate = self;
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_searchBar];

    [NSLayoutConstraint activateConstraints:@[
        [brandIcon.leadingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.leadingAnchor],
        [brandIcon.topAnchor constraintEqualToAnchor:container.topAnchor constant:6.0],
        [brandIcon.widthAnchor constraintEqualToConstant:56.0],
        [brandIcon.heightAnchor constraintEqualToConstant:56.0],
        [brandSubtitle.leadingAnchor constraintEqualToAnchor:brandIcon.trailingAnchor constant:14.0],
        [brandSubtitle.centerYAnchor constraintEqualToAnchor:brandIcon.centerYAnchor],
        [brandSubtitle.trailingAnchor constraintLessThanOrEqualToAnchor:container.layoutMarginsGuide.trailingAnchor],
        [_searchBar.topAnchor constraintEqualToAnchor:brandIcon.bottomAnchor constant:12.0],
        [_searchBar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_searchBar.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_searchBar.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4.0],
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

#pragma mark - Search

- (void)mtApplySearchQuery:(NSString *)query {
    NSArray<MTSettingsSearchEntry *> *entries = [MTPrefsSearchIndex entriesMatchingQuery:query];
    NSMutableArray<MTSettingsRow *> *rows = [NSMutableArray array];
    [entries enumerateObjectsUsingBlock:^(MTSettingsSearchEntry *entry, NSUInteger index, BOOL *stop) {
        MTSettingsRow *row = [MTSettingsRow linkRowWithIdentifier:[NSString stringWithFormat:@"search-result-%lu", (unsigned long)index]
                                                            title:entry.title];
        row.subtitle = entry.path;
        row.userInfo = entry;
        [rows addObject:row];
    }];
    if (!rows.count) {
        MTSettingsRow *empty = [MTSettingsRow linkRowWithIdentifier:@"search-empty" title:@"无搜索结果"];
        empty.kind = MTSettingsRowKindInfo;
        empty.subtitle = @"仅检索设置标题与资源名称";
        rows = [NSMutableArray arrayWithObject:empty];
    }
    MTSettingsSection *section = [MTSettingsSection sectionWithRows:rows];
    MTSettingsPageModel *overlay = [[MTSettingsPageModel alloc] init];
    overlay.sections = @[section];
    self.overlayModel = overlay;
    [self render];
}

- (void)mtExitSearch {
    if (!_searchActive && self.overlayModel == nil) return;
    _searchActive = NO;
    self.overlayModel = nil;
    [self render];
}

- (void)settingsRowSelected:(MTSettingsRow *)row {
    MTSettingsSearchEntry *entry = [row.userInfo isKindOfClass:MTSettingsSearchEntry.class] ? row.userInfo : nil;
    if (!entry) {
        [super settingsRowSelected:row];
        return;
    }
    MTSettingsRow *target = entry.target;
    if (target.routeKind == MTSettingsRouteInPage) {
        [self mtExitSearch];
        [self flashRowWithIdentifier:[target.userInfo isKindOfClass:NSString.class] ? target.userInfo : target.identifier];
        return;
    }
    if (target.routeKind == MTSettingsRouteShellClass) {
        Class controllerClass = target.className.length ? NSClassFromString(target.className) : Nil;
        if (!controllerClass) return;
        id controller = [[controllerClass alloc] init];
        // Shell 内模型驱动页支持行级强调；PS 页（其他分类）自然忽略该属性。
        if ([controller respondsToSelector:@selector(setPendingFocusIdentifier:)]) {
            [(MTSettingsTableController *)controller setPendingFocusIdentifier:
                [target.userInfo isKindOfClass:NSString.class] ? target.userInfo : nil];
        }
        [self.navigationController pushViewController:controller animated:YES];
        return;
    }
    // 子包目标（资源名称）：退出搜索后按原始路由压栈。
    [self mtExitSearch];
    [self performRouteForRow:target];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    _searchActive = YES;
    searchBar.showsCancelButton = YES;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length) [self mtApplySearchQuery:searchText];
    else [self mtExitSearch];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [searchBar resignFirstResponder];
    [self mtExitSearch];
}

@end
