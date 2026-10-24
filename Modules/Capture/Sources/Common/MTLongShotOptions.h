#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// 长截图算法（MTKeyLongShotAlgorithm）：
/// 0 = Metis 自适应滚动（MTLongShotSession，默认）；
/// 1 = SHELLX 录制式（用户滚动，定时抓屏 + 帧哈希去重 + SAD 对齐增量拼接）；
/// 2 = SHELLX 手动拼接（逐屏抓原图，结束时按行签名统一重拼）；
/// 3 = SHELLX 自动拼接（2 的自动滑动循环，到底自动收尾）。
typedef NS_ENUM(NSInteger, MTLongShotAlgorithm) {
    MTLongShotAlgorithmMetis = 0,
    MTLongShotAlgorithmShellXRecording = 1,
    MTLongShotAlgorithmShellXManualStitch = 2,
    MTLongShotAlgorithmShellXAutoStitch = 3,
};

/// 每个任务的不可变参数快照；内存安全底线不属于可配置项。
@interface MTLongShotOptions : NSObject
@property (nonatomic, readonly) MTLongShotAlgorithm algorithm;
@property (nonatomic, readonly) NSTimeInterval scrollDuration;
@property (nonatomic, readonly) NSTimeInterval settleDuration;
@property (nonatomic, readonly) NSInteger maxSlices;
@property (nonatomic, readonly) NSInteger maxCanvasHeight;
@property (nonatomic, readonly) double sliceQuality;
@property (nonatomic, readonly) double outputQuality;
- (instancetype)initWithValues:(NSDictionary<NSString *, id> *)values;
+ (NSArray<NSString *> *)preferenceKeys;
@end
NS_ASSUME_NONNULL_END
