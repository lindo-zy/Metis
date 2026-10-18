#import "MTSettingsTableController.h"
#import "MTSettingsRowCell.h"
#import "MTSettingsNavigation.h"
#import "MTSettingsSpecifierBridge.h"
#import <Preferences/PSSpecifier.h>

// 大标题样式与系统设置一致；被宿主（Settings.app / PreferenceLoader）压栈时
// 导航条已存在，这里只声明本页需要大标题，不改宿主全局行为。
@implementation MTSettingsTableController {
    UILabel *_introLabel;
    UIView *_tableFooter;
    UILabel *_footerLabel;
}

// 由 PSListController 创建并持有真实的 _table。QuickPrefs 在此父类的
// viewDidAppear: 上安装长按手势；另建 UIKit 表格会让手势落在不可见表格上。
- (UITableViewStyle)tableViewStyle {
    return UITableViewStyleInsetGrouped;
}

// iOS 16.1 的 PSListController 只提供 table；Theos 头文件中的 tableView
// 声明不保证运行时实现。保留 UIKit 风格访问器，但始终使用 Preferences
// 持有的同一张表，供首页、全局页和 QuickPrefs 的长按路径共同使用。
- (UITableView *)tableView {
    return [self table];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self mtCommonInit];
}

- (void)mtCommonInit {
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self.tableView registerClass:[MTSettingsRowCell class] forCellReuseIdentifier:@"MTSettingsRowCell"];
    self.tableView.separatorInsetReference = UITableViewSeparatorInsetFromCellEdges;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56.0;
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 0.0;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    if (self.pendingFocusIdentifier.length) {
        NSString *focus = self.pendingFocusIdentifier;
        self.pendingFocusIdentifier = nil;
        [self flashRowWithIdentifier:focus];
    }
}

#pragma mark - Model rendering

// 不尝试载入不存在的 Root.plist。分组顺序与自定义 datasource 完全一致，
// 使 Preferences 的 specifierForID:/indexPathForSpecifier:/URL 路由可直接使用。
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self mtBuildSpecifiers];
    return _specifiers;
}

- (NSMutableArray *)mtBuildSpecifiers {
    return MTSettingsBuildSpecifiers(self.displayedModel, self, self.overlayModel == nil,
        ^Class(MTSettingsRow *row) { return [self controllerClassForSettingsRow:row]; });
}

- (id)mtReadRowValue:(PSSpecifier *)specifier {
    MTSettingsRow *row = [self.displayedModel rowWithIdentifier:specifier.identifier];
    return row.kind == MTSettingsRowKindToggle ? row.userInfo : nil;
}

- (void)mtSetRowValue:(id)value specifier:(PSSpecifier *)specifier {
    MTSettingsRow *row = [self.displayedModel rowWithIdentifier:specifier.identifier];
    if (row.kind == MTSettingsRowKindToggle && row.toggleHandler) row.toggleHandler([value boolValue]);
}

- (MTSettingsPageModel *)displayedModel {
    return self.overlayModel ?: self.model;
}

- (void)render {
    self.specifiers = [self mtBuildSpecifiers];
    if (!_introLabel) _introLabel = [[UILabel alloc] init];
    _introLabel.text = self.displayedModel.introSubtitle;
    if (!self.tableView.tableHeaderView) {
        UIView *header = [self makeTableHeaderView];
        if (header) self.tableView.tableHeaderView = header;
    }
    [self applyFooterText];
    [self.tableView reloadData];
}

- (nullable UIView *)makeTableHeaderView {
    if (!self.displayedModel.introSubtitle.length) return nil;
    if (!_introLabel) {
        _introLabel = [[UILabel alloc] init];
        _introLabel.font = [UIFont systemFontOfSize:15.0];
        _introLabel.textColor = UIColor.secondaryLabelColor;
        _introLabel.adjustsFontForContentSizeCategory = YES;
        _introLabel.translatesAutoresizingMaskIntoConstraints = NO;
    }
    UIView *container = [[UIView alloc] init];
    [container addSubview:_introLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_introLabel.leadingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.leadingAnchor],
        [_introLabel.trailingAnchor constraintLessThanOrEqualToAnchor:container.layoutMarginsGuide.trailingAnchor],
        [_introLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:2.0],
        [_introLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-6.0],
    ]];
    return container;
}

