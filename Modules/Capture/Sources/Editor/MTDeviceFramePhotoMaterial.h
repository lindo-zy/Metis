#import <UIKit/UIKit.h>
#import "MTDeviceFrameTemplateStore.h"

NS_ASSUME_NONNULL_BEGIN
@interface MTDeviceFramePhotoMaterial : NSObject
+ (nullable UIImage *)sourceImageForTemplate:(MTDeviceFrameTemplate *)frame error:(NSError **)error;
/// 预览与最终导入共用开孔逻辑；透明素材保留原遮罩。
+ (nullable UIImage *)overlayForImage:(UIImage *)image screenQuad:(MTDeviceFrameQuad)quad
                              cutout:(BOOL)cutout cornerRadius:(CGFloat)radius error:(NSError **)error;
+ (nullable MTDeviceFrameTemplate *)importImage:(UIImage *)image name:(NSString *)name
                                   screenQuad:(MTDeviceFrameQuad)quad cornerRadius:(CGFloat)radius error:(NSError **)error;
/// 透明素材保留原图遮罩；手动圆角只作用于截图，标志随素材配置持久化。
+ (nullable MTDeviceFrameTemplate *)importImage:(UIImage *)image name:(NSString *)name
                                   screenQuad:(MTDeviceFrameQuad)quad cornerRadius:(CGFloat)radius
                     adjustTransparentCorners:(BOOL)adjust error:(NSError **)error;
/// 在文件提供者回调内调用；先检查体积/像素，再解码并烘焙 EXIF 方向，保持实际分辨率。
+ (nullable UIImage *)imageFromPhotoURL:(NSURL *)URL error:(NSError **)error;
/// 重新定位已有素材时保持 PNG 的原始像素坐标，不应用 EXIF 旋转。
+ (nullable UIImage *)imageForTemplate:(MTDeviceFrameTemplate *)frame error:(NSError **)error;
/// 识别最大封闭透明区，忽略连接画布边缘的透明背景；未识别时给出可手动调整的初始区域。
+ (MTDeviceFrameQuad)suggestedScreenForImage:(UIImage *)image hasTransparentScreen:(BOOL *)transparent;
+ (nullable UIImage *)previewForImage:(UIImage *)image;
/// 放大查看时按需提供较清晰预览，最大边受 2400px 限制，不放大原图。
+ (nullable UIImage *)previewForImage:(UIImage *)image maximumEdge:(CGFloat)edge;
/// 已有透明开孔始终保留遮罩；普通图片 cutout=YES 时清除所选屏幕四边形。
+ (nullable MTDeviceFrameTemplate *)importImage:(UIImage *)image name:(NSString *)name
                                   screenQuad:(MTDeviceFrameQuad)quad cutout:(BOOL)cutout error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
