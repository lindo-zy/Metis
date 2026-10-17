#import <UIKit/UIKit.h>
#import "../Common/PXGeometry.h"
#import "../Common/PXShellXBridge.h"

NS_ASSUME_NONNULL_BEGIN

@class PXSelectionView;

@protocol PXSelectionViewDelegate <NSObject>
/// 确认选区。action 为用户明确选择的动作（Save/Copy）。
- (void)selectionView:(PXSelectionView *)view
   didConfirmDisplayRect:(CGRect)displayRect
                 action:(PXOutputAction)action;
- (void)selectionViewDidCancel:(PXSelectionView *)view;
/// 仅区域模式：抓取当前画面并锁定为选框背景，不改变选区。
- (void)selectionViewDidRequestFreeze:(PXSelectionView *)view;
- (void)selectionViewDidRequestEditor:(PXSelectionView *)view displayRect:(CGRect)displayRect;
/// 工具栏“悬浮”按钮：把选区裁剪结果以可拖动悬浮窗常驻屏幕（不执行输出动作）。
- (void)selectionViewDidRequestFloat:(PXSelectionView *)view displayRect:(CGRect)displayRect;
/// 工具栏“滚动截图”按钮（仅区域模式出现）：以当前选区为采集裁片进入自动滚动会话。
- (void)selectionViewDidRequestLong:(PXSelectionView *)view displayRect:(CGRect)displayRect;
/// 工具栏 SHELLX 按钮：把流程外调给 SHELLX（通知发送由协调器负责，本视图不感知可用性）。
- (void)selectionViewDidRequestShellXAction:(PXSelectionView *)view action:(PXShellXAction)action;
/// 工具栏“全屏标记”按钮：无视当前框选内容，收掉选区后直接以全屏进入标记面板。
- (void)selectionViewDidRequestFullscreenMarkup:(PXSelectionView *)view;
/// 自定义 URL 按钮点击：url 来自 SelectionCustomButtons 记录，由协调器收掉选区后打开。
- (void)selectionView:(PXSelectionView *)view didRequestCustomURL:(NSURL *)url;
@end

/// 区域/冻结/即时模式共用的选区交互层。
/// 区域模式默认透明显示实时画面；冻结/即时模式显示抓屏快照。
/// 坐标转换由协调器使用任务的几何快照完成。
@interface PXSelectionView : UIView

@property (nonatomic, weak, nullable) id<PXSelectionViewDelegate> delegate;
@property (nonatomic, assign, readonly) CGRect selectionRect;

- (instancetype)initWithFrame:(CGRect)frame
                    baseImage:(nullable UIImage *)baseImage
                         mode:(PXCaptureMode)mode
                     delegate:(id<PXSelectionViewDelegate>)delegate;

/// 预置选区入口（显示坐标）：激活默认空选区，「记住上次选区」开启时由协调器传入历史矩形。
- (void)applyDefaultSelectionRect:(CGRect)rect;

/// 区域模式冻结成功后安装独立整屏快照；重复冻结和滚动截图入口随之禁用。
- (void)applyFrozenImage:(UIImage *)image;
/// 冻结失败时保持实时画面和选区，提示用户重试。
- (void)showFreezeFailure;

/// 关闭前清理手势与回调，防止销毁后残留调用。
- (void)prepareForDismissal;

@end

NS_ASSUME_NONNULL_END
