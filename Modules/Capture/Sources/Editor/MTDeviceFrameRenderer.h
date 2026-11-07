#import <UIKit/UIKit.h>
#import "../Common/MTDeviceFrameConfiguration.h"
#import "../Common/MTDeviceFrameTemplate.h"

NS_ASSUME_NONNULL_BEGIN
@interface MTDeviceFrameRenderer : NSObject
/// 后台同步合成；previewEdge 为 0 表示正式输出；失败不回退为未套壳图。
+ (nullable UIImage *)renderImage:(UIImage *)source
                   configuration:(MTDeviceFrameConfiguration *)configuration
                        template:(MTDeviceFrameTemplate *)frame
                     previewEdge:(CGFloat)previewEdge;
/// 素材编辑实时预览，overlay 已包含屏幕开孔，四角使用 overlay 的像素坐标。
+ (nullable UIImage *)renderImage:(UIImage *)source overlay:(UIImage *)overlay screenQuad:(MTDeviceFrameQuad)quad;
+ (UIColor *)backgroundColor:(NSInteger)index;
@end
NS_ASSUME_NONNULL_END
