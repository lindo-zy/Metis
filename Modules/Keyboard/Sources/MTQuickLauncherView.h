#import <UIKit/UIKit.h>

@interface MTQuickLauncherView : UIView
@property(nonatomic, copy) void (^closeHandler)(void);
@property(nonatomic, copy) void (^selectHandler)(NSString *identifier);
@property(nonatomic) BOOL launching;
- (void)beginWithFavorites:(NSArray<NSString *> *)favorites names:(NSDictionary<NSString *, NSString *> *)names
    aliases:(NSDictionary *)aliases usage:(NSDictionary *)usage;
- (void)endSession;
- (void)showOpenFailure;
@end

// Bottom anchored; mirror the existing handle side. Landscape uses two columns.
// scale：面板大小百分比（80~100，缺省 100），由 MTQuickLauncherFrame 消费。
FOUNDATION_EXPORT CGRect MTQuickLauncherFrame(CGRect bounds, UIEdgeInsets safe, NSInteger side, CGFloat scale);
