#import <Foundation/Foundation.h>

// 充满时间的来源。仅用于诊断日志与来源标注，不作为硬件阶段标志。
typedef NS_ENUM(NSUInteger, MTChargeEtaSource) {
    MTChargeEtaSourceNone = 0,
    MTChargeEtaSourceSystem,
    MTChargeEtaSourceRateWindow,
    MTChargeEtaSourceRateInstant,
    /// 输入暂缺或窗口刚被回校清空时保持的上一次估时。
    MTChargeEtaSourceHeld,
};

// Foundation-only decoding: no adapter rating is ever used as live power.
@interface MTChargingSnapshot : NSObject
/// 电池厂商：优先取服务上报字段，缺失时按序列号前缀查表回退，
/// 均未命中为“未知”。来源差异不对外区分。
@property(nonatomic, copy) NSString *batteryManufacturer;
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
/// 当前速度下所需分钟数；调用方须传入实时实测的充电电流。
/// 无法推算（容量不可得、电流低于涓流阈值、超过 1440 分钟）返回 -1。
+ (NSInteger)minutesToFullForRemainingMilliampHours:(double)remaining currentMilliamp:(double)current;
@end

// 有效的明确充满时间字段优先。缺失时接通电源第一拍即按瞬时电流给出带
// “按当前速度”标注的估时，滑动窗实测斜率成熟后替换之。电量计数 mAh 级
// 回校只清观测窗口、不清估时显示；输入暂缺或窗口刚被清空时保持上一次
// 估时，充电期间不允许出现无估时空窗。暂停、断开、充满才清空估时。
@interface MTChargingEstimator : NSObject
- (void)reset;
- (void)updateSnapshot:(MTChargingSnapshot *)snapshot atTime:(NSTimeInterval)time;
@end
