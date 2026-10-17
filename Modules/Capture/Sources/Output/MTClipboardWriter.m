#import "MTClipboardWriter.h"
#import "../Common/MTCaptureLog.h"

@implementation MTClipboardWriter

+ (void)copyImageAsync:(UIImage *)image completion:(void (^)(BOOL ok))completion {
    void (^finishOnMain)(BOOL) = ^(BOOL ok) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(ok); });
    };
    if (!image) {
        finishOnMain(NO);
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSData *pngData = UIImagePNGRepresentation(image);
            if (!pngData) {
                MTCaptureLogError(@"clipboard PNG encode failed");
                finishOnMain(NO);
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                finishOnMain([self mtWritePNGData:pngData]);
            });
        }
    });
}

+ (BOOL)mtWritePNGData:(NSData *)pngData {
    @try {
        // 数据条目直写：UIKit 对 image 赋值会在写入线程同步编码，这条路径已挪到后台。
        [[UIPasteboard generalPasteboard] setData:pngData forPasteboardType:@"public.png"];
        return YES;
    } @catch (NSException *exception) {
        MTCaptureLogError(@"clipboard write exception: %@", exception);
        return NO;
    }
}

@end
