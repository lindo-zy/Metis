// MTLegacyKayokoImporter —— 旧 KayokoX 用户数据一次性接管（2026-10-17 用户授权）。
// 背景：Metis 剪贴板使用自有目录与偏好域且不读旧插件域；老 KayokoX 数据完整
// 留在 /var/mobile/Library/com.lindo.kayoko/（history-v4 同 schema），不迁移则
// 历史面板报「search index is not ready」且全部旧配置丢失。
// 规则（05-data-migration §1 默认值契约仍有效，本类是对外部数据的一次性例外）：
//   - 只在 SpringBoard 安装期同步执行一次，先于任何偏好读取与历史库创建；
//   - marker 文件保证幂等；文件阶段失败不写 marker，下次启动自动重试；
//   - 旧数据只复制不删除（Kayoko 回装仍可用）；
//   - 偏好逐键 only-if-absent 合入，绝不覆盖用户已在 Metis 改过的键；
//   - 排除 Enabled：模块启停权威在 com.lindo.metis（MTModuleGate），旧模块
//     开关不参与迁移（v3 P03）。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTLegacyKayokoImporter : NSObject

/// 生产入口：检测旧 Kayoko 数据目录与偏好 plist，存在则整体迁入 Metis
/// 剪切板数据目录与偏好域。幂等；任何失败只记日志，绝不阻断安装流程。
+ (void)importLegacyDataIfNeeded;

/// 可注入路径的核心实现（宿主测试直接调用）。
/// sourceDirectory      旧 Kayoko 数据目录（含 history-v4.sqlite 等）。
/// legacyPlistPath      旧偏好 plist 文件（直接文件读取，不经 cfprefsd）。
/// targetDirectory      Metis 剪贴板数据目录（不存在则创建）。
/// domain               Metis 剪切板偏好域（cfprefsd 写入）。
/// 返回 NO 仅当文件阶段失败（此时不写 marker）；偏好合并失败记日志不影响返回值。
+ (BOOL)importFromDataDirectory:(NSString *)sourceDirectory
          legacyPreferencesPlist:(NSString *)legacyPlistPath
               intoDataDirectory:(NSString *)targetDirectory
             preferencesDomain:(NSString *)domain
                          error:(NSError **)error;

/// 附件阶段（images/ 与 rich-text/ 目录合并，同名跳过，幂等可独立续跑）；
/// 完成后把 marker 的 attachments 置 1。大体积数据由生产入口放后台队列调用。
+ (BOOL)mergeAttachmentsFromDataDirectory:(NSString *)sourceDirectory
                        intoDataDirectory:(NSString *)targetDirectory
                                     error:(NSError **)error;

/// marker 文件路径（宿主测试断言用）。
+ (NSString *)markerPathForDataDirectory:(NSString *)dataDirectory;

@end

NS_ASSUME_NONNULL_END
