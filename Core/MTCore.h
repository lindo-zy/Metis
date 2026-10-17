// MTCore.h —— MetisCore 公共伞头。
// MetisCore.dylib 只承载 MT* 公共类型：日志、路径解析、进程分类、模块门控与
// 配置写入服务（03-architecture §1）。禁止把业务模块类编入本目标。
#import <Foundation/Foundation.h>
#import "MTLog.h"
#import "MTPathResolver.h"
#import "MTProcessContext.h"
#import "MTModuleGate.h"
#import "MTConfigService.h"
