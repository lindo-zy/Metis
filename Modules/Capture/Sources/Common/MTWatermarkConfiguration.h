#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
@interface MTWatermarkConfiguration : NSObject <NSCopying>
@property (nonatomic) BOOL enabled;
@property (nonatomic, copy) NSString *materialIdentifier;
@property (nonatomic) NSInteger scope; // 0 所有截图，1 普通截图，2 套壳截图
@property (nonatomic) double x; // 水印在可移动范围内的相对位置，0…1
@property (nonatomic) double y;
@property (nonatomic) double size; // 相对成图短边，0.05…1
@property (nonatomic) double opacity;
+ (instancetype)rememberedConfiguration;
+ (instancetype)configurationWithDictionary:(nullable NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;
- (BOOL)remember;
- (BOOL)appliesToFramedImage:(BOOL)framed;
- (CGRect)rectForCanvas:(CGSize)canvas material:(CGSize)material;
@end
NS_ASSUME_NONNULL_END
