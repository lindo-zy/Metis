#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Clipboard stores ordered bindings only. Action payloads always come from the global library.
@interface MTClipboardActionReferences : NSObject
+ (BOOL)supportsEntry:(NSDictionary *)entry;
+ (NSArray<NSDictionary *> *)actionsInDocument:(NSDictionary *)document slot:(NSString *)slot;
+ (NSDictionary *)document:(NSDictionary *)document settingActionIDs:(NSArray<NSString *> *)ids slot:(NSString *)slot;
+ (BOOL)setActionIDs:(NSArray<NSString *> *)ids slot:(NSString *)slot expectedRevision:(uint64_t)revision error:(NSError **)error;
// Settings-only one-time import. Existing legacy files remain as backups.
+ (NSDictionary *)document:(NSDictionary *)document importingText:(NSArray *)text image:(NSArray *)image doubleTapURL:(NSString *)url;

// 剪切板规则存文档顶层键 clipboardRules（原始字典数组；解析/校验用
// MTCaptureRule rulesFromDictionaries，本类保持不依赖规则引擎头）。
+ (NSArray<NSDictionary *> *)ruleDictionariesInDocument:(NSDictionary *)document;
+ (NSDictionary *)document:(NSDictionary *)document settingRuleDictionaries:(NSArray<NSDictionary *> *)rules;
// 一次性：把旧槽位绑定（text/image/image-double-tap）转换成「恒匹配」规则。
// 用户显式保存过规则或迁移标记已存在时为空操作；设置页加载与运行端首次分发各自触发。
+ (BOOL)migrateLegacySlotRulesIfNeeded:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
