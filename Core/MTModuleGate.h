// MTModuleGate —— Metis 整体启停门控的唯一读取入口（docs/development/03 §2）。
// 权威域 com.lindo.metis：enabled 是唯一整体开关，缺省 YES。
// 旧 captureEnabled/keyboardEnabled/clipboardEnabled 模块键已退役（v3 P03）：
// 分类只是设置页面组织，不制造依赖开关；本类不再读取任何退役键。
// 设置端是唯一写入者（MTConfigService）；运行端只读 + 监听 config-changed。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const MTConfigDomain;
extern NSString *const MTConfigChangedNotification;

// 历史模块标识：仅供旧日志/迁移审计辨认来源，不参与任何启停判断。
extern NSString *const MTModuleCapture;
extern NSString *const MTModuleKeyboard;
extern NSString *const MTModuleClipboard;

@interface MTModuleGate : NSObject

/// 唯一整体开关（key: enabled，缺省 YES）。关闭时所有入口按同一快照停止。
+ (BOOL)globalEnabled;

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
