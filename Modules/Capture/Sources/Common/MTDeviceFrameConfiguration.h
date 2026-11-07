#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface MTDeviceFrameConfiguration : NSObject <NSCopying>
@property (nonatomic, copy) NSString *templateIdentifier;
@property (nonatomic) NSInteger bodyColor;       // 0 石墨 1 银白 2 原色 3 蓝
@property (nonatomic) NSInteger background;      // 0 透明 1 雾白 2 深灰 3 浅紫
@property (nonatomic) double paddingFraction;    // 相对机壳短边，0…0.25
@property (nonatomic) BOOL shadow;
@property (nonatomic) BOOL autoLandscape;
@property (nonatomic) BOOL randomize;
+ (instancetype)rememberedConfiguration;
+ (instancetype)configurationWithDictionary:(nullable NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;
- (BOOL)remember;
@end
NS_ASSUME_NONNULL_END
