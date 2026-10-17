#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MTCaptureTask;
@class MTResultBubble;

@protocol MTResultBubbleDelegate <NSObject>
/// 点击气泡主体（缩略图/文案区）：持有者按本次输出动作分流
/// （复制=关闭气泡；保存=进相册最近照片；其余进编辑器）。
- (void)resultBubbleDidTapBody:(MTResultBubble *)bubble;
/// 气泡完全关闭（含自动消失），持有者应释放引用。
- (void)resultBubbleDidDismiss:(MTResultBubble *)bubble;
@end

/// 结果预览气泡：独立小窗口，4 秒自动消失。成功态只显示缩略图（点击按
/// 本次输出动作分流）；失败态显示错误文字（诊断优先）。
/// 缩略图不参与任何相册链路。
@interface MTResultBubble : UIView

@property (nonatomic, weak, nullable) id<MTResultBubbleDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) MTCaptureTask *task;

+ (instancetype)presentWithImage:(nullable UIImage *)thumbnail
                         message:(NSString *)message
                            task:(nullable MTCaptureTask *)task
                       succeeded:(BOOL)succeeded
                        delegate:(id<MTResultBubbleDelegate>)delegate;

/// 主线程更新缩略图（后台渲染完成后回填；气泡已关闭时静默忽略）。
- (void)updateThumbnailImage:(UIImage *)image;

/// 幂等关闭；completion 主线程回调。
- (void)dismissWithCompletion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
