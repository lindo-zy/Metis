#import <Foundation/Foundation.h>

// Foundation-only decoding: no adapter rating is ever used as live power.
@interface MTChargingSnapshot : NSObject
@property(nonatomic) BOOL connected;
@property(nonatomic) BOOL charging;
@property(nonatomic) BOOL fullyCharged;
@property(nonatomic) double level;
@property(nonatomic) double volts;
@property(nonatomic) double amps;
@property(nonatomic) double watts;
@property(nonatomic) double celsius;
/// 距充满还差多少 mAh（AppleRawMaxCapacity - AppleRawCurrentCapacity）。
/// 驱动只给百分比时无法换算，取值为 NAN。
@property(nonatomic) double remainingMilliampHours;
@property(nonatomic) NSInteger minutesToFull;
/// YES 表示按最近实测速度外推，并非系统的充满时间模型。
@property(nonatomic) BOOL rateEstimate;
+ (instancetype)snapshotWithProperties:(NSDictionary *)properties
                        fallbackLevel:(double)level connected:(BOOL)connected charging:(BOOL)charging;
/// 当前速度下所需分钟数；调用方须先取得稳定的实测充电速度。
/// 无法推算（容量不可得、电流低于涓流阈值、超过 1440 分钟）返回 -1。
+ (NSInteger)minutesToFullForRemainingMilliampHours:(double)remaining currentMilliamp:(double)current;
@end

// 有效的明确充满时间字段优先。缺失时，用至少 60 秒的容量增量和
// 平均净电流交叉核对；暂停、断开及采样中断后重新积累，不沿用旧速度。
@interface MTChargingEstimator : NSObject
- (void)reset;
- (void)updateSnapshot:(MTChargingSnapshot *)snapshot atTime:(NSTimeInterval)time;
@end
