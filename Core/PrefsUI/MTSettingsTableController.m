#import "MTSettingsTableController.h"
#import "MTSettingsRowCell.h"
#import "MTSettingsNavigation.h"

// 大标题样式与系统设置一致；被宿主（Settings.app / PreferenceLoader）压栈时
// 导航条已存在，这里只声明本页需要大标题，不改宿主全局行为。
@implementation MTSettingsTableController {
    UILabel *_introLabel;
    UIView *_tableFooter;
    UILabel *_footerLabel;
}

// 所有构造路径统一收敛到 inset grouped（设计稿卡片风格）；mtCommonInit
// 只在 viewDidLoad 做，避免 init 期触碰 self.tableView 触发提前 loadView。
// 说明：UITableViewController 自身就以 initWithStyle: 收敛 initWithNibName 链，
// 这里的转发模式与之相同；对 clang 的 DI 链检查局部豁免。
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (instancetype)init {
    return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}
#pragma clang diagnostic pop

- (void)viewDidLoad {
    [super viewDidLoad];
    [self mtCommonInit];
}

- (void)mtCommonInit {
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self.tableView registerClass:[MTSettingsRowCell class] forCellReuseIdentifier:@"MTSettingsRowCell"];
    self.tableView.separatorInsetReference = UITableViewSeparatorInsetFromCellEdges;
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

- (MTSettingsPageModel *)displayedModel {
    return self.overlayModel ?: self.model;
}

- (void)render {
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
    Class controllerClass = nil;
    if (row.routeKind == MTSettingsRouteShellClass) {
        controllerClass = row.className.length ? NSClassFromString(row.className) : Nil;
    }
    // Subbundle 路由需要加载外部 bundle：由 Shell 侧子类（MTPrefsShellTableController）
    // 覆写补齐；基础层无法感知子包布局，这里不猜测路径。
    if (!controllerClass) return;
    id controller = [[controllerClass alloc] init];
    MTSettingsPushController(self, controller, nil, YES);
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
