#import "MTCodeResultsController.h"

@interface MTCodeResultsController ()
@property (nonatomic, copy) NSArray<NSString *> *codes;
@end
@implementation MTCodeResultsController
- (instancetype)initWithCodes:(NSArray<NSString *> *)codes {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _codes = [codes copy];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"扫码结果";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成"
        style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 100;
}
- (void)close { if (self.onClose) self.onClose(); }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.codes.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"点按识别结果可复制内容或打开链接。二维码、条码中的文字均可识别。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"code"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"code"];
    cell.textLabel.text = [NSString stringWithFormat:@"识别结果 %ld", (long)indexPath.row + 1];
    cell.detailTextLabel.text = self.codes[indexPath.row];
    cell.detailTextLabel.numberOfLines = 6;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *text = self.codes[indexPath.row];
    UIAlertController *actions = [UIAlertController alertControllerWithTitle:@"识别结果" message:text
        preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [actions addAction:[UIAlertAction actionWithTitle:@"复制内容" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (weakSelf.onCopy) weakSelf.onCopy(text);
    }]];
    NSURL *url = [NSURL URLWithString:text];
    // 仅把可浏览/常见扫码应用链接展示为打开动作，其余载荷保留为可复制文本。
    if (url && [@[@"https", @"http", @"weixin", @"alipay", @"alipays", @"wxp"] containsObject:url.scheme.lowercaseString]) {
        [actions addAction:[UIAlertAction actionWithTitle:@"打开链接" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (weakSelf.onOpenURL) weakSelf.onOpenURL(url);
        }]];
    }
    [actions addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    actions.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
    actions.popoverPresentationController.sourceRect = [tableView cellForRowAtIndexPath:indexPath].bounds;
    [self presentViewController:actions animated:YES completion:nil];
}
@end
