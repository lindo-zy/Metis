#import <UIKit/UIKit.h>
#import "MTDeviceFrameTemplateStore.h"

NS_ASSUME_NONNULL_BEGIN
@interface MTDeviceFramePhotoMaterial : NSObject
/// 在文件提供者回调内调用；先检查体积/像素，再解码并烘焙 EXIF 方向，保持实际分辨率。
+ (nullable UIImage *)imageFromPhotoURL:(NSURL *)URL error:(NSError **)error;
/// 识别最大封闭透明区，忽略连接画布边缘的透明背景；未识别时给出可手动调整的初始区域。
+ (MTDeviceFrameQuad)suggestedScreenForImage:(UIImage *)image hasTransparentScreen:(BOOL *)transparent;
+ (nullable UIImage *)previewForImage:(UIImage *)image;
/// cutout=YES 时清除选中屏幕四边形；NO 保留原 PNG 的圆角/摄像头透明遮罩。
+ (nullable MTDeviceFrameTemplate *)importImage:(UIImage *)image name:(NSString *)name
                                   screenQuad:(MTDeviceFrameQuad)quad cutout:(BOOL)cutout error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
