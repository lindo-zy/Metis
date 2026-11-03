#import <UIKit/UIKit.h>
@class MTChargingSnapshot;

// 设计稿基准尺寸：绘制缩放与锁屏/预览两处布局共用同一比例，避免三处各写一份。
// static 修饰：宿主测试只编 Runtime+Snapshot（CardView 用桩类替代），头文件内联
// 取值即可，不产生对 MTChargingCardView.m 的链接依赖。
static const CGFloat MTChargingCardDesignWidth = 361.0;
static const CGFloat MTChargingCardDesignHeight = 268.0;

@interface MTChargingCardView : UIView
- (void)updateSnapshot:(MTChargingSnapshot *)snapshot;
@end
