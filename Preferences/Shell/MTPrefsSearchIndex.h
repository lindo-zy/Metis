// MTPrefsSearchIndex —— 首页搜索索引（docs/development/02 §7）。
// 只检索静态设置标题、分类路径与资源名称/类型；不读剪切板正文或用户脚本内容。
// 每条结果携带目标 MTSettingsRow（route 描述），点击由首页控制器执行
// 「直达 + 短暂强调」。Foundation-only，宿主测试编译本文件。
#import <Foundation/Foundation.h>
#import "MTSettingsModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTSettingsSearchEntry : NSObject
@property (nonatomic, copy) NSString *title;            ///< 配置项标题
@property (nonatomic, copy) NSString *path;             ///< 分类路径（如「全局 · 面板管理」）
@property (nonatomic, strong) MTSettingsRow *target;    ///< 目标行（route + 稳定 identifier）
@end

@interface MTPrefsSearchIndex : NSObject
/// 按查询过滤索引（空查询返回空数组）。资源名称在首次调用时从共享 store 快照读取。
+ (NSArray<MTSettingsSearchEntry *> *)entriesMatchingQuery:(NSString *)query;
/// 静态部分（标题+路径），供宿主测试断言；不含资源名称。
+ (NSArray<MTSettingsSearchEntry *> *)staticEntries;
@end

NS_ASSUME_NONNULL_END
