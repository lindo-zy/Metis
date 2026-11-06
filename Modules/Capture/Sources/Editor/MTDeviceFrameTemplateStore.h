#import "../Common/MTDeviceFrameTemplate.h"
#import "../Common/MTDeviceFrameConfiguration.h"

NS_ASSUME_NONNULL_BEGIN
@interface MTDeviceFrameTemplateStore : NSObject
+ (NSArray<MTDeviceFrameTemplate *> *)templates;
+ (nullable MTDeviceFrameTemplate *)templateForIdentifier:(NSString *)identifier;
/// 每个请求只选择一次；失效素材明确失败，不静默替换用户配置。
+ (nullable MTDeviceFrameTemplate *)resolveTemplateForConfiguration:(MTDeviceFrameConfiguration *)configuration
                                                        templates:(NSArray<MTDeviceFrameTemplate *> *)templates;
/// 在后台队列调用。传入已获取 security-scope 的 URL，只接受一份 PNG 和一份配置。
+ (nullable MTDeviceFrameTemplate *)importFiles:(NSArray<NSURL *> *)URLs error:(NSError **)error;
/// 文件与相册共用的验证/原子落盘入口，配置坐标对应 PNG 实际像素。
+ (nullable MTDeviceFrameTemplate *)importPNGData:(NSData *)data configuration:(NSDictionary *)configuration error:(NSError **)error;
+ (BOOL)removeTemplate:(MTDeviceFrameTemplate *)frame error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
