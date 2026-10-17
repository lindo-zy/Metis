// MTSettingsIconTileView —— 设置行系统 SF Symbol 图标（无底色，随 label 色，
// 与 iOS 系统设置行内图标一致）。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTSettingsIconTileView : UIView
/// 更新符号内容；iconName 为空时整块隐藏（无图标行）。
- (void)updateWithIconName:(nullable NSString *)iconName;
@end

NS_ASSUME_NONNULL_END
