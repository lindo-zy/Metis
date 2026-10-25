#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Request-local CA context exclusion. Never changes a window or layer's display state.
/// UIKit/context discovery and completion run on main; rendering/copy run on a serial queue.
@interface MTContextSnapshotSource : NSObject
- (void)captureExcludingWindows:(NSArray<UIWindow *> *)windows
                    completion:(void (^)(UIImage * _Nullable, BOOL, NSString *, NSError * _Nullable))completion;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
