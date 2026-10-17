// MTPasteServicesEntry —— MetisPasteServices.dylib constructor。
// 仅 druid/pasted 加载；这两个进程不做任何 UIKit/业务初始化。
#import <Foundation/Foundation.h>
#import "MTCore.h"

%ctor {
    MTProcessContext *context = [MTProcessContext currentContext];
    if (![context isPasteTipProcess]) {
        return;
    }
    MTLogInfo(MTLogModuleCore, @"state=paste-services-loaded process=%@", context.processName);
    // 粘贴提示 hook 在 Clipboard 模块迁入时挂接（默认关闭，用户启用才安装）。
}
