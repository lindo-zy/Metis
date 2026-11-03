#import <Foundation/Foundation.h>

// Foundation-only decoding: no adapter rating is ever used as live power.
@interface MTChargingSnapshot : NSObject
@property(nonatomic) BOOL connected;
@property(nonatomic) BOOL charging;
@property(nonatomic) double level;
@property(nonatomic) double volts;
@property(nonatomic) double amps;
@property(nonatomic) double watts;
@property(nonatomic) double celsius;
/// 距充满还差多少 mAh（AppleRawMaxCapacity - AppleRawCurrentCapacity）。
/// 驱动只给百分比时无法换算，取值为 NAN。
@property(nonatomic) double remainingMilliampHours;
@property(nonatomic) NSInteger minutesToFull;
+ (instancetype)snapshotWithProperties:(NSDictionary *)properties
                        fallbackLevel:(double)level connected:(BOOL)connected charging:(BOOL)charging;
/// 近 60 秒曲线的纵轴上限。按固定档位吸附并带回落滞环：档位只跨越一次，
/// 不会因为每秒采样的小幅波动把整条曲线重新缩放。currentCeiling <= 0 表示尚未建立。
+ (double)axisCeilingForPeak:(double)peak currentCeiling:(double)currentCeiling;
/// 充满所需分钟数 = 剩余容量 / 充电电流，由本进程按实测值推算，
/// 不采用驱动内部的 TimeRemaining（长期平滑模型，末段会给出数小时量级的估值）。
/// 无法推算（容量不可得、电流低于涓流阈值、超过 1440 分钟）返回 -1。
+ (NSInteger)minutesToFullForRemainingMilliampHours:(double)remaining currentMilliamp:(double)current;
@end
