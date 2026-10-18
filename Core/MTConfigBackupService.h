// MTConfigBackupService.h —— 配置备份/恢复聚合服务（全局「配置维护」）。
// 覆盖范围：Metis 自有 CFPreferences 域全量键值 + 共享资源文档（动作/面板）。
// 写入者语义：恢复写域后逐域 AppSynchronize，并广播各模块既有刷新通知，
// 由既有监听路径热加载；门控快照经 MTConfigService.flush 重发（沙盒宿主
// 的唯一门控来源，必须与恢复后的 enabled 保持一致）。
// Foundation-only：宿主测试直接编译本文件（域清单/备份目录可 override）。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 备份文件根键 format；不匹配的一律拒绝（不是 Metis 配置备份）。
extern NSString *const MTConfigBackupFormat;
/// 当前备份 schema 版本（根键 schemaVersion）；高于本版本的备份只读拒绝。
extern NSUInteger const MTConfigBackupCurrentSchemaVersion;
/// 滚动保留份数：createBackup 成功后仅保留最近 N 份，更早的自动淘汰。
extern NSUInteger const MTConfigBackupRetentionLimit;
extern NSString *const MTConfigBackupErrorDomain;

typedef NS_ENUM(NSInteger, MTConfigBackupErrorCode) {
    MTConfigBackupErrorNone = 0,
    MTConfigBackupErrorIOFailed,       ///< 备份目录创建/文件写失败
    MTConfigBackupErrorUnreadable,     ///< 文件不存在或不是合法 plist
    MTConfigBackupErrorInvalidFile,    ///< format 不匹配（不是 Metis 备份）
    MTConfigBackupErrorFutureSchema,   ///< schemaVersion 高于当前版本
    MTConfigBackupErrorRestoreFailed,  ///< 恢复过程中写域/写共享资源失败
};

/// 备份元信息（不含内容）；列表展示与删除/恢复定位用。
@interface MTConfigBackupItem : NSObject
@property (nonatomic, copy) NSString *path;          ///< 备份文件完整路径
@property (nonatomic, copy) NSDate *createdAt;       ///< 备份创建时间（文件内 createdAt）
@property (nonatomic, copy) NSString *appVersion;    ///< 备份时设置端版本
@property (nonatomic, assign) uint64_t byteSize;
@property (nonatomic, assign) NSUInteger domainCount; ///< 非空偏好域个数
@property (nonatomic, assign) BOOL includesSharedResources;
@end

@interface MTConfigBackupService : NSObject

/// 备份根目录（逻辑 /var/mobile/Library/Metis/Backups/，经 MTResolvePath）。
+ (NSString *)backupDirectory;

/// 全部备份，创建时间倒序（最新在前）。
+ (NSArray<MTConfigBackupItem *> *)availableBackups;

/// 立即备份：聚合全部偏好域 + 共享资源文档，原子写入备份目录；
/// 成功后按滚动策略淘汰旧备份。失败返回 nil 并给出错误。
+ (nullable MTConfigBackupItem *)createBackupWithError:(NSError **)error;

/// 校验并读取备份内容（不写入任何东西）。失败返回 nil 并给出错误。
+ (nullable NSDictionary *)readBackupAtPath:(NSString *)path error:(NSError **)error;

/// 全量恢复：安全网备份当前配置 → 覆盖全部偏好域 → 恢复共享资源 →
/// MTConfigService.flush（门控快照 + config-changed）+ 各模块刷新通知。
/// 任一步失败返回 NO；偏好域可能已部分写入（尽力恢复语义，错误信息说明现场）。
+ (BOOL)restoreBackupAtPath:(NSString *)path error:(NSError **)error;

/// 删除单个备份文件（仅限备份目录内）。文件已不存在视为成功。
+ (BOOL)deleteBackupAtPath:(NSString *)path error:(NSError **)error;

/// 导入外部备份（换机/分享文件场景）：先校验格式与 schema，通过后复制为
/// 一份正式备份（同目录同命名规则，纳入滚动保留）。返回新备份文件路径。
+ (nullable NSString *)importBackupFromPath:(NSString *)sourcePath error:(NSError **)error;

/// 主机测试专用：备份根目录 override；传入 nil 恢复默认。
+ (void)setBackupDirectoryOverride:(nullable NSString *)path;

/// 主机测试专用：偏好域清单 override；传入 nil 恢复默认（6 个产品域）。
+ (void)setPreferenceDomainOverride:(nullable NSArray<NSString *> *)domains;

@end

NS_ASSUME_NONNULL_END
