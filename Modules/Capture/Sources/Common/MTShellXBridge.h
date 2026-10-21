#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 工具栏可外调的 SHELLX 功能全集（SHELLX 插件文档 2/3 节 + 逆向保留项）。
/// 通知类动作走 Darwin notify_post；URL 类动作走 prefs:// 打开（文档未给等价通知）。
typedef NS_ENUM(NSInteger, MTShellXAction) {
    MTShellXActionArea = 0,    // 普通框选（官方通知 open）
    MTShellXActionInstant,     // 即时（官方通知 open.instant）
    MTShellXActionFreeze,      // 冻结（官方通知 open.freeze）
    MTShellXActionHistory,     // 图片记录（官方通知 history）
    MTShellXActionOpenLast,    // 最近一张悬浮（官方通知 openlast，无最近图片时无反应）
    MTShellXActionClose,       // 关闭框选/长截图/拼接（官方通知 close）
    MTShellXActionLongShot,    // 长截图（URL shellx_long）
    MTShellXActionFullShot,    // 整屏截一张（通知 AssistiveScreenshot；真机实测：文档所记 URL shellx_full 实际是套壳）
    MTShellXActionMark,        // 全屏标记（URL shellx_mark）
    MTShellXActionEdit,        // 编辑（URL shellx_edit）
    MTShellXActionAI2,         // 文字问答（URL shellx_ai2）
    MTShellXActionTranslate,   // 全屏翻译（URL shellx_translate）
    MTShellXActionScan,        // 全屏扫码（URL shellx_scan）
    MTShellXActionAssistive,   // 套壳截图（URL shellx_full；真机实测：逆向名 AssistiveScreenshot 通知实际是整屏）
};

/// SHELLX 出向桥：运行时在场探测 + 通知/URL 双通道外调。
/// 与 MTShellXPlugin 的入向注册互补；未装 SHELLX 时一切调用为安全 no-op。
/// 工具栏按钮的显隐口径不在这里：由 MTEditorOrder.shellXInstalled（dylib 文件探测）
/// 决定，保证设置页（SHELLX 不注入）与截图界面看到同一套按钮。
@interface MTShellXBridge : NSObject

/// SHELLX 在场：SpringBoard 进程内能取到 SHELLXPluginManager 类（其 dylib 的
/// 全部通知观察者与该类同住，类在场即代表观察者已注册）。
+ (BOOL)isInstalled;
/// 通知类动作对应的 SHELLX 触发通知名（不检查可用性）；URL 类动作返回 nil。
/// 供调用方做自发自收抑制等配套处理。
+ (nullable NSString *)notificationNameForAction:(MTShellXAction)action;
/// URL 类动作对应的 prefs:// 路由（不检查可用性）；通知类动作返回 nil。
+ (nullable NSURL *)urlForAction:(MTShellXAction)action;
/// 外调一个 SHELLX 动作：通知类 notify_post，URL 类经 SpringBoard 的 UIApplication
/// openURL 打开（SHELLX 在 URL 分发层拦截；外部 URL scheme 入口已移除）。
/// 未装时只记日志不触发。
+ (void)notifyAction:(MTShellXAction)action;

@end

NS_ASSUME_NONNULL_END
