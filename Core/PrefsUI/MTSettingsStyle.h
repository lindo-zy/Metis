// MTSettingsStyle —— 设置页视觉 token（设计稿 metis-settings-v3.png）。
// 只用系统动态色与系统字体（02 §8：模块图标色仅作导航辅助，深浅色自适应）。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTSettingsStyle : NSObject

/// 瓦片色 token → 系统动态色；未知 token 返回 systemGray。
+ (UIColor *)tileColorForName:(nullable NSString *)name;

/// 系统图标；preferred 不可用时回退 fallback，两者都不可用返回 nil（行内隐藏瓦片）。
+ (nullable UIImage *)symbolPreferred:(NSString *)preferred fallback:(nullable NSString *)fallback;

+ (CGFloat)tileSide;            ///< 图标瓦片边长 29pt（系统设置惯例）
+ (CGFloat)tileCornerRadius;    ///< 连续圆角半径
+ (CGFloat)tileIconPointSize;   ///< 瓦片内白色符号点数
@end

NS_ASSUME_NONNULL_END
