#import "MTSharePresenter.h"
#import "MTImageEncoding.h"
#import "../Common/MTConstants.h"
#import "../Common/MTCaptureLog.h"

@implementation MTSharePresenter

+ (void)shareImage:(UIImage *)image
            fromViewController:(UIViewController *)hostViewController
                    completion:(void (^)(BOOL))completion {
    if (!image) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        return;
    }

    if (!hostViewController) {
        // 没有可用宿主时降级：后台写入临时根目录（随下次启动 sweep 清理），保证图片不丢。
        NSString *path = [MTTemporaryTasksRoot() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"share_%@.%@", [NSUUID UUID].UUIDString, MTImageRequiresPNG(image) ? @"png" : @"jpg"]];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                NSData *data = MTImageRequiresPNG(image) ? UIImagePNGRepresentation(image) : UIImageJPEGRepresentation(image, 0.95);
                [data writeToFile:path atomically:YES];
                MTCaptureLogWarn(@"no host for share sheet, image dumped to %@", path);
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        });
        return;
    }

    if (MTImageRequiresPNG(image)) {
        // 分享真实 PNG 文件，让「存储到文件/照片」收到原始透明像素；编码不占主线程。
        NSString *path = [MTTemporaryTasksRoot() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"share_%@.png",NSUUID.UUID.UUIDString]];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            @autoreleasepool {
                NSData *data = UIImagePNGRepresentation(image);
                BOOL ok = data && [data writeToFile:path atomically:YES];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!ok) { completion(NO); return; }
                    [self mtPresentItem:[NSURL fileURLWithPath:path] fromViewController:hostViewController
                        cleanupPath:path completion:completion];
                });
            }
        });
        return;
    }
    [self mtPresentItem:image fromViewController:hostViewController cleanupPath:nil completion:completion];
}

+ (void)mtPresentItem:(id)item fromViewController:(UIViewController *)hostViewController
           cleanupPath:(NSString *)cleanupPath completion:(void (^)(BOOL))completion {
    void (^finish)(BOOL) = ^(BOOL completed) {
        if (cleanupPath) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
            [NSFileManager.defaultManager removeItemAtPath:cleanupPath error:nil];
        });
        completion(completed);
    };
    UIActivityViewController *activity = [[UIActivityViewController alloc]
                                          initWithActivityItems:@[item]
                                          applicationActivities:nil];
    activity.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed,
                                            NSArray *returnedItems, NSError *activityError) {
        if (activityError) {
            MTCaptureLogError(@"share activity error: %@", activityError);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ finish(completed); });
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        // present 失败（宿主已有 presented VC、窗口不可见等）时 completionWithItemsHandler
        // 不会触发，completion 必须兜底回调，否则任务卡在分享态、结果状态永不结束。
        if (!hostViewController.view.window || hostViewController.presentedViewController) {
            MTCaptureLogError(@"share sheet skipped: host already presenting %@", hostViewController);
            finish(NO);
            return;
        }
        @try {
            activity.popoverPresentationController.sourceView = hostViewController.view;
            activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(hostViewController.view.bounds),
                CGRectGetMidY(hostViewController.view.bounds),1,1);
            [hostViewController presentViewController:activity animated:YES completion:nil];
            if (!hostViewController.presentedViewController) {
                MTCaptureLogError(@"share sheet present failed");
                finish(NO);
            }
        } @catch (NSException *exception) {
            MTCaptureLogError(@"share sheet present exception: %@", exception);
            finish(NO);
        }
    });
}

@end
