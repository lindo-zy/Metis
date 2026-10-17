#import <UIKit/UIKit.h>
#import "../Common/MTGeometry.h"
#import "../Common/MTCapturePreferences.h"

NS_ASSUME_NONNULL_BEGIN

/// 一次截图任务的唯一载体。字段命名与 DEVELOPMENT.md 4.1 对应。
/// 状态只允许 MTCaptureCoordinator 通过转换表修改；输出动作必须先 claim，保证幂等。
@interface MTCaptureTask : NSObject

@property (nonatomic, copy, readonly) NSString *taskID;
@property (nonatomic, assign, readonly) MTCaptureMode mode;
@property (nonatomic, assign, readonly) MTCaptureState state;
@property (nonatomic, strong, readonly) MTConfig *configSnapshot;

/// 任务的屏幕几何快照：实时区域抓屏前后必须与这组值一致，选区换算使用这组值。
@property (nonatomic, assign, readonly) CGRect capturedScreenBounds;
@property (nonatomic, assign, readonly) CGFloat capturedScreenScale;

/// 归一化后的原始整屏截图（upright，scale = 屏幕缩放）；实时区域等待用户动作才抓屏。
@property (nonatomic, strong, nullable) UIImage *baseImage;
/// 区域模式的“冻结”按钮已锁定 baseImage；此后裁剪不再重抓屏。仅主线程读写。
@property (nonatomic, assign) BOOL areaFrameFrozen;
/// 当前结果图（裁剪/编辑后的输出源）。
@property (nonatomic, strong, nullable) UIImage *resultImage;
/// 结果图对应的磁盘文件（长截图为拼接产物 longshot.jpg）：气泡缩略图优先从此
/// 降采样，避免为小图整幅解码大图；非长截图任务为 nil，回退内存解码路径。
@property (nonatomic, copy, nullable) NSString *resultFilePath;
@property (nonatomic, assign) BOOL isPartialCapture;   // 回退路径仅捕获到 SpringBoard 自身窗口
@property (nonatomic, copy, nullable) NSString *savedAssetIdentifier;  // 相册写入成功后的资产 ID
@property (nonatomic, assign) BOOL isReedit;                           // 气泡重编辑产生的新任务
@property (nonatomic, copy, nullable) NSString *errorCode;
@property (nonatomic, copy, nullable) NSString *errorMessage;

- (instancetype)initWithMode:(MTCaptureMode)mode
                      config:(MTConfig *)config
                screenBounds:(CGRect)screenBounds
                 screenScale:(CGFloat)screenScale;

/// 状态迁移：仅当转换合法时生效（内部持锁）。返回是否成功。
- (BOOL)transitionToState:(MTCaptureState)target;

/// 当前状态（加锁读取，供后台线程做取消态复查）。
- (MTCaptureState)currentState;

/// 输出幂等：同一动作只会被认领一次，重复触发返回 NO。
- (BOOL)claimOutputAction:(MTOutputAction)action;
- (BOOL)isOutputActionClaimed:(MTOutputAction)action;
/// 输出失败后撤回认领，允许气泡入口重试。
- (void)unclaimOutputAction:(MTOutputAction)action;

/// 任务数据目录（临时文件），惰性创建。
- (NSString *)ensureTemporaryDirectory;
/// 已存在的任务数据目录；不创建。枚举/清理类调用用这个，避免让本应消失的目录复活。
- (nullable NSString *)existingTemporaryDirectory;

NS_ASSUME_NONNULL_END

@end
