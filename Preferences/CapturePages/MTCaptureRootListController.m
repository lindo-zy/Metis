#import "MTCaptureRootListController.h"
#import "MTCaptureTestCell.h"
#import <UIKit/UIKit.h>
#import "../../Modules/Capture/Sources/Common/MTCaptureAction.h"
#import "../../Modules/Capture/Sources/Common/MTCaptureLog.h"
#import "../../Modules/Capture/Sources/Common/MTConstants.h"

@implementation MTCaptureRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        [self mtMigrateRemovedLongShotAlgorithms];
        _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        NSUInteger insertIndex = _specifiers.count;
        for (PSSpecifier *specifier in _specifiers) {
            if ([specifier.identifier isEqualToString:@"capture.tests"]) {
                insertIndex = [_specifiers indexOfObject:specifier] + 1;
                break;
            }
        }
        for (MTCaptureAction *action in MTCaptureActions()) {
            [_specifiers insertObject:[self mtTestSpecifierWithTitle:action.title identifier:action.identifier]
                             atIndex:insertIndex++];
        }
    }
    return _specifiers;
}

// 录制式与手动拼接选项已移除：旧配置的 1/2 先归到自动拼接，
// 否则列表取不到当前值会显示空白，与运行时的迁移规则保持一致。
- (void)mtMigrateRemovedLongShotAlgorithms {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:MTCapturePreferencesDomain];
    NSInteger raw = [defaults integerForKey:MTKeyLongShotAlgorithm];
    if (raw != 1 && raw != 2) return;
    [defaults setInteger:3 forKey:MTKeyLongShotAlgorithm];
    MTCaptureLogInfo(@"prefs long shot algorithm migrated: %ld -> 3", (long)raw);
}

- (PSSpecifier *)mtTestSpecifierWithTitle:(NSString *)title identifier:(NSString *)identifier {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title target:self
        set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    specifier.identifier = identifier;
    // 仅 didSelect 分发；不同时注册 buttonAction，以免一击产生两个请求。
    return specifier;
}

- (BOOL)mtIsTestSpecifier:(PSSpecifier *)specifier {
    return MTCaptureActionForIdentifier(specifier.identifier) != nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if (![self mtIsTestSpecifier:specifier]) return [super tableView:tableView cellForRowAtIndexPath:indexPath];
    // 显式构造并绑定 PSTableCell，不依赖 plist 的 cellClass 加载或 PSButtonCell 的缓存标签。
    MTCaptureTestCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MTCaptureTestCell"];
    if (!cell) cell = [[MTCaptureTestCell alloc] initWithStyle:UITableViewCellStyleDefault
                                            reuseIdentifier:@"MTCaptureTestCell"];
    [cell refreshCellContentsWithSpecifier:specifier];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self mtIsTestSpecifier:[self specifierAtIndexPath:indexPath]]) return UITableViewAutomaticDimension;
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if (![self mtIsTestSpecifier:specifier]) {
        [super tableView:tableView didSelectRowAtIndexPath:indexPath];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    MTCaptureAction *action = MTCaptureActionForIdentifier(specifier.identifier);
    // Preferences 向自身 openURL 并不保证经过 SpringBoard 的启动事务。
    // 所有本地测试直接使用已注册的跨进程入口；外部 URL 仍由路由器处理同一目录。
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)action.notificationName, NULL, NULL, YES);
    MTCaptureLogInfo(@"prefs capture action requested: %@", action.identifier);
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    // 反馈不改 specifier、标题或路由，不安排延迟刷新，也不把「已发送」误报为截图成功。
}

@end
