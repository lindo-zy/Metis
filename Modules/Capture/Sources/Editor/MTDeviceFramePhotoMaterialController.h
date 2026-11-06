#import <UIKit/UIKit.h>
#import "MTDeviceFramePhotoMaterial.h"

NS_ASSUME_NONNULL_BEGIN
/// 素材导入/重新定位时校准；完成后持久化素材，截图仍走自动输出链路。
@interface MTDeviceFramePhotoMaterialController : UITableViewController
- (instancetype)initWithImage:(UIImage *)image preview:(UIImage *)preview
                suggestedQuad:(MTDeviceFrameQuad)quad transparentScreen:(BOOL)transparent
                   completion:(void (^)(MTDeviceFrameTemplate * _Nullable frame))completion;
/// 保留已有素材，校准结果另存为新素材；默认保留原 PNG 遮罩。
- (instancetype)initWithTemplate:(MTDeviceFrameTemplate *)frame image:(UIImage *)image preview:(UIImage *)preview
                     completion:(void (^)(MTDeviceFrameTemplate * _Nullable frame))completion;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
