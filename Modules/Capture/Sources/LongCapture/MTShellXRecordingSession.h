#import <UIKit/UIKit.h>
#import "../Capture/MTLongShotSession.h"

NS_ASSUME_NONNULL_BEGIN

/// SHELLX 录制式长截图（LongCaptureMethod=0 的移植）：
/// 用户自行滚动页面，会话按自适应频率定时抓屏——画面变化时 0.12s、
/// 连续 4 帧未变降为 0.5s、静止 2s 进入空闲 10s 并显示 6s 自动保存倒计时；
/// 帧间用 20×20 JPEG 指纹去重，新增内容用条带 SAD 对齐后增量拼入；
/// 超屏数/内存紧张自动收尾；反向或无可靠重叠时暂停，保留已截内容供完成保存。
/// displayRect 限定采集区域。
@interface MTShellXRecordingSession : NSObject <MTLongShotSessionControl>
+ (instancetype)startWithTask:(MTCaptureTask *)task
                  displayRect:(CGRect)displayRect
                     delegate:(id<MTLongShotSessionDelegate>)delegate;

- (void)teardownForExternalCancel;

@property (nonatomic, assign, readonly) BOOL isFinished;

@end

NS_ASSUME_NONNULL_END
