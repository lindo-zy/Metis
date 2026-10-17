// MTPrefsShellTableController —— 设置壳内设计稿风格页面的共同基类。
// 在 MetisCore 的 MTSettingsTableController 之上补齐 Shell 特有路由：
// MTSettingsRouteSubbundle 经 MTPrefsSubbundleLoader 加载子包控制器；
// 加载失败给出明确提示（02 §7：不静默跳过）。首页/全局分类页共用。
#import "MTSettingsTableController.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsShellTableController : MTSettingsTableController
/// 路由失败提示（子包缺失/类不存在）。alert 只提示，不改变导航栈。
- (void)presentUnavailableAlertWithTitle:(NSString *)title;
@end

NS_ASSUME_NONNULL_END
