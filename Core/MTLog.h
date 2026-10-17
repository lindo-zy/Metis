// MTLog.h —— 统一日志。规则（03-architecture §9）：syslog/os_log 输出，
// 禁止记录剪贴板正文、验证码、截图内容、API 密钥与完整个人路径。
#import <Foundation/Foundation.h>

/// 版本号由构建系统注入（MetisCore Makefile -DMETIS_PACKAGE_VERSION）。
extern NSString *const MTCoreVersionString;

/// 模块标签复用集合（模块适配器也可以传自定义标签）。
extern NSString *const MTLogModuleCore;
extern NSString *const MTLogModuleCapture;
extern NSString *const MTLogModuleKeyboard;
extern NSString *const MTLogModuleClipboard;
extern NSString *const MTLogModulePrefs;

/// 记录一条 [Metis][module] 前缀的 info 日志。fmt 只放状态/原因/计数。
#ifdef __cplusplus
extern "C" {
#endif
void MTLogInfo(NSString *module, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
void MTLogWarn(NSString *module, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
void MTLogError(NSString *module, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
#ifdef __cplusplus
}
#endif
