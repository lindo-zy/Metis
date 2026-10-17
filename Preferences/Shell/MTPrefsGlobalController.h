// MTPrefsGlobalController —— 全局分类页（02-settings-ux §2）。
// 共享资源：自定义动作 / 面板管理；调用配置：入口绑定；配置维护：引用管理。
// 编辑器复用 MetisKeyboardPrefs 包内现有控制器（共享 store 读写服务），
// 不提供「启用全局」或任何替代模块的开关。
#import <Preferences/Preferences.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsGlobalController : PSListController
@end

NS_ASSUME_NONNULL_END
