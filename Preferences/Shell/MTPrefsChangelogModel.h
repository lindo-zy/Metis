// MTPrefsChangelogModel —— 设置首页「更新说明」数据层（Foundation-only）。
// 数据源是包内 Resources/Changelog.plist（只保留最近 5 个版本），本文件负责
// 解析、校验、数值排序、去重与截断；UIKit 渲染见 MTPrefsChangelogController。
// 版本号必须按数值分段比较（字符串比较会把 0.8.10 排到 0.8.9 前面）。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 变更标签：新增 / 优化 / 修复；未知标签归入「调整」，不丢条目。
typedef NS_ENUM(NSInteger, MTChangelogTag) {
    MTChangelogTagAdded = 0,
    MTChangelogTagImproved,
    MTChangelogTagFixed,
    MTChangelogTagChanged,
};

/// 展示上限：只记录最近 5 次版本（数据文件与渲染层双重保障）。
FOUNDATION_EXPORT NSUInteger const MTPrefsChangelogEntryLimit;

@interface MTChangelogItem : NSObject
@property (nonatomic, assign, readonly) MTChangelogTag tag;
@property (nonatomic, copy, readonly) NSString *text;
/// 标签中文名（新增 / 优化 / 修复 / 调整）。
@property (nonatomic, copy, readonly) NSString *tagDisplayName;
+ (instancetype)itemWithTag:(MTChangelogTag)tag text:(NSString *)text;
@end

@interface MTChangelogEntry : NSObject
@property (nonatomic, copy, readonly) NSString *version;
@property (nonatomic, copy, readonly) NSArray<MTChangelogItem *> *items;
+ (instancetype)entryWithVersion:(NSString *)version items:(NSArray<MTChangelogItem *> *)items;
@end

@interface MTPrefsChangelogModel : NSObject

/// 包内数据源解析结果（最多 5 条，版本降序）。资源缺失/损坏时返回空数组。
+ (NSArray<MTChangelogEntry *> *)entries;

/// 同上，可指定上限；limit 为 0 时按 MTPrefsChangelogEntryLimit 处理。
+ (NSArray<MTChangelogEntry *> *)entriesWithLimit:(NSUInteger)limit;

/// 纯函数入口（宿主测试直接喂字典数组）：校验 + 去重 + 数值降序 + 截断。
/// 缺 version、items 为空的条目整条丢弃；单条 text 为空的项逐条丢弃。
+ (NSArray<MTChangelogEntry *> *)entriesFromArray:(nullable NSArray *)raw limit:(NSUInteger)limit;

/// 数值分段比较（"0.8.10" > "0.8.9"）；非数字段按 0 处理。
+ (NSComparisonResult)compareVersion:(NSString *)lhs toVersion:(NSString *)rhs;

/// 半屏标题：两条以上为「更新（上一发布 → 最新发布）」，单条为「更新说明 · 版本」。
/// 不依赖本地「上次查看版本」，避免为一次性文案新增偏好键。
+ (NSString *)sheetTitleForEntries:(NSArray<MTChangelogEntry *> *)entries;

@end

NS_ASSUME_NONNULL_END
