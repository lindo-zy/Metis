#import <Preferences/PSViewController.h>
#import <UIKit/UIKit.h>
#import "MTExternalURLController.h"
#import "../../Modules/Capture/Sources/Common/MTConstants.h"

// 外部 URL 调用文档页：列出全部 5 条寄生路由（prefs://root=metis_*），点击复制。
// 触发链路：捷径「打开 URL」动作 → openURL: → SpringBoard URL 分发层
// （MTURLRouter.xm 拦截 metis_ 命名空间）→ MTCaptureCoordinator，与 Darwin
// 通知入口是同一协调器方法。因此行为口径完全一致：总开关或截图模块关闭、
// 已有截图任务进行中时请求被忽略并记日志；本入口无结果回调（fire-and-forget）。
// 与 MTCustomURLController 同款自建 UITableView：Preferences 导航页必须继承
// PSViewController，plist 加载器不会实例化代码构建的 cellClass。

@implementation MTExternalURLController {
    UITableView *_tableView;
    NSInteger _flashedRow;      // 正在显示「已复制」反馈的行；-1 = 无
    NSInteger _flashGeneration; // 反馈代数：仅最新一轮允许恢复，连续点击不抖动
}

- (void)loadView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    self.view = _tableView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"外部 URL 调用";
}

#pragma mark - 数据源

// 标题与 MTConstants 路由常量一一对应；改路由必须同步本表与 MTURLRouter.xm 白名单。
// 冻结/即时/取消不开放 URL 入口（仍可由 Darwin 通知与键盘系统动作触发）。
- (NSArray<NSArray<NSString *> *> *)mtRouteEntries {
    return @[
        @[@"全屏截图", (__bridge NSString *)MTURLRouteFull],
        @[@"区域截图", (__bridge NSString *)MTURLRouteArea],
        @[@"全屏标记", (__bridge NSString *)MTURLRouteMarkup],
        @[@"滚动长截图", (__bridge NSString *)MTURLRouteLong],
        @[@"编辑剪贴板图片", (__bridge NSString *)MTURLRouteEditClipboard],
    ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self mtRouteEntries].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuse = @"mt-external-url-cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    if (indexPath.row < 0 || indexPath.row >= [self mtRouteEntries].count) return cell;
    NSArray<NSString *> *entry = [self mtRouteEntries][indexPath.row];
    BOOL flashed = indexPath.row == _flashedRow;
    cell.textLabel.text = flashed ? @"已复制 ✓" : entry[0];
    cell.textLabel.textColor = flashed ? [UIColor systemBlueColor] : [UIColor labelColor];
    cell.detailTextLabel.text = entry[1];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"可用路由（点击复制）";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"在 iOS 捷径 App 中新建「打开 URL」动作，填入对应地址即可触发，可进一步绑定到操作按钮、轻点背面或 NFC 标签。触发链路与系统截图入口一致：Metis 总开关或截图模块关闭、已有截图任务进行中时，请求会被忽略；本入口只发送请求，没有结果回调。";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 52.0;
}

#pragma mark - 动作

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (indexPath.row < 0 || indexPath.row >= [self mtRouteEntries].count) return;
    [UIPasteboard generalPasteboard].string = [self mtRouteEntries][indexPath.row][1];
    UISelectionFeedbackGenerator *haptic = [[UISelectionFeedbackGenerator alloc] init];
    [haptic selectionChanged];

    // 行内即时反馈：标题短暂替换后自动恢复；同一行连续点击时仅最新一轮恢复。
    NSInteger previous = _flashedRow;
    _flashedRow = indexPath.row;
    _flashGeneration++;
    NSInteger generation = _flashGeneration;
    NSMutableArray<NSIndexPath *> *rows = [NSMutableArray arrayWithObject:indexPath];
    if (previous >= 0 && previous != indexPath.row) {
        [rows addObject:[NSIndexPath indexPathForRow:previous inSection:0]];
    }
    [tableView reloadRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationNone];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self->_flashGeneration) return;
        NSInteger row = self->_flashedRow;
        self->_flashedRow = -1;
        if (row >= 0 && self.isViewLoaded && self.view.window) {
            [self->_tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
                                   withRowAnimation:UITableViewRowAnimationNone];
        }
    });
}

@end
