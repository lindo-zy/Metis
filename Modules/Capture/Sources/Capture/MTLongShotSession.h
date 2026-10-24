#import <UIKit/UIKit.h>
#import "../Common/MTGeometry.h"
#import "../Common/MTLongShotOptions.h"

NS_ASSUME_NONNULL_BEGIN

@class MTCaptureTask;
@class MTLongShotSession;

@protocol MTLongShotSessionDelegate <NSObject>
/// 拼接成功。会话自身已开始收尾，协调器接手输出动作。
- (void)longShotSessionDidFinish:(MTLongShotSession *)session resultImage:(UIImage *)image;
/// 用户主动取消（HUD 取消键或锁屏）。会话已自行清理窗口与临时引用。
- (void)longShotSessionDidCancel:(MTLongShotSession *)session;
/// 拼接失败，走任务失败路径（记录诊断日志）。
- (void)longShotSessionDidFail:(MTLongShotSession *)session message:(NSString *)message;
@end

/// 自动拼接：主线程连续滚动与采集、串行后台帧存储和导出。
/// 创建后等待「截取」，可暂停/继续；displayRect 限定采集范围。
/// 任务首屏快照不作为稍后截取的第一帧。
@interface MTLongShotSession : NSObject
+ (instancetype)startWithTask:(MTCaptureTask *)task
                  displayRect:(CGRect)displayRect
                     delegate:(id<MTLongShotSessionDelegate>)delegate;

/// 外部取消（Darwin cancel / 失败路径）：只清理自身，不回调 delegate。幂等。
- (void)teardownForExternalCancel;

/// 会话是否已收尾（窗口已销毁）。
@property (nonatomic, assign, readonly) BOOL isFinished;

@end

NS_ASSUME_NONNULL_END
