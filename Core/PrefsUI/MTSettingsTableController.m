#import "MTSettingsTableController.h"
#import "MTSettingsRowCell.h"
#import "MTSettingsNavigation.h"
#import "MTSettingsSpecifierBridge.h"
#import <Preferences/PSSpecifier.h>
#import "MTLog.h"
#import <objc/message.h>

// The bundled Theos header exposes only the legacy notification selector.
// iOS 16/17 PSListController dispatches through this completion-bearing entry.
@interface PSListController (MTSettingsURLCompletionCompatibility)
- (void)handleURL:(id)url withCompletion:(void (^)(void))completion;
@end

@interface MTSettingsTableController ()
@property (nonatomic, copy) NSDictionary *mtPendingSettingsURL;
@property (nonatomic, copy) void (^mtPendingSettingsURLCompletion)(void);
@property (nonatomic) BOOL mtOwnsSettingsURL;
// 栈锚点：本页为某条路径压出的子控制器（URL 直达与行点按共用）。
// 锚点描述导航栈的事实而非某次投递：只要锚定子控制器还在栈内，
// 同目标的重复投递一律不再次压栈；子控制器出栈后惰性释放。
@property (nonatomic, copy) NSString *mtRoutedPath;
@property (nonatomic, weak) PSViewController *mtRoutedChildController;
// Back 露出本页的外观过渡期：期间到达的同目标投递（含超类生命周期重放）丢弃。
@property (nonatomic) BOOL mtReturningFromChild;
@end

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
    if (self.mtRoutedPath.length && !self.mtPendingSettingsURL &&
        self.navigationController.topViewController == self) {
        self.mtReturningFromChild = YES;
    }
    // PSListController also keeps its own deferred URL. Clear it before the
    // superclass gets a chance to replay it when Back reveals this page.
    if (self.mtOwnsSettingsURL) [self mtClearNativePendingSettingsURL];
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
    [self prepareSettingsModel];
    if (!_specifiers) _specifiers = [self mtBuildSpecifiers];
    return _specifiers;
}

- (void)prepareSettingsModel {}

#pragma mark - Preferences URL routing

- (void)mtClearNativePendingSettingsURL {
    SEL clear = NSSelectorFromString(@"clearPendingURL");
    if ([self respondsToSelector:clear]) ((void (*)(id, SEL))objc_msgSend)(self, clear);
    // Explicitly clear both queues as well: framework implementations differ
    // in which fields clearPendingURL resets. Do not clear the current page ID.
    for (NSString *name in @[@"setPendingURLResourceDictionary:", @"setSpecifierIDPendingPush:"]) {
        SEL setter = NSSelectorFromString(name);
        if ([self respondsToSelector:setter]) ((void (*)(id, SEL, id))objc_msgSend)(self, setter, nil);
    }
}

- (NSArray<NSString *> *)settingsPathComponents:(NSArray<NSString *> *)components {
    return components;
}

// Preferences normally passes a resource dictionary. Accept NSURL too, as the
// Theos compatibility header uses that type (including opaque prefs:root= URLs).
- (NSDictionary *)mtSettingsResourcesForURL:(id)url {
    if ([url isKindOfClass:NSDictionary.class]) return url;
    if (![url isKindOfClass:NSURL.class]) return nil;
    NSString *query = [url query];
    if (!query.length) query = [url resourceSpecifier];
    NSMutableDictionary *resources = [NSMutableDictionary dictionary];
    for (NSString *item in [query componentsSeparatedByString:@"&"]) {
        NSRange separator = [item rangeOfString:@"="];
        if (separator.location == NSNotFound) continue;
        NSString *key = [[item substringToIndex:separator.location] stringByRemovingPercentEncoding];
        NSString *value = [[item substringFromIndex:separator.location + 1] stringByRemovingPercentEncoding];
        if (key && value) resources[key] = value;
    }
    return resources;
}

- (void)handleURL:(id)url {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self handleURL:url]; });
        return;
    }
    if (![self mtHandleSettingsURL:url completion:nil]) [super handleURL:url];
}

- (void)handleURL:(id)url withCompletion:(void (^)(void))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self handleURL:url withCompletion:completion]; });
        return;
    }
    MTLogInfo(MTLogModulePrefs, @"state=settings-url-entry source=%@ instance=%p modern=1",
              NSStringFromClass(self.class), (__bridge void *)self);
    // Do not enter PSURLControllerHandler for a model route: that handler
    // invokes handleURL: as a notification, then continues native navigation.
    // Overriding only the notification lets native and custom pushes coexist.
    if ([self mtHandleSettingsURL:url completion:completion]) return;
    if ([PSListController instancesRespondToSelector:@selector(handleURL:withCompletion:)]) {
        [super handleURL:url withCompletion:completion];
    } else {
        [super handleURL:url];
        if (completion) completion();
    }
}

