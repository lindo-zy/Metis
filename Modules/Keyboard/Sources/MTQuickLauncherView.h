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
FOUNDATION_EXPORT CGRect MTQuickLauncherFrame(CGRect bounds, UIEdgeInsets safe, NSInteger side);
