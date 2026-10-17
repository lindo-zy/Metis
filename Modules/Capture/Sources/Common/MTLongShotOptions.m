#import "MTLongShotOptions.h"
#import "MTConstants.h"
#import <math.h>

static double MTLongShotNumber(NSDictionary *values, NSString *key, double fallback,
                                double minimum, double maximum, BOOL integer) {
    id value = values[key];
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
        return fallback;
    double number = [value doubleValue];
    if (!isfinite(number) || number < minimum || number > maximum || (integer && floor(number) != number))
        return fallback;
    return number;
}

@implementation MTLongShotOptions
+ (NSArray<NSString *> *)preferenceKeys {
    return @[MTKeyLongShotMode, MTKeyLongShotAutoScroll, MTKeyLongShotSampleInterval, MTKeyLongShotIdleInterval,
             MTKeyLongShotScrollDuration, MTKeyLongShotSettleDuration, MTKeyLongShotMaxSlices,
             MTKeyLongShotMaxCanvasHeight, MTKeyLongShotSliceQuality, MTKeyLongShotOutputQuality];
}
- (instancetype)initWithValues:(NSDictionary<NSString *, id> *)values {
    if ((self = [super init])) {
        // 新键优先；仅新键缺失时迁移旧开关。非法值回到默认自动；打开会话后仍须点截取才运行。
        id legacy = values[MTKeyLongShotAutoScroll];
        MTLongShotMode fallback = MTLongShotModeAutomatic;
        if (!values[MTKeyLongShotMode] && [legacy isKindOfClass:NSNumber.class] &&
            ([legacy doubleValue] == 0 || [legacy doubleValue] == 1))
            fallback = [legacy boolValue] ? MTLongShotModeAutomatic : MTLongShotModeSampling;
        _mode = (MTLongShotMode)MTLongShotNumber(values, MTKeyLongShotMode, fallback, 0, 2, YES);
        _autoScroll = _mode != MTLongShotModeSampling;
        _sampleInterval = MTLongShotNumber(values, MTKeyLongShotSampleInterval, 0.12, 0.08, 1, NO);
        _idleInterval = MTLongShotNumber(values, MTKeyLongShotIdleInterval, 0.5, _sampleInterval, 2, NO);
        if (_idleInterval < _sampleInterval) _idleInterval = _sampleInterval;
        _scrollDuration = MTLongShotNumber(values, MTKeyLongShotScrollDuration, 0.62, 0.25, 2, NO);
        _settleDuration = MTLongShotNumber(values, MTKeyLongShotSettleDuration, 0.7, 0.15, 2, NO); // ShellX 抬指后等 0.7s：指示条淡出+动画稳定
        _maxSlices = (NSInteger)MTLongShotNumber(values, MTKeyLongShotMaxSlices, 200, 2, 500, YES);
        _maxCanvasHeight = (NSInteger)MTLongShotNumber(values, MTKeyLongShotMaxCanvasHeight, 16384, 1024, 16384, YES);
        _sliceQuality = MTLongShotNumber(values, MTKeyLongShotSliceQuality, 0.95, 0.5, 1, NO);
        _outputQuality = MTLongShotNumber(values, MTKeyLongShotOutputQuality, 0.9, 0.5, 1, NO);
    }
    return self;
}
@end