- (BOOL)mtHandleSettingsURL:(id)url completion:(void (^)(void))completion {
    NSDictionary *resources = [self mtSettingsResourcesForURL:url];
    id path = resources[@"path"];
    if (![path isKindOfClass:NSString.class] || ![path length]) {
        [self mtReleaseSettingsURL];
        return NO;
    }
    NSArray<NSString *> *components = [self settingsPathComponents:[path componentsSeparatedByString:@"/"]];
    [self prepareSettingsModel];
    MTSettingsRow *row = [self.model rowWithIdentifier:components.firstObject];
    if (!row || [components containsObject:@""]) {
        [self mtReleaseSettingsURL];
        return NO;
    }
    // Resolve against the persistent model, never search-result specifiers.
    self.mtOwnsSettingsURL = YES;
    [self mtClearNativePendingSettingsURL];
    NSString *canonicalPath = [components componentsJoinedByString:@"/"];
    [self mtDropRoutingAnchorIfUnstacked];
    MTLogInfo(MTLogModulePrefs, @"state=settings-url-request source=%@ anchored=%@ in-stack=%d returning=%d",
              NSStringFromClass(self.class), self.mtRoutedPath, self.mtRoutedChildController != nil,
              self.mtReturningFromChild);
    // Settings can redeliver a URL whose target this page already pushed.
    // While the anchored child is still in the stack the delivery is dropped,
    // no matter whether this page is visible or mid-return: re-queueing would
    // fire on Back and stack a second instance. A strict prefix targets an
    // ancestor that is already open and is dropped for the same reason.
    // The anchored child may already be deallocated while its Back transition
    // is still running (weak reference nils before the transition ends); the
    // return-transition flag keeps those deliveries suppressed as well.
    BOOL anchorLive = self.mtRoutedChildController != nil &&
        [self.navigationController.viewControllers containsObject:self.mtRoutedChildController];
    if (self.mtRoutedPath.length && (anchorLive || self.mtReturningFromChild)) {
        BOOL sameTarget = [canonicalPath isEqualToString:self.mtRoutedPath];
        BOOL targetsAncestor = [self mtPath:canonicalPath isComponentPrefixOfPath:self.mtRoutedPath];
        BOOL extendsAnchor = [self mtPath:self.mtRoutedPath isComponentPrefixOfPath:canonicalPath];
        if (sameTarget || targetsAncestor || (extendsAnchor && !anchorLive)) {
            MTLogInfo(MTLogModulePrefs, @"state=settings-url-duplicate-consumed source=%@ reason=%@",
                      NSStringFromClass(self.class),
                      sameTarget ? @"self" : (targetsAncestor ? @"ancestor" : @"transition"));
            if (completion) completion();
            return YES;
        }
        if (extendsAnchor) {
            // The anchored child is already open: hand it the deeper path
            // instead of stacking a second instance of it.
            MTLogInfo(MTLogModulePrefs, @"state=settings-url-extend-open source=%@ target=%@",
                      NSStringFromClass(self.class), self.mtRoutedPath);
            [self mtForwardPath:resources toComponents:components controller:self.mtRoutedChildController
                     completion:completion];
            return YES;
        }
    }
    self.mtReturningFromChild = NO;
    self.overlayModel = nil;
    NSMutableDictionary *pending = [resources mutableCopy];
    pending[@"path"] = canonicalPath;
    void (^supersededCompletion)(void) = self.mtPendingSettingsURLCompletion;
    self.mtPendingSettingsURL = pending;
    self.mtPendingSettingsURLCompletion = completion;
    // Coalesce repeated delivery and let Settings finish attaching the page.
    dispatch_async(dispatch_get_main_queue(), ^{ [self mtOpenPendingSettingsURL]; });
    // A superseded request is settled once; the latest request owns the queue.
    if (supersededCompletion) supersededCompletion();
    return YES;
}

- (void)viewDidAppear:(BOOL)animated {
    if (self.mtOwnsSettingsURL) [self mtClearNativePendingSettingsURL];
    BOOL hadPendingRequest = self.mtPendingSettingsURL != nil;
    [super viewDidAppear:animated];
    [self mtOpenPendingSettingsURL];
    // A pure return (no request opened on the way back) ends the routed
    // lifetime: the anchor is released so a fresh delivery of the same URL
    // opens the page again, without a timeout or cooldown.
    if (self.mtReturningFromChild && self.navigationController.topViewController == self && self.view.window) {
        MTLogInfo(MTLogModulePrefs, @"state=settings-url-return-complete source=%@", NSStringFromClass(self.class));
        self.mtReturningFromChild = NO;
        if (!hadPendingRequest) [self mtReleaseRoutingAnchor];
    }
}

