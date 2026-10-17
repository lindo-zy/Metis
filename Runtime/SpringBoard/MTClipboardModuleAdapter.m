// MTClipboardModuleAdapter —— Clipboard（MetisClipboard）模块的 Metis 挂接层。
// 门控变化转成 Mt 既有 preferences.reload 通知，运行端 reload 后
// isEnabled 即反映 MTModuleGate。说明：模块业务观察者在 SB 启动时按当时
// 门控安装（沿用 Mt 原语义），开关跨重启生效；首版标记“需重新载入桌面”。
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "MTCore.h"

static NSString *const MTClipboardPreferencesReloadName = @"com.lindo.metis.clipboard.preferences.reload";

__attribute__((constructor))
static void MTClipboardModuleAdapterLoad(void) {
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [MTModuleGate addObserver:nil block:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    (__bridge CFStringRef)MTClipboardPreferencesReloadName,
                    NULL, NULL, TRUE);
                MTLogInfo(MTLogModuleClipboard,
                          @"state=gate-applied enabled=%d",
                          [MTModuleGate globalEnabled]);
            });
        }];
    });
}
