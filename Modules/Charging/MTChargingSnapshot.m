#import "MTChargingSnapshot.h"
#include <math.h>
#include <stdint.h>

static NSString *MTChargeIdentityString(id value) {
    // Accept NUL-padded UTF-8 buffers in explicit identity fields.
    // Do not decode ManufacturerData, serial prefixes or other binary blobs.
    NSString *string = nil;
    if ([value isKindOfClass:NSString.class]) string = value;
    else if ([value isKindOfClass:NSData.class] && [value length] <= 512)
        string = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
    if (!string || string.length > 512) return nil;
    NSMutableCharacterSet *padding = [NSCharacterSet.whitespaceAndNewlineCharacterSet mutableCopy];
    [padding addCharactersInRange:NSMakeRange(0, 1)];
    string = [string stringByTrimmingCharactersInSet:padding];
    if (!string.length || string.length > 128 ||
        [string rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    if ([@[@"unknown", @"n/a", @"none", @"null", @"(null)", @"-", @"—", @"未知"] containsObject:string.lowercaseString]) return nil;
    return string;
}

static NSString *MTChargeIdentity(NSDictionary *properties, NSString *key) {
    NSString *value = MTChargeIdentityString(properties[key]);
    id nested = properties[@"BatteryData"];
    if (!value && [nested isKindOfClass:NSDictionary.class]) value = MTChargeIdentityString(nested[key]);
    return value ?: @"未知";
}

// iOS 电池服务没有厂商明文键，序列号前缀→封装厂是电池工具的通行对照
// （与电池助手 1.0.7 一致）。仅作上报字段缺失时的回退：未命中保持
// “未知”，不做更大表的猜测，来源差异不对外区分。
static NSDictionary<NSString *, NSString *> *MTChargeVendorBySerialPrefix(void) {
    static NSDictionary<NSString *, NSString *> *vendors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        vendors = @{ @"F5D": @"德赛", @"FG9": @"新普", @"F8Y": @"欣旺达", @"PS": @"品胜" };
    });
    return vendors;
}

static double MTChargeNumber(NSDictionary *dict, NSString *key) {
    id value = dict[key];
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NAN;
    double result = [value doubleValue];
    return isfinite(result) ? result : NAN;
}

// Some gauges publish the raw counters inside the nested BatteryData dictionary.
static double MTChargeNestedNumber(NSDictionary *dict, NSString *key) {
    double value = MTChargeNumber(dict, key);
    if (isfinite(value)) return value;
    id nested = dict[@"BatteryData"];
    return [nested isKindOfClass:NSDictionary.class] ? MTChargeNumber(nested, key) : NAN;
}

// Charge-time estimate. Below this current the pack is trickling or the charge
// is paused, and dividing by it would produce an hours-long meaningless number.
static const double MTChargeMinCurrentMilliamp = 50.0;
static const double MTChargeMaxMinutes = 1440.0;
// Above one hour the estimate is quantised so current noise cannot rewrite the
// text every second; below it, single minutes still carry real information.
static const double MTChargeCoarseMinutes = 60.0;
static const double MTChargeCoarseStep = 5.0;
// A few-mAh gauge recalibration is not a charge-direction reversal; absorb it
// in the window instead of discarding it. Larger jumps restart the clock.
static const double MTChargeGaugeJitterMilliampHours = 3.0;
// The window slope needs a few samples before it means anything; shorter
// spans stay with the instant estimate (or the held one).
static const NSTimeInterval MTChargeWindowMinSeconds = 20.0;

@implementation MTChargingSnapshot
+ (NSInteger)minutesToFullForRemainingMilliampHours:(double)remaining currentMilliamp:(double)current {
    if (!isfinite(remaining) || remaining <= 0) return -1;
    if (!isfinite(current) || current < MTChargeMinCurrentMilliamp) return -1;
    double minutes = remaining / current * 60.0;
    if (!isfinite(minutes) || minutes > MTChargeMaxMinutes) return -1;
    if (minutes >= MTChargeCoarseMinutes) return (NSInteger)(llround(minutes / MTChargeCoarseStep) * MTChargeCoarseStep);
    return MAX(1, (NSInteger)ceil(minutes));
}

