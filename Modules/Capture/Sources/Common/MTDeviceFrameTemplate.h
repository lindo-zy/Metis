#import "MTDeviceFrameGeometry.h"

NS_ASSUME_NONNULL_BEGIN
@interface MTDeviceFrameTemplate : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) CGSize canvasSize;
@property (nonatomic, readonly) MTDeviceFrameQuad screenQuad;
@property (nonatomic, copy, readonly, nullable) NSString *overlayPath;
@property (nonatomic, readonly) CGFloat screenCornerRadius; // 以屏幕短边 393 为基准，0…100
@property (nonatomic, readonly) NSInteger kind; // 0 island, 1 notch, 2 home, 3 custom
+ (NSArray<MTDeviceFrameTemplate *> *)builtInTemplates;
+ (nullable NSDictionary *)parseConfigurationData:(NSData *)data;
+ (nullable instancetype)customTemplateWithDictionary:(NSDictionary *)dictionary
                                         identifier:(NSString *)identifier
                                        overlayPath:(NSString *)path;
- (NSDictionary *)dictionaryRepresentation;
@end
NS_ASSUME_NONNULL_END
