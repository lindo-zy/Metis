#import "MTCaptureRootListController.h"
#import "../../Modules/Capture/Sources/Common/MTConstants.h"
#import "../../Modules/Capture/Sources/Common/MTCaptureLog.h"

@interface MTCaptureRootListController ()
@property (nonatomic, assign) NSInteger copyFeedbackGeneration;
@end

// 模块内不再挂品牌 logo 头（2026-10-17 需求）：品牌只在系统设置首页出现，
// 本页直接进配置项（Root.plist），外部测试入口仍在「外部入口」分组。
@implementation MTCaptureRootListController

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
