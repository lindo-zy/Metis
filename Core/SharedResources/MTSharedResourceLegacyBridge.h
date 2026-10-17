// MTSharedResourceLegacyBridge.h —— 键盘 legacy 视图 ↔ 共享资源 store 的双向适配
// （docs/development/04 §1/§6：单一配置源；旧编辑器与键盘运行时经本桥读写
//  共享定义，键盘域只保留宿主布局参数，不再持久化资源键）。
// 兼容层只负责旧引用转新 ID；切换完成后键盘域停止写旧动作数组。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTSharedResourceLegacyBridge : NSObject

/// 桥接接管的键盘域资源键：linkactions / panels / 分组 / 三个绑定表。
/// 这些键不再写入键盘域，读取一律由 store 导出视图覆盖。
+ (NSArray<NSString *> *)bridgedResourceKeys;

/// store 快照 → legacy 视图键值，覆盖写入 legacyPrefs（进程内字典）。
/// 沙盒宿主从 global-shared.plist 读快照后同样调用本方法合并。
+ (void)applyStoreSnapshot:(nullable NSDictionary *)snapshot toLegacyPreferences:(NSMutableDictionary *)legacyPrefs;

/// legacy 写入 → store 提交：按 selector/panelID 重导入资源数组。
/// 内容与当前 store 视图深度相等时不提交（revision 不递增）。
/// 仅在非沙盒写入端（Settings/SpringBoard）调用。
+ (BOOL)applyLegacyPreferences:(NSDictionary *)legacyPreferences error:(NSError **)error;

/// 从 legacy 键盘偏好构造完整 store 文档（迁移/导入共用）。
/// base 为 nil 时从空库开始；只替换来源为 keyboard 的资源，其余保留。
+ (NSDictionary *)documentByImportingLegacyPreferences:(NSDictionary *)legacyPreferences
                                           intoDocument:(nullable NSDictionary *)base;

/// 供设置端「绑定总览/引用管理」使用的 slot 注册表：
/// {bindingID: {legacyKey, slot, title}}，覆盖工具栏/Dock/状态栏既有槽位。
+ (NSDictionary<NSString *, NSDictionary *> *)knownBindingSlots;

@end

NS_ASSUME_NONNULL_END
