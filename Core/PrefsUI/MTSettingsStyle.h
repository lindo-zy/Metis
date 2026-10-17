// MTSettingsStyle —— 设置页视觉 token（系统 grouped 风格，行内 SF Symbol 无底色）。
// 只用系统动态色与系统字体（02 §8：深浅色自适应）。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTSettingsStyle : NSObject

/// 系统图标；preferred 不可用时回退 fallback，两者都不可用返回 nil（行内隐藏图标）。
+ (nullable UIImage *)symbolPreferred:(NSString *)preferred fallback:(nullable NSString *)fallback;

+ (CGFloat)contentInset;        ///< 行内容左/右内边距 16pt（卡片内基准）
+ (CGFloat)tileSide;            ///< 图标槽位边长 29pt（系统设置惯例）
+ (CGFloat)tileIconPointSize;   ///< 行内 SF Symbol 点数
+ (CGFloat)tileTextGap;         ///< 图标与标题间距
@end

NS_ASSUME_NONNULL_END
