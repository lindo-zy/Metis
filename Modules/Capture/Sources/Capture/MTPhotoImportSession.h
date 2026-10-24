#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 一轮相册取图。completion 在主线程调用一次；cancel 销毁界面并废弃在途回调。
@interface MTPhotoImportSession : NSObject
- (instancetype)initWithCompletion:(void (^)(UIImage * _Nullable image))completion;
- (BOOL)start;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
