#import <UIKit/UIKit.h>
#import "../Capture/MTLongShotSession.h"

NS_ASSUME_NONNULL_BEGIN

/// SHELLX 拼接式长截图（LongCaptureMethod=1/2 的移植）：
/// 每次截取保存一整屏原图（full_%d.jpg），仅保留最近帧的下采样签名；auto=YES 时
/// 截完一屏由 HID 滑动接管（滚动 → 等待稳定 → 再截），行签名连续两次
/// 相同判定到底后自动收尾；结束时逐帧重算行签名，把原图重新拼接成片，
/// 无可靠重叠时暂停而不跳过内容。displayRect 限定采集与滑动区域。
@interface MTShellXStitchSession : NSObject <MTLongShotSessionControl>
+ (instancetype)startWithTask:(MTCaptureTask *)task
                  displayRect:(CGRect)displayRect
                     delegate:(id<MTLongShotSessionDelegate>)delegate
                        auto:(BOOL)automatic;

- (void)teardownForExternalCancel;

@property (nonatomic, assign, readonly) BOOL isFinished;

@end

NS_ASSUME_NONNULL_END
