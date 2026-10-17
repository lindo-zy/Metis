#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - 包元数据（唯一命名来源，工程内禁止再硬编码）

/// 主 Bundle ID：com.lindo.metis.capture（外部身份标识，URL scheme / 错误域）
FOUNDATION_EXPORT NSString * const MTBundleID;
/// 偏好域：com.lindo.metis.capture（Metis 自有细节域；启停权威在 MTModuleGate）
FOUNDATION_EXPORT NSString * const MTCapturePreferencesDomain;

// MARK: - Darwin 跨进程通知名（只发请求信号，不携带图片对象）

FOUNDATION_EXPORT CFStringRef const MTDarwinActivate;          // com.lindo.metis.capture/activate（区域截图）
FOUNDATION_EXPORT CFStringRef const MTDarwinCaptureFull;        // com.lindo.metis.capture/full
FOUNDATION_EXPORT CFStringRef const MTDarwinCaptureArea;        // com.lindo.metis.capture/area
FOUNDATION_EXPORT CFStringRef const MTDarwinCaptureFreeze;      // com.lindo.metis.capture/freeze
FOUNDATION_EXPORT CFStringRef const MTDarwinCaptureInstant;     // com.lindo.metis.capture/instant
FOUNDATION_EXPORT CFStringRef const MTDarwinCaptureMarkup;      // com.lindo.metis.capture/markup
FOUNDATION_EXPORT CFStringRef const MTDarwinCaptureLong;        // com.lindo.metis.capture/long（全屏自动滚动，可切换手动）
FOUNDATION_EXPORT CFStringRef const MTDarwinCaptureCancel;      // com.lindo.metis.capture/cancel
FOUNDATION_EXPORT CFStringRef const MTDarwinPreferencesReload;  // com.lindo.metis.capture/preferences/reload

// MARK: - Snapper3 兼容别名（外部按 Snapper3 公开通知约定发信号即可触发 MetisCapture）

FOUNDATION_EXPORT CFStringRef const MTDarwinSnapperForceOpen;        // com.jontelang.snapper3.force.open → 区域截图
FOUNDATION_EXPORT CFStringRef const MTDarwinSnapperForceInstantOpen; // com.jontelang.snapper3.forceinstant.open → 即时区域截图
FOUNDATION_EXPORT CFStringRef const MTDarwinSnapperForceFreezeOpen;  // com.jontelang.snapper3.forcefreeze.open → 冻结截图
FOUNDATION_EXPORT CFStringRef const MTDarwinSnapperCloseAll;         // com.jontelang.snapper3.close.all → 取消当前任务
FOUNDATION_EXPORT CFStringRef const MTDarwinSnapperCloseCrop;        // com.jontelang.snapper3.closecrop → 取消当前任务

// MARK: - SHELLX 兼容别名（SHELLX 约定调用方在 Darwin 或 Distributed 任一中心发一条，
// 两个中心都必须监听；history/openlast/ready 无对应功能不注册）

FOUNDATION_EXPORT CFStringRef const MTDarwinShellXOpen;        // com.iosdump.screenshotshell.open → 区域截图
FOUNDATION_EXPORT CFStringRef const MTDarwinShellXOpenInstant; // com.iosdump.screenshotshell.open.instant → 即时区域截图
FOUNDATION_EXPORT CFStringRef const MTDarwinShellXOpenFreeze;  // com.iosdump.screenshotshell.open.freeze → 冻结截图
FOUNDATION_EXPORT CFStringRef const MTDarwinShellXClose;       // com.iosdump.screenshotshell.close → 取消当前任务

// MARK: - SHELLX 出向触发名（SHELLX 自己注册的观察者，MetisCapture 工具栏按钮 notify_post 外调用。
// 官方名逐字取自 SHELLX 插件文档第 2 节，文档保证 SHELLX 监听；其中区域/即时/冻结/关闭
// 与上方兼容别名同名，自发通知会被本方观察者收到，外调方必须做自发自收抑制。
// 历史版本走 Snapper3 别名（com.jontelang.snapper3.*），现按官方文档统一切换；
// AssistiveScreenshot 是文档外的逆向入口，继续沿用逆向报告。名字写错即静默无效，
// 改前必须用 SHELLX 插件文档或二进制字符串表核对）

FOUNDATION_EXPORT CFStringRef const MTShellXTriggerArea;      // com.iosdump.screenshotshell.open → 普通框选
FOUNDATION_EXPORT CFStringRef const MTShellXTriggerInstant;   // com.iosdump.screenshotshell.open.instant → 即时
FOUNDATION_EXPORT CFStringRef const MTShellXTriggerFreeze;    // com.iosdump.screenshotshell.open.freeze → 冻结
FOUNDATION_EXPORT CFStringRef const MTShellXTriggerHistory;   // com.iosdump.screenshotshell.history → 图片记录
FOUNDATION_EXPORT CFStringRef const MTShellXTriggerOpenLast;  // com.iosdump.screenshotshell.openlast → 最近一张悬浮
FOUNDATION_EXPORT CFStringRef const MTShellXTriggerClose;     // com.iosdump.screenshotshell.close → 关闭框选/长截图/拼接
FOUNDATION_EXPORT CFStringRef const MTShellXTriggerAssistive; // com.iosdump.screenshotshell/AssistiveScreenshot → 套壳截图

// MARK: - SHELLX 出向 URL 路由（SHELLX 插件文档第 3 节：prefs://root=shellx_*，
// 快捷指令与其余插件同链路调用。文档未给这些功能的等价通知，只能走 URL：
// 经 SpringBoard URL 分发层由 SHELLX 拦截（外部 URL scheme 入口已移除）

