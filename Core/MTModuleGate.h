// MTModuleGate.h —— 模块启停门控的唯一读取入口（03-architecture §4）。
// 权威域 com.lindo.metis：全局开关默认开，三个模块默认关（ADR-014）。
// 设置端是唯一写入者（MTConfigService）；运行端只读 + 监听 config-changed。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const MTConfigDomain;
extern NSString *const MTConfigChangedNotification;

extern NSString *const MTModuleCapture;
extern NSString *const MTModuleKeyboard;
extern NSString *const MTModuleClipboard;

/// 全部模块 ID，稳定顺序：截图 / 键盘 / 剪贴板。
extern NSArray<NSString *> *MTAllModuleIDs;

@interface MTModuleGate : NSObject

/// 总开关（key: enabled，缺省 YES）。总开关关闭时一切模块业务都被门控。
+ (BOOL)globalEnabled;

/// 模块开关（key: <module>Enabled，缺省 NO）。结果同时受总开关约束。
+ (BOOL)moduleEnabled:(NSString *)moduleID;

/// 显式读取模块自身开关（不看总开关）。诊断页使用。
+ (BOOL)moduleSwitchRaw:(NSString *)moduleID;

/// 已启用模块数量（诊断/首页状态行）。
+ (NSUInteger)enabledModuleCount;

/// 强制从权威域重读快照（config-changed 后由内部回调触发，也可手动调用）。
+ (void)reload;

/// 注册 config-changed 监听；queue 为 nil 时在主队列回调。
/// 返回的 token 供 removeObserver: 使用。回调内先自动 reload。
+ (id)addObserver:(nullable dispatch_queue_t)queue block:(void (^)(void))block;
+ (void)removeObserver:(id)token;

/// 当前快照（仅非敏感开关状态，供诊断导出）。
+ (NSDictionary<NSString *, NSNumber *> *)switchSnapshotForDiagnostics;

@end

NS_ASSUME_NONNULL_END
