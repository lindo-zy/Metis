#import <UIKit/UIKit.h>

// 拖动摆放的阶段：宿主按阶段决定是否落盘（只有 Ended 写入，Cancelled 回滚）。
typedef NS_ENUM(NSInteger, MTQuickLauncherDragPhase) {
    MTQuickLauncherDragBegan = 0,
    MTQuickLauncherDragChanged,
    MTQuickLauncherDragEnded,
    MTQuickLauncherDragCancelled
};

@interface MTQuickLauncherView : UIView
@property(nonatomic, copy) void (^closeHandler)(void);
@property(nonatomic, copy) void (^selectHandler)(NSString *identifier);
// translation 为相对上一次回调的增量（父视图坐标系）。
@property(nonatomic, copy) void (^dragHandler)(MTQuickLauncherDragPhase phase, CGPoint translation);
// 双击 grabber 复位到默认停靠位。
@property(nonatomic, copy) void (^resetHandler)(void);
@property(nonatomic) BOOL launching;
- (void)beginWithFavorites:(NSArray<NSString *> *)favorites names:(NSDictionary<NSString *, NSString *> *)names
    aliases:(NSDictionary *)aliases usage:(NSDictionary *)usage;
- (void)endSession;
- (void)showOpenFailure;
// 外部（面板关闭、锁屏、键盘弹出）打断拖动，防止残留正在追踪的手势。
- (void)cancelDrag;
@end

// Bottom anchored; mirror the existing handle side. Landscape uses two columns.
// scale：面板大小百分比（80~100，缺省 100），由 MTQuickLauncherFrame 消费。
FOUNDATION_EXPORT CGRect MTQuickLauncherFrame(CGRect bounds, UIEdgeInsets safe, NSInteger side, CGFloat scale);