FOUNDATION_EXPORT CFStringRef const MTShellXRouteLong;      // prefs://root=shellx_long → 长截图
FOUNDATION_EXPORT CFStringRef const MTShellXRouteFull;      // prefs://root=shellx_full → 整屏截一张
FOUNDATION_EXPORT CFStringRef const MTShellXRouteMark;      // prefs://root=shellx_mark → 全屏标记
FOUNDATION_EXPORT CFStringRef const MTShellXRouteEdit;      // prefs://root=shellx_edit → 编辑
FOUNDATION_EXPORT CFStringRef const MTShellXRouteAI2;       // prefs://root=shellx_ai2 → 文字问答
FOUNDATION_EXPORT CFStringRef const MTShellXRouteTranslate; // prefs://root=shellx_translate → 全屏翻译
FOUNDATION_EXPORT CFStringRef const MTShellXRouteScan;      // prefs://root=shellx_scan → 全屏扫码

// MARK: - 进程内通知名（同样不携带图片对象，只提示协调器刷新）

FOUNDATION_EXPORT NSString * const MTNotificationResultUpdated; // com.lindo.metis.capture/result/updated

// MARK: - 偏好键（集中定义）

FOUNDATION_EXPORT NSString * const MTKeyEnabled;
FOUNDATION_EXPORT NSString * const MTKeyDefaultResultAction;
FOUNDATION_EXPORT NSString * const MTKeySaveAlsoCopy;
FOUNDATION_EXPORT NSString * const MTKeyAutoSaveToPhotos;
FOUNDATION_EXPORT NSString * const MTKeyCopyToClipboard;
FOUNDATION_EXPORT NSString * const MTKeyShowResultBubble;
FOUNDATION_EXPORT NSString * const MTKeyFloatingSnapShadow;
/// 选区边缘吸附距离（点）：0=关闭，>0=拖动选框时某边距屏幕边缘不超过该值即对齐边缘。
FOUNDATION_EXPORT NSString * const MTKeySelectionSnapEdgeDistance;
FOUNDATION_EXPORT NSString * const MTKeyShowCompletionNotification;
FOUNDATION_EXPORT NSString * const MTKeyMuteScreenshotSound;
FOUNDATION_EXPORT NSString * const MTKeyScreenshotHaptic;
FOUNDATION_EXPORT NSString * const MTKeyEditorDefaultColor;
FOUNDATION_EXPORT NSString * const MTKeyEditorDefaultLineWidth;
FOUNDATION_EXPORT NSString * const MTKeyEditorActionOrder;
FOUNDATION_EXPORT NSString * const MTKeyEditorToolOrder;
FOUNDATION_EXPORT NSString * const MTKeyEditorActionHidden;
FOUNDATION_EXPORT NSString * const MTKeyEditorToolHidden;
FOUNDATION_EXPORT NSString * const MTKeyEditorActionNames;
FOUNDATION_EXPORT NSString * const MTKeyEditorToolNames;
FOUNDATION_EXPORT NSString * const MTKeyEditorActionIcons;
FOUNDATION_EXPORT NSString * const MTKeyEditorToolIcons;
FOUNDATION_EXPORT NSString * const MTKeyEditorButtonIconSize;
FOUNDATION_EXPORT NSString * const MTKeySelectionButtonOrder;
FOUNDATION_EXPORT NSString * const MTKeySelectionButtonHidden;
FOUNDATION_EXPORT NSString * const MTKeySelectionButtonNames;
FOUNDATION_EXPORT NSString * const MTKeySelectionButtonIcons;
FOUNDATION_EXPORT NSString * const MTKeySelectionButtonIconStyle;
/// 选区工具栏自定义 URL 按钮：行记录 CSV（行间 \n、字段间 ,：id,name,icon,url）。
FOUNDATION_EXPORT NSString * const MTKeySelectionCustomButtons;
FOUNDATION_EXPORT NSString * const MTKeyAreaRememberLastRect;
FOUNDATION_EXPORT NSString * const MTKeyAreaLastSelectionRect;
FOUNDATION_EXPORT NSString * const MTKeyMarkupHandleOrigin;
FOUNDATION_EXPORT NSString * const MTKeyLongShotMode;
FOUNDATION_EXPORT NSString * const MTKeyLongShotAutoScroll; // 旧配置迁移
FOUNDATION_EXPORT NSString * const MTKeyLongShotSampleInterval;
FOUNDATION_EXPORT NSString * const MTKeyLongShotIdleInterval;
FOUNDATION_EXPORT NSString * const MTKeyLongShotScrollDuration;
FOUNDATION_EXPORT NSString * const MTKeyLongShotSettleDuration;
FOUNDATION_EXPORT NSString * const MTKeyLongShotMaxSlices;
FOUNDATION_EXPORT NSString * const MTKeyLongShotMaxCanvasHeight;
FOUNDATION_EXPORT NSString * const MTKeyLongShotSliceQuality;
FOUNDATION_EXPORT NSString * const MTKeyLongShotOutputQuality;

// MARK: - 默认值

FOUNDATION_EXPORT const NSInteger MTDefaultResultAction;             // MTOutputActionSave
FOUNDATION_EXPORT const CGFloat    MTDefaultEditorLineWidth;         // 4.0

// MARK: - 路径（集中管理，按需创建）

/// 截图任务临时文件根目录：<tmp>/PixPinTasks
NSString *MTTemporaryTasksRoot(void);

NS_ASSUME_NONNULL_END
