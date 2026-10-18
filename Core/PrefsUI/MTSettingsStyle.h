// MTSettingsStyle —— 设置页视觉 token（系统 grouped 风格，行内 SF Symbol 无底色）。
// 只用系统动态色与系统字体（02 §8：深浅色自适应）。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTSettingsStyle : NSObject

/// 系统图标；preferred 不可用时回退 fallback，两者都不可用返回 nil（行内隐藏图标）。
+ (nullable UIImage *)symbolPreferred:(NSString *)preferred fallback:(nullable NSString *)fallback;

/// 设置条目统一 SF Symbol 样式：tileIconPointSize 大小 + AlwaysTemplate
/// （颜色由调用方 imageView tint 决定，全库统一蓝；App 图标不走此路）。
+ (nullable UIImage *)settingsSymbolImageNamed:(nullable NSString *)name;

+ (CGFloat)contentInset;        ///< 行内容左/右内边距 16pt（卡片内基准）
+ (CGFloat)tileSide;            ///< 图标槽位边长 29pt（系统设置惯例）
+ (CGFloat)tileIconPointSize;   ///< 行内 SF Symbol 点数
+ (CGFloat)tileTextGap;         ///< 图标与标题间距
+ (CGFloat)rowVerticalPadding;  ///< 文字栈上下内边距 12pt（单行条目 ≈44.7pt，对齐 iOS 设置 44pt 标准）
@end

NS_ASSUME_NONNULL_END
