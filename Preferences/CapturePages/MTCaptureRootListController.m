#import "MTCaptureRootListController.h"
#import "../../Modules/Capture/Sources/Common/MTConstants.h"
#import "../../Modules/Capture/Sources/Common/MTCaptureLog.h"

@interface MTCaptureRootListController ()
@property (nonatomic, assign) NSInteger copyFeedbackGeneration;
@property (nonatomic, strong) UIView *brandingHeader;
@end

@implementation MTCaptureRootListController

- (UITableView *)mtSettingsTable {
    if ([self respondsToSelector:@selector(tableView)]) return self.tableView;
    if ([self respondsToSelector:@selector(table)]) return self.table;
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UITableView *table = [self mtSettingsTable];
    if (!table) {
        MTCaptureLogWarn(@"prefs branding header skipped: table unavailable");
        return;
    }
    NSBundle *bundle = [NSBundle bundleForClass:[MTCaptureRootListController class]];
    NSString *imagePath = [bundle pathForResource:@"CaptureHeader" ofType:@"png"];
    UIImage *logo = imagePath.length ? [UIImage imageWithContentsOfFile:imagePath] : nil;
    if (!logo) {
        MTCaptureLogWarn(@"prefs branding logo missing; using bundle icon");
        logo = [UIImage imageNamed:@"MetisCapture" inBundle:bundle compatibleWithTraitCollection:self.traitCollection];
    }
    id versionValue = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *version = [versionValue isKindOfClass:NSString.class] ? versionValue : nil;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(table.bounds), 270)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = UIColor.clearColor;
    self.brandingHeader = header;

    // 独立阴影容器保留 Logo 的透明圆角，避免裁掉阴影。
    UIView *iconContainer = [[UIView alloc] init];
    iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
    iconContainer.layer.shadowColor = UIColor.blackColor.CGColor;
    iconContainer.layer.shadowOpacity = 0.25;
    iconContainer.layer.shadowRadius = 12;
    iconContainer.layer.shadowOffset = CGSizeMake(0, 6);
    [header addSubview:iconContainer];
    UIImageView *imageView = [[UIImageView alloc] initWithImage:logo];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.isAccessibilityElement = NO;
    [iconContainer addSubview:imageView];

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = @"MetisCapture";
    UIFontDescriptor *rounded = [[UIFont systemFontOfSize:36 weight:UIFontWeightRegular].fontDescriptor
        fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    nameLabel.font = rounded ? [UIFont fontWithDescriptor:rounded size:36] : [UIFont systemFontOfSize:36];
    nameLabel.textColor = UIColor.labelColor;
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.adjustsFontSizeToFitWidth = YES;
    nameLabel.minimumScaleFactor = 0.7;
    nameLabel.accessibilityTraits |= UIAccessibilityTraitHeader;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:nameLabel];

    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = version.length ? [NSString stringWithFormat:@"版本 %@", version] : @"版本未知";
    versionLabel.font = [UIFont systemFontOfSize:14];
    versionLabel.textColor = UIColor.secondaryLabelColor;
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.adjustsFontSizeToFitWidth = YES;
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:versionLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconContainer.topAnchor constraintEqualToAnchor:header.topAnchor constant:28],
        [iconContainer.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [iconContainer.widthAnchor constraintEqualToConstant:134],
        [iconContainer.heightAnchor constraintEqualToConstant:134],
        [imageView.topAnchor constraintEqualToAnchor:iconContainer.topAnchor],
        [imageView.bottomAnchor constraintEqualToAnchor:iconContainer.bottomAnchor],
        [imageView.leadingAnchor constraintEqualToAnchor:iconContainer.leadingAnchor],
        [imageView.trailingAnchor constraintEqualToAnchor:iconContainer.trailingAnchor],
        [nameLabel.topAnchor constraintEqualToAnchor:iconContainer.bottomAnchor constant:10],
        [nameLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [nameLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [nameLabel.heightAnchor constraintEqualToConstant:48],
        [versionLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:2],
        [versionLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [versionLabel.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor],
        [versionLabel.heightAnchor constraintEqualToConstant:22],
    ]];
    table.tableHeaderView = header;
    MTCaptureLogInfo(@"prefs branding header loaded: version=%@", version.length ? version : @"unknown");
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UITableView *table = [self mtSettingsTable];
    UIView *header = self.brandingHeader;
    CGFloat width = CGRectGetWidth(table.bounds);
    if (header && width > 0 && CGRectGetWidth(header.bounds) != width) {
        CGRect frame = header.frame;
        frame.size.width = width;
        header.frame = frame;
        table.tableHeaderView = header;
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        _specifiers = [self mtSpecifiersWithURLSchemeEntry];
    }
    return _specifiers;
}

// plist 加载器不会实例化自定义 cellClass（真机上条目缺动作且显示不全），
// 外部入口使用 PSButtonCell + buttonAction，在代码中构建并插入分组之后。
- (NSMutableArray *)mtSpecifiersWithURLSchemeEntry {
    NSMutableArray *items = [_specifiers mutableCopy];
    NSUInteger insertIndex = items.count;
    PSSpecifier *group = [self mtExternalEntryGroupIn:items];
    if (group) insertIndex = [items indexOfObject:group] + 1;
    for (PSSpecifier *specifier in [self mtCaptureURLSchemeSpecifiers]) {
        [items insertObject:specifier atIndex:insertIndex];
        insertIndex++;
    }
    return items;
}

- (PSSpecifier *)mtExternalEntryGroupIn:(NSArray *)specifiers {
    for (PSSpecifier *spec in specifiers) {
        if ([spec.name isEqualToString:@"外部入口"]) return spec;
    }
    return nil;
}

// 测试入口直发 Darwin 通知（外部 URL scheme 已移除）；名称与 SB 入口注册表一致。
- (NSArray<NSArray<NSString *> *> *)mtSchemeEntries {
    return @[
        @[@"启动（区域截图）", (__bridge NSString *)MTDarwinActivate],
        @[@"全屏截图", (__bridge NSString *)MTDarwinCaptureFull],
        @[@"区域截图", (__bridge NSString *)MTDarwinCaptureArea],
        @[@"全屏标记", (__bridge NSString *)MTDarwinCaptureMarkup],
        @[@"滚动截图", (__bridge NSString *)MTDarwinCaptureLong],
    ];
}

- (NSArray<PSSpecifier *> *)mtCaptureURLSchemeSpecifiers {
    NSMutableArray *specifiers = [NSMutableArray array];
    for (NSArray<NSString *> *entry in [self mtSchemeEntries]) {
        NSString *notificationName = entry[1];
        NSString *title = entry[0];
        PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
                                                                target:self
                                                                   set:NULL
                                                                   get:NULL
                                                                detail:Nil
                                                                  cell:PSButtonCell
                                                                   edit:Nil];
        // URL 行由 didSelectRowAtIndexPath 直接分发，避免系统按钮转发丢失动作，
        // 同时不注册第二条 buttonAction 路径，保证一次点击只发送一次请求。
        [specifier setProperty:notificationName forKey:@"mtCaptureNotification"];
        [specifier setProperty:title forKey:@"mtTitle"];
        [specifiers addObject:specifier];
    }
    return specifiers;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // specifierAtIndexPath: 是 Preferences 私有方法，缺失时回退系统转发，避免整页点击崩溃。
    if (![self respondsToSelector:@selector(specifierAtIndexPath:)]) {
        [super tableView:tableView didSelectRowAtIndexPath:indexPath];
        return;
    }
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([[specifier propertyForKey:@"mtCaptureNotification"] isKindOfClass:NSString.class]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self mtTriggerCaptureTest:specifier];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)mtTriggerCaptureTest:(PSSpecifier *)specifier {
    NSString *notificationName = [specifier propertyForKey:@"mtCaptureNotification"];
    NSString *title = [specifier propertyForKey:@"mtTitle"];
    if (notificationName.length == 0 || title.length == 0) {
        MTCaptureLogWarn(@"prefs test specifier missing notification/title");
        return;
    }
    // 直发一次 Darwin 请求；不 openURL、不复制、不重试。
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)notificationName, NULL, NULL, YES);
    MTCaptureLogInfo(@"prefs test entry requested: %@", notificationName);
    UISelectionFeedbackGenerator *haptic = [[UISelectionFeedbackGenerator alloc] init];
    [haptic selectionChanged];

    // 同一行连续点击时，仅最新一轮反馈恢复标题；切走设置页后只恢复模型。
    NSUInteger rowGeneration = [[specifier propertyForKey:@"mtFeedbackGeneration"] unsignedIntegerValue] + 1;
    [specifier setProperty:@(rowGeneration) forKey:@"mtFeedbackGeneration"];
    specifier.name = @"已发送请求 ✓";
    [self reloadSpecifier:specifier animated:NO];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if ([[specifier propertyForKey:@"mtFeedbackGeneration"] unsignedIntegerValue] != rowGeneration) return;
        specifier.name = title;
        __strong typeof(weakSelf) self = weakSelf;
        if (self.isViewLoaded && self.view.window) [self reloadSpecifier:specifier animated:NO];
    });

    self.copyFeedbackGeneration++;
    NSInteger generation = self.copyFeedbackGeneration;
    PSSpecifier *group = [self mtExternalEntryGroupIn:_specifiers];
    if (!group) return;
    NSString *feedbackFooter = @"已发送测试请求。";
    if (![group propertyForKey:@"mtOriginalFooter"]) {
        [group setProperty:([group propertyForKey:@"footerText"] ?: @"") forKey:@"mtOriginalFooter"];
    }
    [group setProperty:feedbackFooter forKey:@"footerText"];
    [self reloadSpecifier:group animated:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.copyFeedbackGeneration) return;
        [group setProperty:([group propertyForKey:@"mtOriginalFooter"] ?: @"") forKey:@"footerText"];
        if (self.isViewLoaded && self.view.window) [self reloadSpecifier:group animated:NO];
    });
}

@end
