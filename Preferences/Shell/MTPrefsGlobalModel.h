// MTPrefsGlobalModel —— 全局分类页模型（docs/development/02 §2 + 设计稿第二屏）。
// 共享资源（自定义动作/面板管理）+ 配置维护（引用管理）；
// 不提供任何「启用全局」开关。Foundation-only，
// 宿主测试编译本文件断言结构。
#import <Foundation/Foundation.h>
#import "MTSettingsModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsGlobalModel : NSObject
/// 全局页模型（每次调用重建；资源行动作/面板编辑器在 MetisKeyboardPrefs 子包）。
+ (MTSettingsPageModel *)globalPageModel;
/// 两组全部行（共享资源/配置维护），搜索索引复用。
+ (NSArray<MTSettingsRow *> *)resourceRows;
@end

NS_ASSUME_NONNULL_END
