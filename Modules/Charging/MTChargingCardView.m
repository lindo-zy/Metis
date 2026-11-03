#import "MTChargingCardView.h"
#import "MTChargingSnapshot.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@interface MTChargingCardInk : UIView
@property(nonatomic, strong) MTChargingSnapshot *snapshot;
@end

static UIColor *MTChargeGreen(void) { return [UIColor colorWithRed:0.44 green:0.93 blue:0.67 alpha:1]; }
static void MTChargeText(NSString *text, CGRect rect, CGFloat size, UIFontWeight weight, UIColor *color, NSTextAlignment align) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = align;
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName:color, NSParagraphStyleAttributeName:style}];
}
static NSString *MTChargeValue(double value, NSUInteger decimals, NSString *unit) {
    return isfinite(value) ? [NSString stringWithFormat:@"%.*f%@", (int)decimals, value, unit] : @"—";
}

@implementation MTChargingCardInk
- (void)drawRect:(CGRect)rect {
    MTChargingSnapshot *s = self.snapshot;
    if (!s) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGContextScaleCTM(context, self.bounds.size.width / MTChargingCardDesignWidth, self.bounds.size.height / MTChargingCardDesignHeight);
    UIColor *white = UIColor.whiteColor, *muted = [white colorWithAlphaComponent:0.64], *green = MTChargeGreen();
    NSString *power = MTChargeValue(s.watts, 1, @"");
    MTChargeText(power, CGRectMake(17, 13, 210, 58), 44, UIFontWeightSemibold, white, NSTextAlignmentLeft);
    CGFloat unitX = 21 + [power sizeWithAttributes:@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:44 weight:UIFontWeightSemibold]}].width;
    MTChargeText(@"W", CGRectMake(MIN(unitX, 227), 23, 24, 25), 17, UIFontWeightBold, green, NSTextAlignmentLeft);
    MTChargeText(@"实时功率 · 电池侧", CGRectMake(18, 69, 205, 19), 11, UIFontWeightSemibold, muted, NSTextAlignmentLeft);
    CGPoint center = CGPointMake(310, 50);
    UIBezierPath *track = [UIBezierPath bezierPathWithArcCenter:center radius:27 startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
    track.lineWidth = 4.5; [[white colorWithAlphaComponent:0.13] setStroke]; [track stroke];
    if (isfinite(s.level) && s.level > 0) {
        UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:center radius:27 startAngle:-M_PI_2 endAngle:-M_PI_2 + M_PI * 2 * s.level clockwise:YES];
        ring.lineWidth = 4.5; ring.lineCapStyle = kCGLineCapRound; [green setStroke]; [ring stroke];
    }
    MTChargeText(isfinite(s.level) ? [NSString stringWithFormat:@"%.0f%%", s.level * 100] : @"—", CGRectMake(280, 35, 60, 23), 16, UIFontWeightBold, white, NSTextAlignmentCenter);
    MTChargeText(@"电量", CGRectMake(280, 56, 60, 17), 9, UIFontWeightSemibold, muted, NSTextAlignmentCenter);
    [[white colorWithAlphaComponent:0.1] setStroke];
    UIBezierPath *dividers = [UIBezierPath bezierPath];
    [dividers moveToPoint:CGPointMake(17, 96)]; [dividers addLineToPoint:CGPointMake(344, 96)];
    [dividers moveToPoint:CGPointMake(17, 153)]; [dividers addLineToPoint:CGPointMake(344, 153)];
    for (NSNumber *x in @[@121, @239]) { [dividers moveToPoint:CGPointMake(x.doubleValue, 108)]; [dividers addLineToPoint:CGPointMake(x.doubleValue, 141)]; }
    for (NSNumber *x in @[@121, @239]) { [dividers moveToPoint:CGPointMake(x.doubleValue, 164)]; [dividers addLineToPoint:CGPointMake(x.doubleValue, 202)]; }
    dividers.lineWidth = 0.35; [dividers stroke];
    NSArray *titles = @[@"电压", @"电流", @"电池温度"];
    NSArray *values = @[MTChargeValue(s.volts, 2, @" V"), MTChargeValue(s.amps, 2, @" A"), MTChargeValue(s.celsius, 1, @" °C")];
    for (NSUInteger i = 0; i < 3; i++) {
        CGFloat x = i == 0 ? 18 : (i == 1 ? 136 : 254);
        MTChargeText(titles[i], CGRectMake(x, 108, 90, 17), 10, UIFontWeightSemibold, muted, NSTextAlignmentLeft);
        MTChargeText(values[i], CGRectMake(x, 125, 95, 24), 16, UIFontWeightSemibold, white, NSTextAlignmentLeft);
    }
    // 最大容量取满充容量（AppleRawMaxCapacity）；部分电量计的 DesignCapacity
    // 会镜像剩余容量，百分比电量计的 MaxCapacity 也与剩余容量同刻度，
    // 都不能当作“最大”展示。
    NSArray *capacityTitles = @[@"实时容量", @"最大容量", @"循环次数"];
    NSArray *capacityValues = @[MTChargeValue(s.currentMilliampHours, 0, @" mAh"),
        MTChargeValue(s.fullMilliampHours, 0, @" mAh"), MTChargeValue(s.cycleCount, 0, @" 次")];
    for (NSUInteger i = 0; i < 3; i++) {
        CGFloat x = i == 0 ? 18 : (i == 1 ? 136 : 254);
        MTChargeText(capacityTitles[i], CGRectMake(x, 164, 95, 17), 10, UIFontWeightSemibold, muted, NSTextAlignmentLeft);
        MTChargeText(capacityValues[i], CGRectMake(x, 182, 95, 24), 14, UIFontWeightSemibold, white, NSTextAlignmentLeft);
    }
    MTChargeText([NSString stringWithFormat:@"厂商：%@%@", s.batteryManufacturer ?: @"未知",
        s.batteryManufacturerInferred ? @"（推断）" : @""],
        CGRectMake(18, 211, 154, 17), 10, UIFontWeightMedium, muted, NSTextAlignmentLeft);
    NSString *health = isfinite(s.healthPercent) ?
        [NSString stringWithFormat:@"%.0f%%", s.healthPercent] : @"—";
    MTChargeText([NSString stringWithFormat:@"健康度：%@", health],
        CGRectMake(184, 211, 160, 17), 10, UIFontWeightMedium, muted, NSTextAlignmentLeft);
    NSString *status = !s.connected ? @"未充电" : (s.fullyCharged ? @"已充满" :
        (s.trickleEstimated ? @"涓流估测" : (s.charging ? @"正在充电" : @"充电已暂停")));
    CGRect badge = CGRectMake(17, 240, 88, 20);
    [[green colorWithAlphaComponent:0.14] setFill]; [[UIBezierPath bezierPathWithRoundedRect:badge cornerRadius:10] fill];
    MTChargeText(status, CGRectMake(20, 243, 82, 16), 10, UIFontWeightSemibold, green, NSTextAlignmentCenter);
    NSString *eta = !s.connected ? @"尚未接入电源" : (s.fullyCharged ? @"电量已充满" : (!s.charging ? @"充电已暂停" :
        (s.minutesToFull > 0 ? [NSString stringWithFormat:s.rateEstimate ? @"按当前速度约 %ld 分钟" : @"预计约 %ld 分钟充满",
            (long)s.minutesToFull] : @"正在估算充电时间")));
    if (s.trickleEstimated) {
        NSString *observed = s.trickleObservedSeconds < 60 ?
            [NSString stringWithFormat:@"已观测 %.0f 秒", floor(s.trickleObservedSeconds)] :
            [NSString stringWithFormat:@"已观测 %.0f 分钟", floor(s.trickleObservedSeconds / 60)];
        eta = [NSString stringWithFormat:@"%@ · %@", observed,
            s.minutesToFull > 0 ? [NSString stringWithFormat:@"预计约 %ld 分钟", (long)s.minutesToFull] : @"余时估算中"];
    }
    MTChargeText(eta, CGRectMake(112, 243, 231, 16), 10, UIFontWeightMedium, muted, NSTextAlignmentRight);
    CGContextRestoreGState(context);
}
@end

