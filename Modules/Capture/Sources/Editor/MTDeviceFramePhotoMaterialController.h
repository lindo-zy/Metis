#import <UIKit/UIKit.h>
#import "MTDeviceFramePhotoMaterial.h"

NS_ASSUME_NONNULL_BEGIN
/// 仅在素材导入时校准一次；完成后持久化素材，截图仍走自动输出链路。
@interface MTDeviceFramePhotoMaterialController : UITableViewController
- (instancetype)initWithImage:(UIImage *)image preview:(UIImage *)preview
                suggestedQuad:(MTDeviceFrameQuad)quad transparentScreen:(BOOL)transparent
                   completion:(void (^)(MTDeviceFrameTemplate * _Nullable frame))completion;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
