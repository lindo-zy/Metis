#import "MTChargingSnapshot.h"
#include <math.h>
#include <stdint.h>

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
    if (rawMaximum > 0 && rawCurrent >= 0 && rawCurrent <= rawMaximum)
        s.remainingMilliampHours = rawMaximum - rawCurrent;
    else if (maximum > 200 && current >= 0 && current <= maximum)
        s.remainingMilliampHours = maximum - current;
    else s.remainingMilliampHours = NAN;
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
@end

@implementation MTChargingEstimator
- (instancetype)init {
    if ((self = [super init])) _samples = [NSMutableArray array];
    return self;
}
- (void)reset { [self.samples removeAllObjects]; }
- (void)updateSnapshot:(MTChargingSnapshot *)snapshot atTime:(NSTimeInterval)time {
    BOOL hasSystemEstimate = snapshot.minutesToFull > 0 && !snapshot.rateEstimate;
    snapshot.rateEstimate = NO;
    if (!snapshot.connected || !snapshot.charging || snapshot.fullyCharged) {
        snapshot.minutesToFull = -1; [self reset]; return;
    }
    // The battery controller's explicit full-charge model accounts for taper;
    // don't overwrite it with a linear, instantaneous-current calculation.
    if (hasSystemEstimate) { [self reset]; return; }
    snapshot.minutesToFull = -1;
    double remaining = snapshot.remainingMilliampHours, ma = snapshot.amps * 1000.0;
    if (!isfinite(time) || !isfinite(remaining) || remaining <= 0 ||
        !isfinite(ma) || ma < MTChargeMinCurrentMilliamp) { [self reset]; return; }
    NSDictionary *last = self.samples.lastObject;
    double delta = time - [last[@"time"] doubleValue];
    if (last && (delta < 0 || delta > 10 || remaining > [last[@"remaining"] doubleValue] + 2)) {
        [self reset]; last = nil;
    }
    if (last && delta < 0.8) return; // layout/reload callbacks aren't new samples
    [self.samples addObject:@{@"time": @(time), @"remaining": @(remaining), @"ma": @(ma)}];
    while (self.samples.count > 1 && time - [self.samples[0][@"time"] doubleValue] > 120)
        [self.samples removeObjectAtIndex:0];
    NSDictionary *first = self.samples.firstObject;
    double elapsed = time - [first[@"time"] doubleValue];
    double gained = [first[@"remaining"] doubleValue] - remaining;
    if (elapsed < 60 || gained < 3) return; // don't amplify gauge quantisation
    double milliampSeconds = 0;
    for (NSUInteger i = 1; i < self.samples.count; i++) {
        NSDictionary *a = self.samples[i - 1], *b = self.samples[i];
        milliampSeconds += ([a[@"ma"] doubleValue] + [b[@"ma"] doubleValue]) * 0.5 *
            ([b[@"time"] doubleValue] - [a[@"time"] doubleValue]);
    }
    double averageMA = milliampSeconds / elapsed, observedMA = gained * 3600.0 / elapsed;
    // A gauge recalibration isn't charge delivered. Wait for a consistent
    // window rather than showing a confident number based on a capacity jump.
    if (observedMA < averageMA * 0.5 || observedMA > averageMA * 1.5) return;
    snapshot.minutesToFull = [MTChargingSnapshot minutesToFullForRemainingMilliampHours:remaining
        currentMilliamp:MIN(averageMA, observedMA)];
    snapshot.rateEstimate = snapshot.minutesToFull > 0;
}
@end
