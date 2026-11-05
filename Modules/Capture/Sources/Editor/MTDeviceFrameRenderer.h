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
+ (UIColor *)backgroundColor:(NSInteger)index;
@end
NS_ASSUME_NONNULL_END
