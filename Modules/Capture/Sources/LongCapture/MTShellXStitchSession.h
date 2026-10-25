#import <UIKit/UIKit.h>
#import "../Capture/MTLongShotSession.h"

NS_ASSUME_NONNULL_BEGIN

/// SHELLX 自动拼接长截图：截取一整屏原图后由 HID 滑动接管（滚动 → 等待
/// 画面稳定 → 抓帧配对），配对以正文区域对齐、按确认位移与正文边界入账；
/// 标题折叠等工具栏动画吸收拖动时自动再滚；有限恢复失败才暂停保留已截
/// 内容；导出只按入账记录裁带合并。displayRect 限定采集与滑动区域。
@interface MTShellXStitchSession : NSObject <MTLongShotSessionControl>
+ (instancetype)startWithTask:(MTCaptureTask *)task
                  displayRect:(CGRect)displayRect
                     delegate:(id<MTLongShotSessionDelegate>)delegate;

- (void)teardownForExternalCancel;

@property (nonatomic, assign, readonly) BOOL isFinished;

@end

NS_ASSUME_NONNULL_END
