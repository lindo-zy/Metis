// MTPrefsChangelogController —— 「更新说明」半屏内容（UIKit 渲染层）。
// 结构与配色见 docs/development/update-notes-plan.md：标题行（关闭按钮 + 居中标题）
// + 滚动区（版本块：版本标题 / 分隔线 / 彩色标签 + 悬挂缩进正文）。
// 半屏参数（detents / 抓取条 / 圆角）由入口方 MTPrefsRootController 配置。
#import <UIKit/UIKit.h>
#import "MTPrefsChangelogModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsChangelogController : UIViewController

+ (instancetype)controllerWithEntries:(NSArray<MTChangelogEntry *> *)entries
                                title:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