- (void)applyFooterText {
    NSString *text = self.displayedModel.footerText;
    if (!_tableFooter) {
        _tableFooter = [[UIView alloc] init];
        _footerLabel = [[UILabel alloc] init];
        _footerLabel.font = [UIFont systemFontOfSize:13.0];
        _footerLabel.textColor = UIColor.secondaryLabelColor;
        _footerLabel.numberOfLines = 0;
        _footerLabel.adjustsFontForContentSizeCategory = YES;
        _footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_tableFooter addSubview:_footerLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_footerLabel.leadingAnchor constraintEqualToAnchor:_tableFooter.layoutMarginsGuide.leadingAnchor],
            [_footerLabel.trailingAnchor constraintEqualToAnchor:_tableFooter.layoutMarginsGuide.trailingAnchor],
            [_footerLabel.topAnchor constraintEqualToAnchor:_tableFooter.topAnchor constant:8.0],
            [_footerLabel.bottomAnchor constraintEqualToAnchor:_tableFooter.bottomAnchor constant:-16.0],
        ]];
    }
    _footerLabel.text = text;
    _tableFooter.hidden = (text.length == 0);
    self.tableView.tableFooterView = text.length ? _tableFooter : nil;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // tableHeaderView 高度按内容自适应（Auto Layout 布局的头视图不会自动更新）。
    UIView *header = self.tableView.tableHeaderView;
    if (!header) return;
    CGSize fitting = [header systemLayoutSizeFittingSize:
        CGSizeMake(CGRectGetWidth(self.tableView.bounds), CGFLOAT_MAX)
        withHorizontalFittingPriority:UILayoutPriorityRequired
             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGRect frame = header.frame;
    if ((NSInteger)frame.size.height != (NSInteger)fitting.height || (NSInteger)frame.size.width != (NSInteger)CGRectGetWidth(self.tableView.bounds)) {
        frame.size.height = fitting.height;
        frame.size.width = CGRectGetWidth(self.tableView.bounds);
        header.frame = frame;
        self.tableView.tableHeaderView = header;
    }
}

#pragma mark - UITableViewDataSource / Delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.displayedModel.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.displayedModel.sections.count) return 0;
    return self.displayedModel.sections[section].rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self rowSectionAt:section].headerTitle;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [self rowSectionAt:section].footerText;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MTSettingsRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MTSettingsRowCell" forIndexPath:indexPath];
    MTSettingsRow *row = [self rowAtIndexPath:indexPath];
    if (row) [cell configureWithRow:row];
    cell.specifier = [self specifierAtIndexPath:indexPath];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    MTSettingsRow *row = [self rowAtIndexPath:indexPath];
    if (!row) return;
    [self settingsRowSelected:row];
}

#pragma mark - Rows / routes

- (MTSettingsSection *)rowSectionAt:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.displayedModel.sections.count) return nil;
    return self.displayedModel.sections[section];
}

- (MTSettingsRow *)rowAtIndexPath:(NSIndexPath *)indexPath {
    MTSettingsSection *section = [self rowSectionAt:indexPath.section];
    if (!section || indexPath.row < 0 || indexPath.row >= (NSInteger)section.rows.count) return nil;
    return section.rows[indexPath.row];
}

- (NSString *)introSubtitleText {
    return self.displayedModel.introSubtitle;
}

- (void)settingsRowSelected:(MTSettingsRow *)row {
    if (row.kind != MTSettingsRowKindLink) return;
    [self performRouteForRow:row];
}

- (void)performRouteForRow:(MTSettingsRow *)row {
    if (row.routeKind == MTSettingsRouteInPage) {
        if (row.identifier.length) [self flashRowWithIdentifier:row.identifier];
        return;
    }
    if (row.routeKind == MTSettingsRouteNone) return;
    Class controllerClass = [self controllerClassForSettingsRow:row];
    if (!controllerClass) return;
    id controller = [[controllerClass alloc] init];
    MTSettingsPushController(self, controller, [self specifierForID:row.identifier], YES);
}

- (Class)controllerClassForSettingsRow:(MTSettingsRow *)row {
    if (row.routeKind != MTSettingsRouteShellClass || !row.className.length) return Nil;
    return NSClassFromString(row.className);
}

- (void)flashRowWithIdentifier:(NSString *)identifier {
    if (!identifier.length) return;
    MTSettingsPageModel *displayed = self.displayedModel;
    NSInteger section = -1, row = -1;
    for (NSInteger s = 0; s < (NSInteger)displayed.sections.count; s++) {
        NSArray<MTSettingsRow *> *rows = displayed.sections[s].rows;
        for (NSInteger r = 0; r < (NSInteger)rows.count; r++) {
            if ([rows[r].identifier isEqualToString:identifier]) { section = s; row = r; break; }
        }
        if (section >= 0) break;
    }
    if (section < 0) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
    [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    // 目标行可能尚未渲染（刚进入页面/滚动动画中）：立即试一次，再延迟补一次。
    [self mtPulseCellAtIndexPath:indexPath];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self isViewLoaded] && self.view.window) [self mtPulseCellAtIndexPath:indexPath];
    });
}

- (void)mtPulseCellAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (!cell) return;
    [UIView animateWithDuration:0.15 animations:^{ cell.alpha = 0.25; }
                     completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.35 animations:^{ cell.alpha = 1.0; }];
    }];
}

@end
