#import <Foundation/Foundation.h>

// 充满时间的来源。仅用于诊断日志与来源标注，不作为硬件阶段标志。
typedef NS_ENUM(NSUInteger, MTChargeEtaSource) {
    MTChargeEtaSourceNone = 0,
    MTChargeEtaSourceSystem,
    MTChargeEtaSourceRateWindow,
    MTChargeEtaSourceRateInstant,
};

// Foundation-only decoding: no adapter rating is ever used as live power.
@interface MTChargingSnapshot : NSObject
/// 电池服务原始上报信息；缺失或无效时为“未知”，不通过机型/容量推断。
/// 厂商可在无上报字段时按序列号前缀查表回退，并以推断标志区分来源。
@property(nonatomic, copy) NSString *batteryManufacturer;
/// YES 表示厂商来自序列号前缀查表推断，而非驱动上报字段。
@property(nonatomic) BOOL batteryManufacturerInferred;
@property(nonatomic) BOOL connected;
@property(nonatomic) BOOL charging;
@property(nonatomic) BOOL fullyCharged;
@property(nonatomic) double level;
@property(nonatomic) double volts;
@property(nonatomic) double amps;
@property(nonatomic) double watts;
@property(nonatomic) double celsius;
@property(nonatomic) double currentMilliampHours;
@property(nonatomic) double designMilliampHours;
@property(nonatomic) double fullMilliampHours;
/// 电池循环次数（驱动 CycleCount）；未上报或数值不合理时为 NAN。
@property(nonatomic) double cycleCount;
/// 电池健康度（NominalChargeCapacity/DesignCapacity×100，注册表原值）；
/// 任一容量缺失或不合理时为 NAN，由界面显示占位。
@property(nonatomic) double healthPercent;
@property(nonatomic) NSUInteger capacitySource;
/// 启发式识别，仅表示连续观测到低电流末段，不是硬件阶段标志。
@property(nonatomic) BOOL trickleEstimated;
@property(nonatomic) NSTimeInterval trickleObservedSeconds;
/// 距充满还差多少 mAh（AppleRawMaxCapacity - AppleRawCurrentCapacity）。
/// 驱动只给百分比时无法换算，取值为 NAN。
@property(nonatomic) double remainingMilliampHours;
@property(nonatomic) NSInteger minutesToFull;
/// YES 表示按最近实测速度外推，并非系统的充满时间模型。
@property(nonatomic) BOOL rateEstimate;
/// 当前 minutesToFull 的来源（MTChargeEtaSource）。
@property(nonatomic) NSUInteger etaSource;
+ (instancetype)snapshotWithProperties:(NSDictionary *)properties
                        fallbackLevel:(double)level connected:(BOOL)connected charging:(BOOL)charging;
/// 当前速度下所需分钟数；调用方须先取得稳定的实测充电速度。
/// 无法推算（容量不可得、电流低于涓流阈值、超过 1440 分钟）返回 -1。
+ (NSInteger)minutesToFullForRemainingMilliampHours:(double)remaining currentMilliamp:(double)current;
@end

// 有效的明确充满时间字段优先。缺失时，连续有效充电稳定 30 秒后先按瞬时
// 电流给出带“按当前速度”标注的估时，滑动窗实测斜率成熟后替换之。电量计
// 数 mAh 级回校不重置窗口；暂停、断开、采样中断及大幅回校后重新积累，
// 不沿用旧速度。涓流观测期内不显示任何估时。
@interface MTChargingEstimator : NSObject
- (void)reset;
- (void)updateSnapshot:(MTChargingSnapshot *)snapshot atTime:(NSTimeInterval)time;
@end
