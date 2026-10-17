// MTPrefsGlobalController —— 全局分类页（02-settings-ux §2 + 设计稿第二屏）。
// 共享资源：自定义动作 / 面板管理；配置维护：引用管理。结构由 MTPrefsGlobalModel 提供；编辑器复用
// MetisKeyboardPrefs 包内现有控制器（共享 store 读写服务），
// 不提供「启用全局」或任何替代模块的开关。
#import "MTPrefsShellTableController.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsGlobalController : MTPrefsShellTableController
@end

NS_ASSUME_NONNULL_END
