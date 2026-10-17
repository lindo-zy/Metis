// MTPrefsEntryController —— MetisPrefs 主类薄壳。
// Preferences 框架对设置包主类有硬性契约：controllerForSpecifier: 实例化主类后
// 会直接发送 initForContentSize:/setSpecifier: 等 PSViewController/PSListController
// 方法且不做 respondsToSelector 保护，主类不是 PSListController 子类时抛
// unrecognized selector（0.1.5 点击入口崩溃的根因）。
// 本类只满足该契约并承载导航标题；v3 设计稿首页由 MTPrefsRootController
// 以 child view controller 方式完整嵌入，模型驱动渲染与路由不受影响。
#import <Preferences/Preferences.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsEntryController : PSListController
@end

NS_ASSUME_NONNULL_END
