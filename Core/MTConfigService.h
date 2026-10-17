// MTConfigService.h —— 设置端配置写入服务（唯一写入者，docs/development/03 §2）。
// 只有 Preferences 宿主调用；写权威域并广播 config-changed。
// 模块键（captureEnabled 等）已随 v3 退役，本服务只写唯一整体开关。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTConfigService : NSObject

+ (void)setGlobalEnabled:(BOOL)enabled;
+ (void)flush;   // 同步落盘 + 广播（toggle 场景在设置完成后调用一次）

@end

NS_ASSUME_NONNULL_END
