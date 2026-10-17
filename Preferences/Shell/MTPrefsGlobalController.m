#import "MTPrefsGlobalController.h"
#import "MTPrefsGlobalModel.h"

// 全局分类页渲染：模型见 MTPrefsGlobalModel（宿主测试权威）。
// 搜索直达支持：pendingFocusIdentifier 由首页在压栈前设置（基类消费）。
@implementation MTPrefsGlobalController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"全局";
    self.model = [MTPrefsGlobalModel globalPageModel];
    [self render];
}

@end
