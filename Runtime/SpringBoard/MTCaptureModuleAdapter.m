// MTCaptureModuleAdapter —— Capture（MetisCapture）模块的 Metis 挂接层。
// 职责（04-module-integration §3 的 v1 切片）：
//   1. 监听 com.lindo.metis/config-changed，把门控变化转成 MTCapturePreferences reload；
//   2. 模块开关关闭时拒绝新任务由 MTConfig.enabled 既有语义承担（迁入保持）。
// 完整 prepare/activate/deactivate 生命周期（MT-007 后续切片）在此扩展。
#import <Foundation/Foundation.h>
#import "MTCore.h"
#import "../../Modules/Capture/Sources/Common/MTCapturePreferences.h"

static id gConfigObserver;

__attribute__((constructor))
static void MTCaptureModuleAdapterLoad(void) {
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        gConfigObserver = [MTModuleGate addObserver:nil block:^{
            [MTCapturePreferences reload];
            MTLogInfo(MTLogModuleCapture,
                      @"state=config-applied enabled=%d",
                      [MTModuleGate moduleEnabled:MTModuleCapture]);
        }];
    });
}
