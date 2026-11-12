#import <UIKit/UIKit.h>
@class MTConfig;

NS_ASSUME_NONNULL_BEGIN
/// 一次性识别会话。入口、取消、回调均在主线程；解码、Vision、编码均在后台。
/// cancel 后不再回调；协调器另以任务身份复查，防止迟到结果覆盖剪贴板。
@interface MTCaptureRecognitionService : NSObject
- (void)recognizeTextInImage:(UIImage *)image config:(MTConfig *)config
                 completion:(void (^)(NSString * _Nullable text, NSString * _Nullable error))completion;
- (void)recognizeCodesInImage:(UIImage *)image
                  completion:(void (^)(NSArray<NSString *> *codes, NSString * _Nullable error))completion;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
