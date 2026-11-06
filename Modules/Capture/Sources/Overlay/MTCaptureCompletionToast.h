#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 主线程使用。独立非 key 窗口，气泡外触摸穿透；两秒或点击后销毁。
@interface MTCaptureCompletionToast : NSObject
- (void)showCopied;
- (void)showErrorMessage:(NSString *)message;
- (void)showSavedAssetIdentifier:(nullable NSString *)identifier;
- (void)dismiss;
@end

NS_ASSUME_NONNULL_END
