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
    return @[MTKeyLongShotScrollDuration, MTKeyLongShotSettleDuration, MTKeyLongShotMaxSlices,
             MTKeyLongShotMaxCanvasHeight, MTKeyLongShotSliceQuality, MTKeyLongShotOutputQuality];
}
- (instancetype)initWithValues:(NSDictionary<NSString *, id> *)values {
    if ((self = [super init])) {
        // 仅保留自动拼接。旧 LongShotMode / LongShotAutoScroll / 采样间隔键不再读取，
        // 避免旧的手动或智能配置让新会话只采一次或等待用户滚动。
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
