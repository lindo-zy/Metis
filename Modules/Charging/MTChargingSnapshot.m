#import "MTChargingSnapshot.h"
#include <math.h>
#include <stdint.h>

static double MTChargeNumber(NSDictionary *dict, NSString *key) {
    id value = dict[key];
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NAN;
    double result = [value doubleValue];
    return isfinite(result) ? result : NAN;
}

// Chart scale. The trace is redrawn once per second, so a scale derived from the
// live peak rescales the whole curve on every sample and reads as motion. Snap
// to fixed steps instead and let a step hold until the peak clearly leaves it.
static const double MTChargeAxisFloor = 5.0;
static const double MTChargeAxisHeadroom = 1.15;
static const double MTChargeAxisFallRatio = 1.5;
static const double MTChargeAxisSteps[] = {5, 7.5, 10, 15, 20, 25, 30, 40};

@implementation MTChargingSnapshot
+ (double)axisCeilingForPeak:(double)peak currentCeiling:(double)currentCeiling {
    double need = isfinite(peak) && peak > 0 ? peak * MTChargeAxisHeadroom : MTChargeAxisFloor;
    if (need < MTChargeAxisFloor) need = MTChargeAxisFloor;
    double step = 0;
    for (size_t i = 0; i < sizeof(MTChargeAxisSteps) / sizeof(MTChargeAxisSteps[0]); i++) {
        if (MTChargeAxisSteps[i] >= need) { step = MTChargeAxisSteps[i]; break; }
    }
    if (step <= 0) step = ceil(need / 5.0) * 5.0; // Above the ladder: round up to 5 W.
    if (!(currentCeiling > 0) || step > currentCeiling) return step;
    // Rising is immediate so a new peak is never clipped; falling needs real
    // headroom, otherwise the trace would oscillate across a step boundary.
    return step * MTChargeAxisFallRatio <= currentCeiling ? step : currentCeiling;
}

+ (instancetype)snapshotWithProperties:(NSDictionary *)p
                        fallbackLevel:(double)level connected:(BOOL)connected charging:(BOOL)charging {
    MTChargingSnapshot *s = [self new];
    s.connected = [p[@"ExternalConnected"] isKindOfClass:NSNumber.class] ? [p[@"ExternalConnected"] boolValue] : connected;
    s.charging = s.connected && ([p[@"IsCharging"] isKindOfClass:NSNumber.class] ? [p[@"IsCharging"] boolValue] : charging);
    double current = MTChargeNumber(p, @"CurrentCapacity"), maximum = MTChargeNumber(p, @"MaxCapacity");
    s.level = maximum > 0 && current >= 0 && current <= maximum ? current / maximum : level;
    if (!isfinite(s.level) || s.level < 0 || s.level > 1) s.level = NAN;
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
    double minutes = MTChargeNumber(p, @"TimeRemaining");
    s.minutesToFull = s.charging && minutes > 0 && minutes <= 1440 ? (NSInteger)ceil(minutes) : -1;
    return s;
}
@end
