// MTSharedResourceMigration.h —— 共享资源库的首装初始化与一次性迁移
// （docs/development/05 §2/§3/§5）。只在非沙盒写入端（Settings/SpringBoard）
// 执行；幂等：相同输入重复运行得到相同 UUID 与条目数。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTSharedResourceMigration : NSObject

/// 惰性初始化：权威文件缺失时，用传入的 legacy 键盘偏好（调用方已做
/// MTPanelMigratePreferences 等读侧规整）构建首版 store 并发布快照。
/// 已安装（含 future-schema 只读）时为 NO-OP。返回是否发起了安装。
/// legacyPreferences 允许为空字典：首装无旧数据 → 合法空库（revision 1）。
+ (BOOL)ensureInstalledWithLegacyPreferences:(nullable NSDictionary *)legacyPreferences;

/// 迁移前备份文件路径（Global/backup/pre-migration.plist，仅保留最近一份）。
+ (NSString *)preMigrationBackupPath;

@end

NS_ASSUME_NONNULL_END
