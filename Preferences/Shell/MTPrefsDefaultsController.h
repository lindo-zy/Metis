// MTPrefsDefaultsController —— 全局分类「默认行为」页（02-settings-ux §2 + 设计稿第二屏）。
// 按规范只承载「共用呈现与缺少上下文时的说明」：全部为已在执行链路生效的
// 行为说明，不提供装饰性开关（不实现无执行语义的设置）。
#import <Preferences/Preferences.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsDefaultsController : PSListController
@end

NS_ASSUME_NONNULL_END
