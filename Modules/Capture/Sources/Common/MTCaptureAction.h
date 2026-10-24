#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 设置页和外部 URL 入口共用的动作目录；URL 仅是动作的一种外部表示。
@interface MTCaptureAction : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *notificationName;
@property (nonatomic, copy, readonly, nullable) NSString *URLRoute;
@end

#ifdef __cplusplus
extern "C" {
#endif

NSArray<MTCaptureAction *> *MTCaptureActions(void);
MTCaptureAction * _Nullable MTCaptureActionForIdentifier(NSString * _Nullable identifier);
MTCaptureAction * _Nullable MTCaptureActionForURL(NSURL * _Nullable URL);
NSString * _Nullable MTCaptureRouteRoot(NSURL * _Nullable URL);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
