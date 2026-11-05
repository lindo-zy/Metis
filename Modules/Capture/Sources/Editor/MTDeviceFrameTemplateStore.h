#import "../Common/MTDeviceFrameTemplate.h"

NS_ASSUME_NONNULL_BEGIN
@interface MTDeviceFrameTemplateStore : NSObject
+ (NSArray<MTDeviceFrameTemplate *> *)templates;
+ (nullable MTDeviceFrameTemplate *)templateForIdentifier:(NSString *)identifier;
/// 在后台队列调用。传入已获取 security-scope 的 URL，只接受一份 PNG 和一份配置。
+ (nullable MTDeviceFrameTemplate *)importFiles:(NSArray<NSURL *> *)URLs error:(NSError **)error;
+ (BOOL)removeTemplate:(MTDeviceFrameTemplate *)frame error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
