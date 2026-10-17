// MTPNewActionTypeController —— 「新建动作」类型选择页（docs/development/02 §3
// + 设计稿第三屏）。替代原 UIAlertController 新建菜单：六类型固定顺序
// （URL Scheme、文本、打开应用、应用快捷方式、系统动作、JavaScript 脚本），
// 选中后回调宿主（自定义动作管理页）走既有 startAddFlowForType: 暂存条目 +
// 编辑器流程，本页不触碰 store。
#import "MTSettingsTableController.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTPNewActionTypeController : MTSettingsTableController
/// 选中类型回调（type 为 common.h 的 kCustomActionType* 字面量）。
@property (nonatomic, copy, nullable) void (^selectionHandler)(NSString *type);
@end

NS_ASSUME_NONNULL_END
