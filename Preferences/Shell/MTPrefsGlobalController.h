// MTPrefsGlobalController —— 全局分类页（02-settings-ux §2 + 02 §6 合并）。
// 共享资源：自定义动作 / 面板管理；手势与悬浮：Dock 手势、状态栏手势、悬浮应用；
// 自动化：AI 问答、短信验证码自动复制、浏览器重定向；配置维护：配置备份、
// 配置恢复、引用管理。
// 原「其他」分类页内容已并入本页；结构由 MTPrefsGlobalModel 提供；编辑器复用
// MetisKeyboardPrefs 包内现有控制器（共享 store 读写服务）。
// 功能开关写值经模型层落到键盘细节域并广播 prefschanged；
// 不提供「启用全局」或任何替代模块的开关（总开关在首页）。
#import "MTPrefsShellTableController.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsGlobalController : MTPrefsShellTableController
@end

NS_ASSUME_NONNULL_END
