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
    return @[MTKeyLongShotAlgorithm, MTKeyLongShotScrollDuration, MTKeyLongShotSettleDuration, MTKeyLongShotMaxSlices,
             MTKeyLongShotMaxCanvasHeight, MTKeyLongShotSliceQuality, MTKeyLongShotOutputQuality];
}
- (instancetype)initWithValues:(NSDictionary<NSString *, id> *)values {
    if ((self = [super init])) {
        // 旧采样间隔/滚动模式不参与新算法配置；4 为独立的连续手动滚动模式。
        NSInteger rawAlgorithm = (NSInteger)MTLongShotNumber(values, MTKeyLongShotAlgorithm, 4, 0, 4, YES);
        // Removed adaptive mode (0) and absent/invalid values use the new default.
        // Earlier recording/manual values (1/2) retain their existing auto migration.
        _algorithm = (rawAlgorithm == 1 || rawAlgorithm == 2 || rawAlgorithm == 3)
            ? MTLongShotAlgorithmShellXAutoStitch : MTLongShotAlgorithmQuickScroll;
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
