// MTPrefsRootModel —— 设置首页模型（docs/development/02 §1 + 设计稿 metis-settings-v3.png）。
// Foundation-only：宿主测试编译本文件并断言页面结构；UIKit 渲染在
// MTPrefsRootController。页面结构权威：品牌头 + 搜索 + 启用总开关 + 五分类 +
// 页脚；关闭总开关时追加一条整体暂停提示行（非模块状态行）。关于页已移除。
#import <Foundation/Foundation.h>
#import "MTSettingsModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsRootModel : NSObject

/// 首页页面模型（每次调用重建；调用方缓存）。
+ (MTSettingsPageModel *)rootPageModel;

/// 五分类行（全局/键盘/剪切板/截图/其他），搜索索引与首页共用同一份定义。
+ (NSArray<MTSettingsRow *> *)categoryRows;

/// 总开关读取与写入（写入 = MTConfigService 落盘 + flush + MTModuleGate reload）。
+ (BOOL)globalEnabled;
+ (void)setGlobalEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
