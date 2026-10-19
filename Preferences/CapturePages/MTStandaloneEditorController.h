#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 独立图片编辑宿主（设置页测试入口）。
///
/// 与区域截图的关系：只复用 MTEditorViewController 及其编辑器组件源码，
/// 不触碰 MTCaptureCoordinator / MTCaptureWindow，区域截图链路保持不变。
/// 图片来源：系统剪贴板优先；剪贴板无图时经 PHPicker 从相册导入。
///
/// 与区域截图的差异来自宿主进程约束，不是功能裁剪：
/// - 宿主是 Preferences.app，其 Info.plist 无 NSPhotoLibraryAddUsageDescription，
///   相册写入不可用；保存类动作统一降级为分享面板（由分享扩展完成入库）。
/// - 复制与分享两个动作由编辑器内部按钮自行完成，不经过本宿主的完成回调。
///
/// 生命周期由设置页控制器强引用持有；编辑器关闭后本对象可复用（再次 start）。
@interface MTStandaloneEditorController : NSObject

- (instancetype)initWithHostViewController:(UIViewController *)hostViewController NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 主线程调用。剪贴板有图直接进编辑器，无图先提示再从相册导入。
/// 返回 YES 表示本轮已启动；重复调用（上一轮未结束）或 host 不可呈现时返回 NO。
- (BOOL)start;

@end

NS_ASSUME_NONNULL_END
