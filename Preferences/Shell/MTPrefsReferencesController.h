// MTPrefsReferencesController —— 引用管理：资源到入口的反向索引（02 §2）。
// 只读展示每个动作/面板被哪些入口引用；删除动作时的引用清理由编辑事务承担。
#import <Preferences/Preferences.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsReferencesController : PSListController
@end

NS_ASSUME_NONNULL_END