+ (instancetype)snapshotWithProperties:(NSDictionary *)p
                        fallbackLevel:(double)level connected:(BOOL)connected charging:(BOOL)charging {
    MTChargingSnapshot *s = [self new];
    s.batteryManufacturer = MTChargeIdentity(p, @"Manufacturer");
    if ([s.batteryManufacturer isEqualToString:@"未知"]) {
        NSString *serial = MTChargeIdentityString(p[@"Serial"]);
        if (!serial && [p[@"BatteryData"] isKindOfClass:NSDictionary.class])
            serial = MTChargeIdentityString(p[@"BatteryData"][@"Serial"]);
        NSDictionary<NSString *, NSString *> *vendors = MTChargeVendorBySerialPrefix();
        for (NSString *prefix in vendors) {
            if ([serial hasPrefix:prefix]) {
                s.batteryManufacturer = vendors[prefix];
                break;
            }
        }
    }
    s.trickleObservedSeconds = NAN;
    s.connected = [p[@"ExternalConnected"] isKindOfClass:NSNumber.class] ? [p[@"ExternalConnected"] boolValue] : connected;
    s.charging = s.connected && ([p[@"IsCharging"] isKindOfClass:NSNumber.class] ? [p[@"IsCharging"] boolValue] : charging);
    double current = MTChargeNumber(p, @"CurrentCapacity"), maximum = MTChargeNumber(p, @"MaxCapacity");
    s.level = maximum > 0 && current >= 0 && current <= maximum ? current / maximum : level;
    if (!isfinite(s.level) || s.level < 0 || s.level > 1) s.level = NAN;
    s.fullyCharged = [p[@"FullyCharged"] isKindOfClass:NSNumber.class] ?
        [p[@"FullyCharged"] boolValue] : (isfinite(s.level) && s.level >= 0.999);
    if (s.fullyCharged) s.charging = NO;
    double mv = MTChargeNumber(p, @"Voltage");
    double ma = MTChargeNumber(p, @"InstantAmperage");
    NSString *currentKey = isfinite(ma) ? @"InstantAmperage" : @"Amperage";
    ma = MTChargeNumber(p, currentKey);
    if (ma > (double)INT64_MAX) ma = [p[currentKey] longLongValue];
    // Some drivers publish a signed 32-bit current wrapped in an unsigned word.
    if (ma >= 2147483648.0 && ma <= 4294967295.0) ma = (int32_t)(uint32_t)ma;
    s.volts = mv >= 2000 && mv <= 20000 ? mv / 1000.0 : NAN;
    s.amps = ma >= -20000 && ma <= 20000 ? ma / 1000.0 : NAN;
    // Preserve a negative (discharge) current; never abs() it into charging power.
    s.watts = s.connected && isfinite(s.volts) && isfinite(s.amps) ? MAX(0, s.volts * s.amps) : NAN;
    double temp = MTChargeNumber(p, @"Temperature"); // iOS battery gauge: hundredths of Celsius.
    if (!isfinite(temp) && [p[@"BatteryData"] isKindOfClass:NSDictionary.class])
        temp = MTChargeNumber(p[@"BatteryData"], @"Temperature");
    s.celsius = temp >= -2000 && temp <= 10000 ? temp / 100.0 : NAN;
    // Remaining charge in mAh. CurrentCapacity/MaxCapacity are percentages on
    // iOS, so only the raw counters (or a mAh-scaled pair) can give minutes.
    double rawMaximum = MTChargeNestedNumber(p, @"AppleRawMaxCapacity");
    double rawCurrent = MTChargeNestedNumber(p, @"AppleRawCurrentCapacity");
    s.currentMilliampHours = NAN;
    s.fullMilliampHours = NAN;
    s.designMilliampHours = MTChargeNestedNumber(p, @"DesignCapacity");
    if (s.designMilliampHours < 200 || s.designMilliampHours > 50000) s.designMilliampHours = NAN;
    // Cycle count is a static gauge counter published by the battery service
    // (AppleSmartBattery); some gauges keep it inside BatteryData instead.
    double cycles = MTChargeNestedNumber(p, @"CycleCount");
    s.cycleCount = cycles >= 0 && cycles <= 100000 ? cycles : NAN;
    // 健康度＝额定满充容量/设计容量（注册表原值，与 ChargeLimiter 同法）；
    // 不回退满充容量近似值，缺任一容量或商值不合理时保持 NAN 显示占位。
    double nominal = MTChargeNestedNumber(p, @"NominalChargeCapacity");
    if (isfinite(s.designMilliampHours) && nominal >= 200 && nominal <= 50000) {
        double health = nominal / s.designMilliampHours * 100.0;
        s.healthPercent = isfinite(health) && health >= 1 && health <= 300 ? health : NAN;
    } else s.healthPercent = NAN;
    if (rawCurrent >= 0 && rawCurrent <= 50000) {
        s.currentMilliampHours = rawCurrent; s.capacitySource = 1;
        if (rawMaximum >= 200 && rawMaximum <= 50000) s.fullMilliampHours = rawMaximum;
    } else if (maximum > 200 && maximum <= 50000 && current >= 0 && current <= maximum) {
        s.currentMilliampHours = current; s.fullMilliampHours = maximum; s.capacitySource = 2;
    }
    // DesignCapacity is nominal; it must never be substituted for today's FCC.
    s.remainingMilliampHours = s.fullMilliampHours >= s.currentMilliampHours ?
        s.fullMilliampHours - s.currentMilliampHours : NAN;
    // TimeRemaining can also mean discharge time. Only explicitly named
    // time-to-full fields are accepted, in minutes; 0/-1/65535 are not ETAs.
    s.minutesToFull = -1;
    if (s.charging && !s.fullyCharged) {
        for (NSString *key in @[@"AvgTimeToFull", @"Time to Full Charge"]) {
            double minutes = MTChargeNestedNumber(p, key);
            if (minutes >= 1 && minutes <= MTChargeMaxMinutes) {
                s.minutesToFull = (NSInteger)ceil(minutes); break;
            }
        }
    }
    return s;
}
@end

