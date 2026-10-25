#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// 持有自有浮窗图层的捕获排除标记；主线程建立/清理，不改变可见性或触摸。
/// 长截图会话全程保持标记：抓屏 API 直接跳过这些图层，悬浮窗无需逐帧隐藏，
/// 消除「隐藏→抓屏→恢复」造成的每次抓帧闪烁。
@interface MTCaptureLayerExclusion : NSObject
@property (nonatomic, readonly, getter=isActive) BOOL active;
+ (nullable instancetype)beginWithLayers:(NSArray *)layers;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
