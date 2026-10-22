#import "MTCaptureRootListController.h"
#import "MTStandaloneEditorController.h"
#import <UIKit/UIKit.h>
#import "../../Modules/Capture/Sources/Common/MTConstants.h"
#import "../../Modules/Capture/Sources/Common/MTCaptureLog.h"

@interface MTCaptureRootListController ()
/// 独立编辑器宿主：强引用保证一轮「取图 → 编辑 → 输出」期间不被释放。
@property (nonatomic, strong) MTStandaloneEditorController *standaloneEditor;
@end

// 模块内不再挂品牌 logo 头（2026-10-17 需求）：品牌只在系统设置首页出现，
// 本页直接进配置项（Root.plist），测试入口仍在「测试」分组。
@implementation MTCaptureRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        _specifiers = [self mtSpecifiersWithTestEntries];
    }
    return _specifiers;
}

// plist 加载器不会实例化自定义 cellClass（真机上条目缺动作且显示不全），
// 测试入口使用 PSButtonCell，在代码中构建并插入「测试」分组之后。
- (NSMutableArray *)mtSpecifiersWithTestEntries {
    NSMutableArray *items = [_specifiers mutableCopy];
    NSUInteger insertIndex = items.count;
    PSSpecifier *group = [self mtTestGroupIn:items];
    if (group) insertIndex = [items indexOfObject:group] + 1;
    for (PSSpecifier *specifier in [self mtCaptureTestSpecifiers]) {
        [items insertObject:specifier atIndex:insertIndex];
        insertIndex++;
    }
    [items insertObject:[self mtStandaloneEditorSpecifier] atIndex:insertIndex];
    return items;
}

- (PSSpecifier *)mtTestGroupIn:(NSArray *)specifiers {
    for (PSSpecifier *spec in specifiers) {
        if ([spec.name isEqualToString:@"测试"]) return spec;
    }
    return nil;
}

// 测试入口表：@[标题, Darwin 通知名, URL 路由]，后两项按行取其一。
// 原「外部 URL 调用」文档页已并入本分组（2026-10-22）：带 URL 路由的行点击后按
// prefs://root=metis_* 发起请求，链路与 iOS 捷径「打开 URL」完全一致——SpringBoard
// 侧 MTURLRouter.xm 拦截后直达 MTCaptureCoordinator，因此一次点击同时验证外部路由
// 与截图入口是否可达。启动入口（activate）按需求不开放 URL 路由，仍走 Darwin 通知，
// 其协调器行为与 metis_area 相同。路由常量单一事实源在 MTConstants，改路由必须同步
// MTURLRouter.xm 白名单。
- (NSArray<NSArray<NSString *> *> *)mtTestEntries {
    return @[
        @[@"启动（区域截图）", (__bridge NSString *)MTDarwinActivate, @""],
        @[@"全屏截图", @"", (__bridge NSString *)MTURLRouteFull],
        @[@"区域截图", @"", (__bridge NSString *)MTURLRouteArea],
        @[@"全屏标记", @"", (__bridge NSString *)MTURLRouteMarkup],
        @[@"滚动截图", @"", (__bridge NSString *)MTURLRouteLong],
        @[@"编辑剪贴板图片", @"", (__bridge NSString *)MTURLRouteEditClipboard],
    ];
}

- (NSArray<PSSpecifier *> *)mtCaptureTestSpecifiers {
    NSMutableArray *specifiers = [NSMutableArray array];
    for (NSArray<NSString *> *entry in [self mtTestEntries]) {
        NSString *title = entry[0];
        PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
                                                                target:self
                                                                   set:NULL
                                                                   get:NULL
                                                                detail:Nil
                                                                  cell:PSButtonCell
                                                                   edit:Nil];
        // 点击由 didSelectRowAtIndexPath 直接分发，避免系统按钮转发丢失动作，
        // 同时不注册第二条 buttonAction 路径，保证一次点击只发送一次请求。
        if (entry[1].length) [specifier setProperty:entry[1] forKey:@"mtCaptureNotification"];
        if (entry[2].length) [specifier setProperty:entry[2] forKey:@"mtCaptureURLRoute"];
        [specifier setProperty:title forKey:@"mtTitle"];
        [specifiers addObject:specifier];
    }
    return specifiers;
}

