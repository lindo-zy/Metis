#import "MTWatermarkConfiguration.h"
#import "MTConstants.h"
#import <math.h>

static double MTWatermarkNumber(id value, double fallback, double minimum, double maximum) {
    if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) return fallback;
    return MAX(minimum, MIN(maximum, [value doubleValue]));
}
@implementation MTWatermarkConfiguration
- (instancetype)init {
    if ((self = [super init])) {
        _materialIdentifier = @"";
        _x = 0.95; _y = 0.95; _size = 0.25; _opacity = 0.8;
    }
    return self;
}
+ (instancetype)configurationWithDictionary:(NSDictionary *)dictionary {
    MTWatermarkConfiguration *style = [self new];
    if (![dictionary isKindOfClass:NSDictionary.class]) return style;
    id identifier = dictionary[@"material"];
    if ([identifier isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:identifier])
        style.materialIdentifier = identifier;
    style.enabled = [dictionary[@"enabled"] isKindOfClass:NSNumber.class] && [dictionary[@"enabled"] boolValue];
    style.scope = (NSInteger)MTWatermarkNumber(dictionary[@"scope"], 0, 0, 2);
    style.x = MTWatermarkNumber(dictionary[@"x"], style.x, 0, 1);
    style.y = MTWatermarkNumber(dictionary[@"y"], style.y, 0, 1);
    style.size = MTWatermarkNumber(dictionary[@"size"], style.size, 0.05, 1);
    style.opacity = MTWatermarkNumber(dictionary[@"opacity"], style.opacity, 0.05, 1);
    return style;
}
+ (instancetype)rememberedConfiguration {
    CFPreferencesAppSynchronize((__bridge CFStringRef)MTCapturePreferencesDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("WatermarkStyle"),
        (__bridge CFStringRef)MTCapturePreferencesDomain));
    return [self configurationWithDictionary:value];
}
- (NSDictionary *)dictionaryRepresentation {
    return @{@"material":self.materialIdentifier, @"enabled":@(self.enabled), @"scope":@(self.scope),
        @"x":@(self.x), @"y":@(self.y), @"size":@(self.size), @"opacity":@(self.opacity)};
}
- (BOOL)remember {
    CFPreferencesSetAppValue(CFSTR("WatermarkStyle"), (__bridge CFPropertyListRef)self.dictionaryRepresentation,
        (__bridge CFStringRef)MTCapturePreferencesDomain);
    return CFPreferencesAppSynchronize((__bridge CFStringRef)MTCapturePreferencesDomain);
}
- (id)copyWithZone:(NSZone *)zone {
    return [MTWatermarkConfiguration configurationWithDictionary:self.dictionaryRepresentation];
}
- (BOOL)appliesToFramedImage:(BOOL)framed {
    return self.enabled && (self.scope == 0 || (self.scope == 2) == framed);
}
- (CGRect)rectForCanvas:(CGSize)canvas material:(CGSize)material {
    if (!isfinite(canvas.width) || !isfinite(canvas.height) || !isfinite(material.width) ||
        !isfinite(material.height) || canvas.width <= 0 || canvas.height <= 0 || material.width <= 0 || material.height <= 0)
        return CGRectZero;
    CGFloat edge = MIN(canvas.width, canvas.height) * self.size;
    CGFloat scale = edge / MAX(material.width, material.height);
    CGSize size = CGSizeMake(material.width * scale, material.height * scale);
    return CGRectMake((canvas.width - size.width) * self.x, (canvas.height - size.height) * self.y, size.width, size.height);
}
@end
