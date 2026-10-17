// MTConfigService.h —— 设置端配置写入服务（唯一写入者，03-architecture §4）。
// 只有 Preferences 宿主调用；写权威域并广播 config-changed。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTConfigService : NSObject

+ (void)setGlobalEnabled:(BOOL)enabled;
+ (void)setModule:(NSString *)moduleID enabled:(BOOL)enabled;
+ (void)flush;   // 同步落盘 + 广播（toggle 场景在设置完成后调用一次）

@end

NS_ASSUME_NONNULL_END
