// MTPrefsGlobalModel —— 全局分类页模型（docs/development/02 §2 + 02 §6 合并）。
// 共享资源（自定义动作/面板管理）+ 手势与悬浮（Dock 手势/状态栏手势/悬浮应用）
// + 自动化（AI 问答/短信验证码自动复制/浏览器重定向）+ 配置维护（引用管理）。
// 原「其他」分类页（02 §6）内容已并入本页：手势/悬浮/AI 链接复用
// MetisKeyboardPrefs 子包控制器；两个功能开关沿用键盘细节域
// （com.lindo.metis.keyboard）键名与 prefschanged 通知，运行端零改动。
// 不提供任何「启用全局」开关（总开关在首页）。Foundation-only，
// 宿主测试编译本文件断言结构。
#import <Foundation/Foundation.h>
#import "MTSettingsModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsGlobalModel : NSObject
/// 全局页模型（每次调用重建；资源行动作/面板编辑器在 MetisKeyboardPrefs 子包）。
+ (MTSettingsPageModel *)globalPageModel;
/// 共享资源行（自定义动作/面板管理），搜索索引复用。
+ (NSArray<MTSettingsRow *> *)resourceRows;
/// 手势与悬浮行（Dock 手势/状态栏手势/悬浮应用），子包路由。
+ (NSArray<MTSettingsRow *> *)gestureAndFloatingRows;
/// 自动化妆置行（AI 问答链接 + 两个功能开关），搜索索引复用。
+ (NSArray<MTSettingsRow *> *)automationRows;
/// 功能开关当前值（缺省关；键名与运行端一致，com.lindo.metis.keyboard 域）。
+ (BOOL)smsCodeCopyEnabled;
+ (BOOL)browserRedirectEnabled;
/// 功能开关写入：替换权威域键值并广播 prefschanged（运行端即时重载）。
+ (void)setSmsCodeCopyEnabled:(BOOL)enabled;
+ (void)setBrowserRedirectEnabled:(BOOL)enabled;
@end

NS_ASSUME_NONNULL_END
