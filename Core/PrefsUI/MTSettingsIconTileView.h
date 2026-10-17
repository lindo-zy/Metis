// MTSettingsIconTileView —— 设置行彩色图标瓦片（圆角方块 + 白色 SF 符号）。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTSettingsIconTileView : UIView
/// 更新瓦片内容；iconName 为空时整块隐藏（无图标行）。
- (void)updateWithIconName:(nullable NSString *)iconName colorName:(nullable NSString *)colorName;
@end

NS_ASSUME_NONNULL_END
