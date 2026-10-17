#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// 本文件只允许依赖 Foundation / CoreGraphics，保证可以在 macOS 宿主上做单元测试。
// 头文件会同时被 .m（C）与 .xm/.mm（C++）包含，C 接口统一加 extern "C"。

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - 枚举定义

typedef NS_ENUM(NSInteger, MTCaptureMode) {
    MTCaptureModeFull = 0,
    MTCaptureModeArea = 1,
    MTCaptureModeFreeze = 2,
    MTCaptureModeInstant = 3,
    MTCaptureModeMarkup = 4,
    /// 全屏滚动截图：用户滚动页面，MTLongShotSession 自动采集拼接。
    MTCaptureModeLong = 5,
};

typedef NS_ENUM(NSInteger, MTCaptureState) {
    MTCaptureStateIdle = 0,
    MTCaptureStatePreparing = 1,
    MTCaptureStateCapturing = 2,
    MTCaptureStateCaptured = 3,
    MTCaptureStatePresenting = 4,
    MTCaptureStateEditing = 5,
    MTCaptureStateExporting = 6,
    MTCaptureStateFinished = 7,
    MTCaptureStateCancelling = 8,
    MTCaptureStateCancelled = 9,
    MTCaptureStateFailed = 10,
};

typedef NS_ENUM(NSInteger, MTOutputAction) {
    MTOutputActionSave = 0,
    MTOutputActionCopy = 1,
    MTOutputActionShare = 2,
    MTOutputActionSaveAndCopy = 3,
    MTOutputActionSaveAndDeleteSource = 4,
    /// 内部哨兵值：表示"使用配置的默认动作"/"仅显示预览气泡"，不作为相册/剪贴板动作执行。
    MTOutputActionPreviewOnly = 5,
};

// MARK: - 状态机（集中管理，禁止各控制器自行修改状态）

/// 任务状态机唯一合法转换表；非法转换返回 NO，调用方必须记录日志并忽略。
BOOL MTCaptureStateCanTransition(MTCaptureState from, MTCaptureState to);

/// 是否处于允许接受新任务的状态（Finished/Cancelled/Failed/Idle 之外均视为忙碌）。
BOOL MTCaptureStateIsBusy(MTCaptureState state);

// MARK: - 几何转换

/// 显示坐标（屏幕点）矩形 → 截图像素坐标矩形。
/// displayRect 必须落在 displayBounds 内；转换后向上/向下取整，保证不越界、不丢像素。
CGRect MTConvertDisplayRectToPixel(CGRect displayRect, CGSize displayBounds, CGSize pixelSize);

/// 将选区钳制在容器内，并强制不小于 minimumSize（点单位）。无法满足时返回零矩形。
CGRect MTClampSelectionRect(CGRect rect, CGSize containerSize, CGFloat minimumSize);

/// 保持悬浮图尺寸，只限制位置。大于屏幕时允许拖动查看两端，不缩图。
CGRect MTConstrainFloatingRect(CGRect frame, CGRect bounds);

/// 选区边缘吸附：distance<=0 时原样返回；拖动选框时四边独立判断——某边距容器
/// 对应边缘不超过 distance 时该边对齐到边缘（间隙为 0），同轴两侧都在阈值内取较近
/// 一侧。矩形大于容器时原样返回（交由钳制层处理）。
CGRect MTApplySelectionEdgeSnap(CGRect rect, CGSize containerSize, CGFloat distance);

/// 工具栏跟随选框：默认贴在选框下方并按选区水平居中；选框贴近屏幕底部放不下时
/// 改到选框上方。上下都放不下时比较与选区的重叠面积，选重叠较小的位置；同面积优先顶部。
/// 空选区时保持 preferredFrame（屏幕底部）位置。
CGRect MTPlaceSelectionToolbar(CGRect preferredFrame, CGRect selectionRect, CGRect availableBounds, CGFloat gap);

// MARK: - 展示辅助

NSString *MTStringFromCaptureMode(MTCaptureMode mode);
NSString *MTStringFromOutputAction(MTOutputAction action);
NSString *MTStringFromCaptureState(MTCaptureState state);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