@interface MTChargingEstimator ()
@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *samples;
@property(nonatomic) NSInteger lastEstimateMinutes; // 充电期间估时不允许空窗的保持值
@property(nonatomic) BOOL lastEstimateRate;         // 保持值是否为速度外推（决定显示文案）
@property(nonatomic) NSTimeInterval taperStart;
@property(nonatomic) NSTimeInterval taperLast;
@property(nonatomic) BOOL taperCandidate;
@end

@implementation MTChargingEstimator
- (instancetype)init {
    if ((self = [super init])) _samples = [NSMutableArray array];
    return self;
}
- (void)reset {
    [self.samples removeAllObjects];
    self.taperCandidate = NO; self.taperStart = 0; self.taperLast = 0;
}
// 充电期间估时不允许空窗：输入暂缺或窗口刚被回校清空时保持上一次估时，
// 来源标注为 Held。从未产生过估时（如刚接电、电流仍低于阈值）才留空。
- (void)applyHeldEstimate:(MTChargingSnapshot *)snapshot {
    if (self.lastEstimateMinutes <= 0) return;
    snapshot.minutesToFull = self.lastEstimateMinutes;
    snapshot.etaSource = MTChargeEtaSourceHeld;
    snapshot.rateEstimate = self.lastEstimateRate;
}
// 瞬时电流直除兜底：窗口未成熟、刚被回校清窗、涓流观测期、同拍重复回调
// 都在此取得估时；仍无结果时保持上次估时，充电期间不允许无估时空窗。
- (void)fillInstantOrHeldEstimate:(MTChargingSnapshot *)snapshot remaining:(double)remaining ma:(double)ma {
    snapshot.minutesToFull = [MTChargingSnapshot minutesToFullForRemainingMilliampHours:remaining currentMilliamp:ma];
    if (snapshot.minutesToFull > 0) {
        snapshot.etaSource = MTChargeEtaSourceRateInstant;
        snapshot.rateEstimate = YES;
    } else {
        [self applyHeldEstimate:snapshot];
    }
}
- (void)updateSnapshot:(MTChargingSnapshot *)snapshot atTime:(NSTimeInterval)time {
    BOOL hasSystemEstimate = snapshot.minutesToFull > 0 && !snapshot.rateEstimate;
    snapshot.rateEstimate = NO;
    snapshot.trickleEstimated = NO;
    snapshot.trickleObservedSeconds = NAN;
    snapshot.etaSource = MTChargeEtaSourceNone;
    if (!snapshot.connected || !snapshot.charging || snapshot.fullyCharged) {
        snapshot.minutesToFull = -1;
        self.lastEstimateMinutes = -1; self.lastEstimateRate = NO;
        [self reset]; return;
    }
    // Not a hardware charging-stage flag. Require sustained high SOC, voltage
    // and low positive C-rate; label this as estimated, never infer from 80% alone.
    BOOL candidate = isfinite(time) && snapshot.level >= 0.9 && snapshot.volts >= 4.1 &&
        snapshot.amps > 0 && isfinite(snapshot.fullMilliampHours) &&
        snapshot.remainingMilliampHours > 0 &&
        snapshot.amps * 1000 <= snapshot.fullMilliampHours * 0.15;
    if (!candidate || !self.taperCandidate || time < self.taperLast || time - self.taperLast > 10) {
        self.taperStart = time;
    }
    self.taperCandidate = candidate;
    self.taperLast = time;
    if (candidate && time - self.taperStart >= 30) {
        snapshot.trickleEstimated = YES;
        snapshot.trickleObservedSeconds = time - self.taperStart;
    }
    double remaining = snapshot.remainingMilliampHours, ma = snapshot.amps * 1000.0;
    // The battery controller's explicit full-charge model accounts for taper;
    // don't overwrite it with a linear, instantaneous-current calculation.
    if (hasSystemEstimate) {
        [self.samples removeAllObjects];
        snapshot.etaSource = MTChargeEtaSourceSystem;
        self.lastEstimateMinutes = snapshot.minutesToFull; self.lastEstimateRate = NO;
        return;
    }
    snapshot.minutesToFull = -1;
    if (!isfinite(time) || !isfinite(remaining) || remaining <= 0 ||
        !isfinite(ma) || ma < MTChargeMinCurrentMilliamp) {
        if (candidate) [self.samples removeAllObjects]; else [self reset];
        [self applyHeldEstimate:snapshot];
        return;
    }
    // A constant-current extrapolation cannot predict the declining-current
    // tail, so the observed-rate window is dropped while taper is observed;
    // the estimates below still run so the card never goes blank.
    if (snapshot.trickleEstimated) { [self.samples removeAllObjects]; }
    NSDictionary *last = self.samples.lastObject;
    double delta = last ? time - [last[@"time"] doubleValue] : 0.0;
    // 采样中断、时间回退或超过容忍带的回校（剩余电量向上跳；或下降速度
    // 超过充电电流可能输送的两倍——都是电量计重校准而非真实充电进度）：
    // 只清观测窗口重新积累；充电未中断，估时显示由瞬时/保持值兜底。
    if (last && (delta < 0 || delta > 10 || remaining > [last[@"remaining"] doubleValue] + MTChargeGaugeJitterMilliampHours ||
        [last[@"remaining"] doubleValue] - remaining > 2.0 * ma * delta / 3600.0 + MTChargeGaugeJitterMilliampHours)) {
        [self.samples removeAllObjects];
        last = nil;
    }
    if (last && delta < 0.8) { // layout/reload callbacks aren't new samples
        [self fillInstantOrHeldEstimate:snapshot remaining:remaining ma:ma];
        if (snapshot.minutesToFull > 0) {
            self.lastEstimateMinutes = snapshot.minutesToFull;
            self.lastEstimateRate = snapshot.rateEstimate;
        }
        return;
    }
    [self.samples addObject:@{@"time": @(time), @"remaining": @(remaining), @"ma": @(ma)}];
    while (self.samples.count > 1 && time - [self.samples[0][@"time"] doubleValue] > 120)
        [self.samples removeObjectAtIndex:0];
    // 滑动窗最小二乘斜率：数 mAh 回校与量化台阶被整窗吸收，不再要求逐
    // 样本严格单调；斜率与电流积分互检通过才采信（回校不是已充入的电）。
    NSUInteger n = self.samples.count;
    if (n >= 2) {
        double t0 = [self.samples[0][@"time"] doubleValue];
        double elapsed = time - t0;
        if (elapsed >= MTChargeWindowMinSeconds) {
            double sumT = 0, sumR = 0, sumTT = 0, sumTR = 0;
            for (NSDictionary *sample in self.samples) {
                double t = [sample[@"time"] doubleValue] - t0, r = [sample[@"remaining"] doubleValue];
                sumT += t; sumR += r; sumTT += t * t; sumTR += t * r;
            }
            double denom = (double)n * sumTT - sumT * sumT;
            if (denom > 1e-6) {
                double rateMilliamp = -((double)n * sumTR - sumT * sumR) / denom * 3600.0; // mAh/s → mA
                double milliampSeconds = 0;
                for (NSUInteger i = 1; i < n; i++) {
                    NSDictionary *a = self.samples[i - 1], *b = self.samples[i];
                    milliampSeconds += ([a[@"ma"] doubleValue] + [b[@"ma"] doubleValue]) * 0.5 *
                        ([b[@"time"] doubleValue] - [a[@"time"] doubleValue]);
                }
                double averageMA = milliampSeconds / elapsed;
                BOOL consistent = isfinite(averageMA) && averageMA > 0 &&
                    rateMilliamp >= MTChargeMinCurrentMilliamp &&
                    rateMilliamp >= averageMA * 0.5 && rateMilliamp <= averageMA * 2.0;
                if (consistent) {
                    snapshot.minutesToFull = [MTChargingSnapshot minutesToFullForRemainingMilliampHours:remaining
                        currentMilliamp:MIN(averageMA, rateMilliamp)];
                    if (snapshot.minutesToFull > 0) { snapshot.etaSource = MTChargeEtaSourceRateWindow; snapshot.rateEstimate = YES; }
                }
            }
        }
    }
    // 接通电源第一拍即可用：窗口未成熟、刚被回校清窗或涓流观测期都按
    // 瞬时电流直除（沿用「按当前速度」标注），滑动窗成熟后动态替换。
    if (snapshot.minutesToFull <= 0) [self fillInstantOrHeldEstimate:snapshot remaining:remaining ma:ma];
    if (snapshot.minutesToFull > 0) {
        self.lastEstimateMinutes = snapshot.minutesToFull;
        self.lastEstimateRate = snapshot.rateEstimate;
    }
}
@end