// 交给超类原生的投递只归还队列所有权；栈锚点是导航栈的事实，
// 不随单次投递失效（锚定子控制器出栈时才惰性释放）。
- (void)mtReleaseSettingsURL {
    void (^completion)(void) = self.mtPendingSettingsURLCompletion;
    self.mtPendingSettingsURLCompletion = nil;
    self.mtPendingSettingsURL = nil;
    self.mtOwnsSettingsURL = NO;
    if (completion) completion();
}

/// 压栈后由 URL 直达与行点按共同调用的锚点记录（Shell 子包路由亦经此登记）。
- (void)mtRecordRoutingAnchorForController:(PSViewController *)controller path:(NSString *)path {
    self.mtRoutedChildController = controller;
    self.mtRoutedPath = path;
}

- (void)mtReleaseRoutingAnchor {
    self.mtRoutedChildController = nil;
    self.mtRoutedPath = nil;
}

- (void)mtDropRoutingAnchorIfUnstacked {
    if (self.mtReturningFromChild) return;
    PSViewController *child = self.mtRoutedChildController;
    if (!child) {
        self.mtRoutedPath = nil;
        return;
    }
    if (![self.navigationController.viewControllers containsObject:child]) {
        [self mtReleaseRoutingAnchor];
    }
}

// Component-boundary prefix: "a/b" prefixes "a/b/c" but not "a/bc".
- (BOOL)mtPath:(NSString *)prefix isComponentPrefixOfPath:(NSString *)path {
    if (prefix.length >= path.length || ![path hasPrefix:prefix]) return NO;
    return [path characterAtIndex:prefix.length] == '/';
}

// 把除首段外的剩余子路径按 Preferences 资源字典转发给目标控制器。
- (void)mtForwardPath:(NSDictionary *)resources toComponents:(NSArray<NSString *> *)components
             controller:(PSViewController *)controller completion:(void (^)(void))completion {
    if (components.count < 2 || !controller) {
        if (completion) completion();
        return;
    }
    NSMutableDictionary *remaining = [resources mutableCopy];
    remaining[@"path"] = [[components subarrayWithRange:NSMakeRange(1, components.count - 1)]
        componentsJoinedByString:@"/"];
    SEL modern = @selector(handleURL:withCompletion:);
    if ([controller respondsToSelector:modern]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(controller, modern, remaining, completion);
    } else {
        if ([controller respondsToSelector:@selector(handleURL:)]) [controller handleURL:(id)remaining];
        if (completion) completion();
    }
}

- (void)mtOpenPendingSettingsURL {
    NSDictionary *resources = self.mtPendingSettingsURL;
    if (!resources || self.navigationController.topViewController != self || !self.view.window) return;
    void (^completion)(void) = self.mtPendingSettingsURLCompletion;
    self.mtPendingSettingsURLCompletion = nil;
    self.mtPendingSettingsURL = nil;
    [self mtClearNativePendingSettingsURL];
    NSArray<NSString *> *components = [resources[@"path"] componentsSeparatedByString:@"/"];
    MTSettingsRow *row = [self.model rowWithIdentifier:components.firstObject];
    if (!row) {
        if (completion) completion();
        return;
    }
    [self render];
    if (row.kind != MTSettingsRowKindLink || row.routeKind == MTSettingsRouteNone ||
        row.routeKind == MTSettingsRouteInPage) {
        // A URL to a switch/setting locates it; it must never execute a toggle.
        if (components.count == 1) [self flashRowWithIdentifier:row.identifier];
        if (completion) completion();
        return;
    }
    Class controllerClass = [self controllerClassForSettingsRow:row];
    if (!controllerClass || ![controllerClass isSubclassOfClass:PSViewController.class]) {
        MTLogError(MTLogModulePrefs, @"state=settings-url-route-unavailable");
        if (completion) completion();
        return;
    }
    PSViewController *controller = [[controllerClass alloc] init];
    [self mtRecordRoutingAnchorForController:controller path:resources[@"path"]];
    MTSettingsPushController(self, controller, [self specifierForID:row.identifier], NO);
    MTLogInfo(MTLogModulePrefs, @"state=settings-url-route-open source=%@ target=%@ remaining=%lu",
              NSStringFromClass(self.class), NSStringFromClass(controllerClass), (unsigned long)(components.count - 1));
    // Non-model PSListController children keep their native path handling.
    [self mtForwardPath:resources toComponents:components controller:controller completion:completion];
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
    PSViewController *controller = [[controllerClass alloc] init];
    // 点按与 URL 直达共用锚点：页面已开时同目标 URL 投递不得重复压栈。
    [self mtRecordRoutingAnchorForController:controller path:row.identifier];
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
