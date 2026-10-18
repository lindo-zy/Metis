#import "MTPrefsGlobalController.h"
#import "MTPrefsGlobalModel.h"

// 全局分类页渲染：模型见 MTPrefsGlobalModel（宿主测试权威）。
// 搜索直达支持：pendingFocusIdentifier 由首页在压栈前设置（基类消费）。
// 功能开关（短信验证码/浏览器重定向）由本类挂 toggleHandler：写值经模型层
// 落到键盘细节域，随后重建模型刷新开关显示（首页总开关同一模式）。
@implementation MTPrefsGlobalController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"全局";
    self.model = [MTPrefsGlobalModel globalPageModel];
    [self mtAttachToggleHandlers];
    [self render];
}

#pragma mark - Feature switches

- (void)mtAttachToggleHandlers {
    MTSettingsRow *sms = [self.model rowWithIdentifier:@"global-sms-code-copy"];
    if (sms) {
        __weak typeof(self) weakSelf = self;
        sms.toggleHandler = ^(BOOL on) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [MTPrefsGlobalModel setSmsCodeCopyEnabled:on];
            [strongSelf mtReloadModel];
        };
    }
    MTSettingsRow *redirect = [self.model rowWithIdentifier:@"global-browser-redirect"];
    if (redirect) {
        __weak typeof(self) weakSelf = weakSelf;
        redirect.toggleHandler = ^(BOOL on) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [MTPrefsGlobalModel setBrowserRedirectEnabled:on];
            [strongSelf mtReloadModel];
        };
    }
}

// 开关写值后重建模型并重新挂接，刷新初值显示。
- (void)mtReloadModel {
    self.model = [MTPrefsGlobalModel globalPageModel];
    [self mtAttachToggleHandlers];
    [self render];
}

@end
