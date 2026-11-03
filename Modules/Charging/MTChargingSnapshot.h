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
@property(nonatomic) NSInteger minutesToFull;
+ (instancetype)snapshotWithProperties:(NSDictionary *)properties
                        fallbackLevel:(double)level connected:(BOOL)connected charging:(BOOL)charging;
/// 近 60 秒曲线的纵轴上限。按固定档位吸附并带回落滞环：档位只跨越一次，
/// 不会因为每秒采样的小幅波动把整条曲线重新缩放。currentCeiling <= 0 表示尚未建立。
+ (double)axisCeilingForPeak:(double)peak currentCeiling:(double)currentCeiling;
@end
