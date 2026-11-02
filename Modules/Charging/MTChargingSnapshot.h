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
@end
