#import <UIKit/UIKit.h>
#import "../Common/MTDeviceFrameConfiguration.h"
#import "../Common/MTGeometry.h"

NS_ASSUME_NONNULL_BEGIN
/// 单次模态会话，不创建额外 UIWindow；completed=NO 为取消，configuration=nil 为恢复原图。
@interface MTDeviceFrameViewController : UIViewController
/// 设置页预配置：只显示保存配置，不提供截图输出或原图选项。加载 view 前设置。
@property (nonatomic) BOOL configurationOnly;
- (instancetype)initWithImage:(UIImage *)unframedImage
                configuration:(nullable MTDeviceFrameConfiguration *)configuration
                   completion:(void (^)(BOOL completed, MTDeviceFrameConfiguration * _Nullable configuration, MTOutputAction action))completion;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
