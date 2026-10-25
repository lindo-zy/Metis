#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// 长截图算法（MTKeyLongShotAlgorithm）：
/// 0 = Metis 自适应滚动（MTLongShotSession，默认）；
/// 3 = SHELLX 自动拼接（正文对齐 + 稳定抓帧 + 有限恢复 + 记录制导出）。
/// 1/2 = 已移除的录制式与手动拼接，枚举值仅为旧配置迁移保留（读入时归到 3）。
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