@interface MTChargingCardView ()
@property(nonatomic, strong) MTChargingCardInk *ink;
@end
@implementation MTChargingCardView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.layer.cornerRadius = 28; self.layer.cornerCurve = kCACornerCurveContinuous; self.clipsToBounds = YES;
        self.layer.borderWidth = 0.5; self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
        blur.frame = self.bounds; blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:blur];
        self.ink = [[MTChargingCardInk alloc] initWithFrame:self.bounds];
        self.ink.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.42]; self.ink.opaque = NO;
        self.ink.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.ink];
        self.isAccessibilityElement = YES;
    }
    return self;
}
- (void)updateSnapshot:(MTChargingSnapshot *)snapshot {
    self.ink.snapshot = snapshot; [self.ink setNeedsDisplay];
    self.accessibilityLabel = [NSString stringWithFormat:@"充电详情，电量 %@，电池侧功率 %@，电压 %@，电流 %@，温度 %@，实时容量 %@，最大容量 %@，循环次数 %@，电池厂商 %@%@，电池健康度 %@",
        MTChargeValue(snapshot.level * 100, 0, @"%"), MTChargeValue(snapshot.watts, 1, @"瓦"),
        MTChargeValue(snapshot.volts, 2, @"伏"), MTChargeValue(snapshot.amps, 2, @"安"), MTChargeValue(snapshot.celsius, 1, @"摄氏度"),
        MTChargeValue(snapshot.currentMilliampHours, 0, @"毫安时"), MTChargeValue(snapshot.fullMilliampHours, 0, @"毫安时"),
        MTChargeValue(snapshot.cycleCount, 0, @""),
        snapshot.batteryManufacturer ?: @"未知",
        snapshot.batteryManufacturerInferred ? @"（按序列号前缀推断）" : @"",
        MTChargeValue(snapshot.healthPercent, 0, @"%"),
        snapshot.trickleEstimated ? [NSString stringWithFormat:@"，涓流阶段为估测，已连续观测 %.0f 秒", floor(snapshot.trickleObservedSeconds)] : @""];
}
@end
