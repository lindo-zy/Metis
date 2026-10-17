// MTPrefsRootController —— Metis 唯一设置入口首页（docs/development/02 §1 + 设计稿第一屏）。
// 设计稿视觉：品牌头（图标 + 统一的效率工具）+ 搜索设置 + 启用 Metis +
// 功能模块五分类 + 页脚（关于页已移除）；结构由 MTPrefsRootModel 提供并经
// 宿主测试断言。UIKit 渲染层（不参与 macOS 宿主测试编译）。
#import "MTPrefsShellTableController.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsRootController : MTPrefsShellTableController
@end

NS_ASSUME_NONNULL_END
