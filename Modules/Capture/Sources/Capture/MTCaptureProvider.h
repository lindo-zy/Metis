#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const MTCaptureErrorDomain;

typedef NS_ENUM(NSInteger, MTCaptureError) {
    MTCaptureErrorNoSource = 1,           // 所有抓取路径都不可用
    MTCaptureErrorCaptureFailed = 2,      // 抓屏返回空结果
    MTCaptureErrorUnexpectedGeometry = 3, // 抓屏结果与屏幕几何不一致，宁可失败也不产出错误裁剪
};

/// 截图能力适配层：私有 API 只允许出现在本层，全部运行期 dlsym 解析。
/// 多级抓取策略（按序尝试，取第一个成功者）：
///   1. private-uicreate     — UIKit 私有 _UICreateScreenUIImage（整屏合成图）
///   2. private-uigetscreen  — UIKit 私有 UIGetScreenImage（整屏缓冲）
///   3. fallback-snapshot    — 公开 UIScreen 快照视图渲染（只能捕到 SpringBoard 自身窗口，结果标记 partial）
/// 返回的图片已归一化：upright、image.size = 屏幕点尺寸、image.scale = 屏幕缩放。
/// 回调永远在主线程。
@interface MTCaptureProvider : NSObject

/// 启动时解析结果（供启动日志）：private-uicreate / private-uigetscreen / fallback-snapshot。
+ (NSString *)resolvedCaptureMethod;

/// 最近一次抓屏实际使用的策略（主线程更新）。
@property (nonatomic, copy, readonly, nullable) NSString *lastCaptureMethod;
/// 内存保护降级开关（主线程读写）：跳过窗口排除快照 API，优先整屏私有抓屏。
/// 图层捕获排除标记不属于外部接口调用，降级时仍然保持。
@property (nonatomic, assign) BOOL fallbackOnlyCapture;
/// 长截图浮窗优先保持可见：对传入窗口建立会话级图层捕获排除标记，
/// 服务端合成抓屏（_UICreateScreenUIImage/UIGetScreenImage）自动跳过标记图层，
/// 窗口全程可见、无逐帧隐藏闪烁；标记期间系统录屏同样看不到这些自有浮窗。
/// 排除标记不可用时回退 _snapshotExcludingWindows:withRect:；仍失败则明确报错，
/// 由会话暂停，绝不隐藏窗口或把悬浮窗截进画面。默认 NO，不改变其他截图调用方。
@property (nonatomic, assign) BOOL keepsExcludedWindowsVisible;
/// 连续采集专用：把抓屏表面绘制为独立 RGBA 位图，在回调前释放源图和临时对象。
@property (nonatomic, assign) BOOL detachesCapturedImage;
/// 抓屏后不恢复被隐藏的传入窗口（默认恢复）：窗口随即销毁的调用方用它避免
/// 「隐藏→恢复→再销毁」造成的多余可见闪烁，恢复或销毁时机由调用方决定。
@property (nonatomic, assign) BOOL keepsExcludedWindowsHiddenAfterCapture;

- (void)captureWithCompletion:(void (^)(UIImage *image,
                                        BOOL isPartial,
                                        NSString *captureMethod,
                                        NSError *error))completion;

/// 长截图专用：keepsExcludedWindowsVisible 为 YES 时建立/复用会话级图层捕获排除，
/// 窗口保持可见；否则先隐藏传入窗口并等两帧。归一化在后台完成，回调永远在主线程。
- (void)captureExcludingWindows:(NSArray<UIWindow *> *)windows
                    completion:(void (^)(UIImage *image, BOOL isPartial,
                                          NSString *captureMethod, NSError *error))completion;

/// 会话收尾时结束图层捕获排除并恢复图层标记（主线程）；
/// keepsExcludedWindowsVisible 会话必须在窗口销毁前调用。
- (void)endVisibleWindowExclusion;
@end

NS_ASSUME_NONNULL_END