// 独立图片编辑入口：不发请求，直接在本页进程内拉起编辑器
// （剪贴板取图 / 相册导入），区域截图链路与协调器均不参与。
- (PSSpecifier *)mtStandaloneEditorSpecifier {
    NSString *title = @"图片编辑";
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
                                                            target:self
                                                               set:NULL
                                                               get:NULL
                                                            detail:Nil
                                                              cell:PSButtonCell
                                                               edit:Nil];
    [specifier setProperty:@YES forKey:@"mtStandaloneEditor"];
    [specifier setProperty:title forKey:@"mtTitle"];
    return specifier;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // specifierAtIndexPath: 是 Preferences 私有方法，缺失时回退系统转发，避免整页点击崩溃。
    if (![self respondsToSelector:@selector(specifierAtIndexPath:)]) {
        [super tableView:tableView didSelectRowAtIndexPath:indexPath];
        return;
    }
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([specifier propertyForKey:@"mtCaptureNotification"] ||
        [specifier propertyForKey:@"mtCaptureURLRoute"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self mtTriggerCaptureTest:specifier];
        return;
    }
    if ([[specifier propertyForKey:@"mtStandaloneEditor"] boolValue]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self mtLaunchStandaloneEditor:specifier];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)mtTriggerCaptureTest:(PSSpecifier *)specifier {
    NSString *notificationName = [specifier propertyForKey:@"mtCaptureNotification"];
    NSString *route = [specifier propertyForKey:@"mtCaptureURLRoute"];
    NSString *title = [specifier propertyForKey:@"mtTitle"];
    if (title.length == 0) {
        MTCaptureLogWarn(@"prefs test specifier missing title");
        return;
    }
    if (route.length > 0) {
        [self mtRequestURLRoute:route specifier:specifier];
        return;
    }
    // 无 URL 路由的入口直发一次 Darwin 请求；不 openURL、不复制、不重试。
    if (notificationName.length == 0) {
        MTCaptureLogWarn(@"prefs test specifier missing notification/route");
        return;
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)notificationName, NULL, NULL, YES);
    MTCaptureLogInfo(@"prefs test entry requested: %@", notificationName);
    [self mtFeedbackForRequest:specifier];
}

// 外部 URL 路由触发：与捷径「打开 URL」同一条链路，命中后由 SpringBoard 侧
// MTURLRouter.xm 消费并直达协调器，本页不会被系统打开设置页顶掉。
- (void)mtRequestURLRoute:(NSString *)route specifier:(PSSpecifier *)specifier {
    NSURL *url = [NSURL URLWithString:route];
    if (!url) {
        MTCaptureLogWarn(@"prefs test route malformed: %@", route);
        [self mtFlashSpecifier:specifier message:@"地址无效"];
        return;
    }
    MTCaptureLogInfo(@"prefs test url route requested: %@", route);
    __weak typeof(self) weakSelf = self;
    [[UIApplication sharedApplication] openURL:url
                                       options:@{}
                             completionHandler:^(BOOL success) {
        if (success) return;
        MTCaptureLogWarn(@"prefs test url route not delivered: %@", route);
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf mtFlashSpecifier:specifier message:@"发送失败"];
        });
    }];
    [self mtFeedbackForRequest:specifier];
}

/// 点击反馈：震动 + 行内即时提示。
- (void)mtFeedbackForRequest:(PSSpecifier *)specifier {
    UISelectionFeedbackGenerator *haptic = [[UISelectionFeedbackGenerator alloc] init];
    [haptic selectionChanged];
    [self mtFlashSpecifier:specifier message:@"已发送请求 ✓"];
}

// 独立图片编辑入口：在本页进程内拉起编辑器，不经过外部请求与协调器。
- (void)mtLaunchStandaloneEditor:(PSSpecifier *)specifier {
    if ([[specifier propertyForKey:@"mtTitle"] length] == 0) return;
    if (!self.standaloneEditor) {
        self.standaloneEditor = [[MTStandaloneEditorController alloc] initWithHostViewController:self];
    }
    BOOL launched = [self.standaloneEditor start];
    [self mtFlashSpecifier:specifier message:(launched ? @"已打开编辑器 ✓" : @"暂时无法打开")];
}

/// 行内即时反馈：标题短暂替换后自动恢复；同一行连续点击时仅最新一轮恢复。
- (void)mtFlashSpecifier:(PSSpecifier *)specifier message:(NSString *)message {
    NSString *title = [specifier propertyForKey:@"mtTitle"];
    if (title.length == 0 || message.length == 0) return;
    NSUInteger rowGeneration = [[specifier propertyForKey:@"mtFeedbackGeneration"] unsignedIntegerValue] + 1;
    [specifier setProperty:@(rowGeneration) forKey:@"mtFeedbackGeneration"];
    specifier.name = message;
    [self reloadSpecifier:specifier animated:NO];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if ([[specifier propertyForKey:@"mtFeedbackGeneration"] unsignedIntegerValue] != rowGeneration) return;
        specifier.name = title;
        __strong typeof(weakSelf) self = weakSelf;
        if (self.isViewLoaded && self.view.window) [self reloadSpecifier:specifier animated:NO];
    });
}

@end
