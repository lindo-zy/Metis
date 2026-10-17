// MTUIKitEntry —— MetisUIKit.dylib 唯一 constructor。
// filter 是 com.apple.UIKit，因此本镜像也会被 SpringBoard 加载：
// 必须先分类进程，SpringBoard 中立即 return（03-architecture §1）。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "MTCore.h"
#import "common.h"

// Metis 门控变化 → 走 MetisKeyboard 既有 prefschanged 重载链（幂等 reload）。
static void MTUIKitPostPrefsChanged(void) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (CFStringRef)kPrefsChangedIdentifier, NULL, NULL, TRUE);
}

%ctor {
    MTProcessContext *context = [MTProcessContext currentContext];
    if ([context isSpringBoard]) {
        // 类注册不可避免，但绝不安装任何 hook / 启动任何业务。
        return;
    }
    if (context.kind == MTProcessKindUnsupported) {
        return;
    }
    [MTModuleGate addObserver:nil block:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            MTUIKitPostPrefsChanged();
            MTLogInfo(MTLogModuleKeyboard, @"state=gate-applied enabled=%d",
                      [MTModuleGate moduleEnabled:MTModuleKeyboard]);
        });
    }];
    setenv("METIS_UIKIT_LOADED", "1", 1);
    MTLogInfo(MTLogModuleCore,
              @"state=uikit-loaded version=%@ kind=%lu bundle=%@",
              MTCoreVersionString,
              (unsigned long)context.kind,
              context.bundleIdentifier);
    // 键盘/剪贴板 Helper 模块激活在迁入时挂接；所有业务读取 MTModuleGate。
}
