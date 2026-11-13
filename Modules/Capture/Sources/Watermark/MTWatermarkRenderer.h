#import <UIKit/UIKit.h>
#import "../Common/MTWatermarkConfiguration.h"

NS_ASSUME_NONNULL_BEGIN
@interface MTWatermarkRenderer : NSObject
+ (NSArray<NSString *> *)materials;
+ (nullable UIImage *)materialForIdentifier:(NSString *)identifier;
+ (nullable NSString *)importURL:(NSURL *)url error:(NSError **)error;
+ (BOOL)removeMaterial:(NSString *)identifier error:(NSError **)error;
/// 后台调用。保留像素尺寸与透明通道，配置启用但素材不可读时返回 nil。
+ (nullable UIImage *)renderImage:(UIImage *)image configuration:(MTWatermarkConfiguration *)style framed:(BOOL)framed;
@end
NS_ASSUME_NONNULL_END
