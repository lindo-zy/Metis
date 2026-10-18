#import "MTPrefsEntryController.h"
#import "MTPrefsRootController.h"

@implementation MTPrefsEntryController

// 空 specifier 表：主类只做容器，不渲染 PS 表格（bundle 无 Root.plist，
// 默认 plist 加载路径不适用），也保证 reloadSpecifiers 等内部机制安全空转。
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [@[] mutableCopy];
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"";
    [self mtEmbedRootPage];
}

// 嵌入 v3 首页。child 的 navigationController 经父链解析到设置导航栈，
// 首页内路由（压栈子包页/Shell 页）无需感知这一层包装。
- (void)mtEmbedRootPage {
    MTPrefsRootController *root = [[MTPrefsRootController alloc] init];
    [self addChildViewController:root];
    root.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:root.view];
    [NSLayoutConstraint activateConstraints:@[
        [root.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [root.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [root.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [root.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [root didMoveToParentViewController:self];
}

@end
