// MTSettingsRowCell —— 设计稿卡片行：图标瓦片 + 加粗标题 + 灰色摘要 + 箭头/开关。
#import <UIKit/UIKit.h>
#import "MTSettingsModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTSettingsRowCell : UITableViewCell
/// 按 row 配置；toggle 行挂 row.toggleHandler，link 行显示箭头，info 行不可选。
- (void)configureWithRow:(MTSettingsRow *)row;
@end

NS_ASSUME_NONNULL_END
