// MTSpringBoardEntry —— MetisSpringBoard.dylib 唯一 constructor。
// 规则（03-architecture §3）：constructor 只做进程校验与非敏感启动门控；
// 需要启动完成的动作由各模块适配器在 SB 启动完成后自行激活。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "MTCore.h"

%ctor {
    // filter 已限定 SpringBoard；这里再校验一次，防止 filter 环境异常。
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
        return;
    }
    setenv("METIS_SPRINGBOARD_LOADED", "1", 1);
    MTLogInfo(MTLogModuleCore,
              @"state=sb-loaded version=%@ arm=%@",
              MTCoreVersionString,
              [NSString stringWithUTF8String:(sizeof(void *) == 8 ? "64" : "32")]);
    // 模块激活（capture/keyboard/clipboard）由各模块适配器在迁入时挂接。
}
