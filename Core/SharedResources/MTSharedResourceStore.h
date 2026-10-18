// MTSharedResourceStore.h —— 共享资源的唯一权威存取（03 §3/§7）。
// 权威文件：/var/mobile/Library/Metis/Global/resources-v1.plist（Settings 唯一写入）。
// 运行快照：/Library/Metis/Config/global-shared.plist（世界可读；沙盒宿主唯一来源）。
// 一次提交 = 校验 → revision+1 → 权威原子替换 → 快照原子发布 → Darwin 失效通知。
// 读取方持有进程内缓存，监听 com.lindo.metis/shared-resources-changed 自动失效。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const MTSharedResourceStoreErrorDomain;

typedef NS_ENUM(NSInteger, MTSharedResourceStoreCode) {
    MTSharedResourceStoreOK = 0,
    MTSharedResourceStoreConflict,          // expectedRevision 落后：重新载入/合并，不得覆盖
    MTSharedResourceStoreValidationFailed,
    MTSharedResourceStoreIOFailed,
    MTSharedResourceStoreUnavailable,       // 读取失败/未来 schema：保留旧有效快照
    MTSharedResourceStoreFutureSchema,      // 高于当前版本：只读不可执行
};

@interface MTSharedResourceStore : NSObject

+ (NSString *)authoritativePath;
+ (NSString *)snapshotPath;

/// 当前进程可见的最新文档；读不到/损坏/未来版本时返回 nil（不把读取失败当空库）。
/// 非沙盒进程优先读权威文件（缺失时回退快照），沙盒进程只读快照。
+ (nullable NSDictionary *)readSnapshot;
+ (nullable NSDictionary *)readSnapshotError:(NSError **)error;

/// 当前可见文档的 revision；无文档时为 0。
+ (uint64_t)currentRevision;

/// 仅 Settings（唯一写入端）调用：以 expectedRevision 做冲突检测后整体提交。
/// draft 为完整 payload（actions/panels/bindings/groups/ungroupedCollapsed/migration）；
/// format/schemaVersion/revision 由本方法装配。
+ (BOOL)commitSnapshot:(NSDictionary *)draft expectedRevision:(uint64_t)revision error:(NSError **)error;

/// 主机测试专用：把两个存储路径指到临时目录；传入 nil 恢复默认。
+ (void)setAuthoritativePathOverride:(nullable NSString *)path snapshotOverride:(nullable NSString *)path2;

/// 构造合法空文档（首装初始配置 / 迁移基座）。
+ (NSDictionary *)emptyDocument;

/// 供迁移器内部使用的低层写入（不做 expectedRevision 检查，用于首装落库）。
+ (BOOL)installDocument:(NSDictionary *)document error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
