#import "MTDeviceFrameConfiguration.h"
#import "MTConstants.h"
#import <math.h>

@implementation MTDeviceFrameConfiguration
- (instancetype)init {
    if ((self = [super init])) {
        _templateIdentifier = @"island";
        _background = 3; _paddingFraction = 0.10; _shadow = YES; _autoLandscape = YES;
    }
    return self;
}
+ (instancetype)rememberedConfiguration {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("DeviceFrameStyle"),
                                                       (__bridge CFStringRef)MTCapturePreferencesDomain);
    id dictionary = CFBridgingRelease(value);
    return [self configurationWithDictionary:[dictionary isKindOfClass:NSDictionary.class] ? dictionary : nil];
}
+ (instancetype)configurationWithDictionary:(NSDictionary *)d {
    MTDeviceFrameConfiguration *c = [self new];
    if (![d isKindOfClass:NSDictionary.class]) return c;
    id identifier = d[@"template"];
    if ([identifier isKindOfClass:NSString.class] && [identifier length] > 0 && [identifier length] < 100 &&
        [identifier rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"] invertedSet]].location == NSNotFound) {
        c.templateIdentifier = identifier;
    }
    if ([d[@"body"] isKindOfClass:NSNumber.class]) c.bodyColor = MAX(0, MIN(3, [d[@"body"] integerValue]));
    if ([d[@"background"] isKindOfClass:NSNumber.class]) c.background = MAX(0, MIN(3, [d[@"background"] integerValue]));
    if ([d[@"padding"] isKindOfClass:NSNumber.class] && isfinite([d[@"padding"] doubleValue]))
        c.paddingFraction = MAX(0, MIN(0.25, [d[@"padding"] doubleValue]));
    if ([d[@"shadow"] isKindOfClass:NSNumber.class]) c.shadow = [d[@"shadow"] boolValue];
    if ([d[@"landscape"] isKindOfClass:NSNumber.class]) c.autoLandscape = [d[@"landscape"] boolValue];
    if ([d[@"random"] isKindOfClass:NSNumber.class]) c.randomize = [d[@"random"] boolValue];
    return c;
}
- (NSDictionary *)dictionaryRepresentation {
    return @{@"template":self.templateIdentifier, @"body":@(self.bodyColor), @"background":@(self.background),
        @"padding":@(self.paddingFraction), @"shadow":@(self.shadow), @"landscape":@(self.autoLandscape), @"random":@(self.randomize)};
}
- (id)copyWithZone:(NSZone *)zone { return [MTDeviceFrameConfiguration configurationWithDictionary:self.dictionaryRepresentation]; }
- (void)remember {
    CFPreferencesSetAppValue(CFSTR("DeviceFrameStyle"), (__bridge CFPropertyListRef)self.dictionaryRepresentation,
                             (__bridge CFStringRef)MTCapturePreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)MTCapturePreferencesDomain);
}
@end
