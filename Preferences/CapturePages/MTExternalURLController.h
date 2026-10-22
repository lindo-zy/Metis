#import <Preferences/PSViewController.h>

/// 外部 URL 调用文档页：列出全部 6 条寄生路由（prefs://root=metis_*）并支持点击复制。
/// 类定义在 MTExternalURLController.m（自建 UITableView，同 MTCustomURLController 模式）；
/// 由 MTCaptureRootListController 以 detail:MTExternalURLController.class 代码插入。
@interface MTExternalURLController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@end
