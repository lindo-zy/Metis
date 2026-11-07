#import <UIKit/UIKit.h>
#import "../Common/MTDeviceFrameConfiguration.h"
#import "../Common/MTGeometry.h"

NS_ASSUME_NONNULL_BEGIN
/// 单次模态会话，不创建额外 UIWindow；completed=NO 为取消，configuration=nil 为恢复原图。
@interface MTDeviceFrameViewController : UIViewController
/// 设置页预配置：嵌入设置页，使用宿主导航栏保存配置。加载 view 前设置。
@property (nonatomic) BOOL configurationOnly;
+ (UIImage *)exampleImage;
- (instancetype)initWithImage:(UIImage *)unframedImage
                configuration:(nullable MTDeviceFrameConfiguration *)configuration
                   completion:(void (^)(BOOL completed, MTDeviceFrameConfiguration * _Nullable configuration, MTOutputAction action))completion;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
