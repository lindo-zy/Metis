#import <UIKit/UIKit.h>
#import "../Common/MTGeometry.h"
#import "../Common/MTLongShotOptions.h"

NS_ASSUME_NONNULL_BEGIN

@class MTCaptureTask;
@class MTLongShotSession;

/// 长截图会话统一出口。session 参数放宽为 id：同一委托同时服务
/// Metis、SHELLX 自动拼接与快速滚动截图会话。
@protocol MTLongShotSessionDelegate <NSObject>
/// 拼接成功。会话自身已开始收尾，协调器接手输出动作。
- (void)longShotSessionDidFinish:(id)session resultImage:(UIImage *)image;
/// 用户主动取消（HUD 取消键或锁屏）。会话已自行清理窗口与临时引用。
- (void)longShotSessionDidCancel:(id)session;
/// 拼接失败，走任务失败路径（记录诊断日志）。
- (void)longShotSessionDidFail:(id)session message:(NSString *)message;
@optional
/// 快速模式的复制/保存按钮显式指定输出动作，其余会话仍使用默认动作。
- (void)longShotSessionDidFinish:(id)session resultImage:(UIImage *)image outputAction:(MTOutputAction)action;
@end

/// 协调器持有的会话控制口，所有长截图算法都必须响应。
/// 不继承 MTLongShotSessionDelegate——delegate 是协调器，会话是事件源。
@protocol MTLongShotSessionControl <NSObject>
/// 外部取消（Darwin cancel / 失败路径）：只清理自身，不回调 delegate。幂等。
- (void)teardownForExternalCancel;
/// 会话是否已收尾（窗口已销毁）。
@property (nonatomic, assign, readonly) BOOL isFinished;
@end

/// 自动拼接：主线程连续滚动与采集、串行后台帧存储和导出。
/// 创建后等待「截取」，可暂停/继续；displayRect 限定采集范围。
/// 任务首屏快照不作为稍后截取的第一帧。
@interface MTLongShotSession : NSObject <MTLongShotSessionControl>
+ (instancetype)startWithTask:(MTCaptureTask *)task
                  displayRect:(CGRect)displayRect
                     delegate:(id<MTLongShotSessionDelegate>)delegate;

/// 外部取消（Darwin cancel / 失败路径）：只清理自身，不回调 delegate。幂等。
- (void)teardownForExternalCancel;

/// 会话是否已收尾（窗口已销毁）。
@property (nonatomic, assign, readonly) BOOL isFinished;

@end

NS_ASSUME_NONNULL_END
