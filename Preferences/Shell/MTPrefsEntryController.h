// MTPrefsEntryController —— MetisPrefs 主类薄壳。
// Preferences 框架对设置包主类有硬性契约：controllerForSpecifier: 实例化主类后
// 会直接发送 initForContentSize:/setSpecifier: 等 PSViewController/PSListController
// 方法且不做 respondsToSelector 保护，主类不是 PSListController 子类时抛
// unrecognized selector（0.1.5 点击入口崩溃的根因）。
// 模型首页现已继承 PSListController，直接承载根表格，让 Preferences 路由
// 与 QuickPrefs 的长按手势读取同一份真实表格与 specifiers。
#import "MTPrefsRootController.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsEntryController : MTPrefsRootController
@end

NS_ASSUME_NONNULL_END
