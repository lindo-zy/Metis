#import <UIKit/UIKit.h>
#import "MTQuickScrollMatcher.h"
#import "../Common/MTLongShotOptions.h"
#import "../Common/MTLongShotControl.h"

NS_ASSUME_NONNULL_BEGIN
@interface MTQuickScrollResult : NSObject
@property (nonatomic) MTQuickScrollMatch match;
@property (nonatomic) NSInteger count, totalHeight;
@property (nonatomic, strong, nullable) UIImage *preview;
/// 采集几何与会话基准不一致（旋转等）：会话暂停等待转回，不再直接失败。
@property (nonatomic) BOOL geometryMismatch;
@end

/// Serial normalization/analysis queue, with a separate serial spool queue.
/// Tracking and output references advance independently; confirmed strips are lossless.
@interface MTQuickScrollStore : NSObject
@property (atomic, readonly) CFAbsoluteTime exportProgressTime;
- (instancetype)initWithDirectory:(NSString *)directory options:(MTLongShotOptions *)options
                     cancellation:(MTLongShotCancellation *)cancellation scale:(CGFloat)scale;
- (nullable MTQuickScrollResult *)consumeImage:(UIImage *)image pixelRect:(CGRect)rect
                                    timestamp:(CFTimeInterval)timestamp final:(BOOL)final error:(NSError **)error;
- (nullable UIImage *)exportToURL:(NSURL *)url error:(NSError **)error;
/// Streamed PNG preserves native width and height without a full bitmap canvas.
- (NSString *)smartOutputName;
- (NSString *)smartOutputUTI;
- (CGFloat)smartOutputQuality;
@end
NS_ASSUME_NONNULL_END
