#import "MTClipboardWriter.h"
#import "../Common/MTCaptureLog.h"

@interface MTQuickScrollClipboardFile : NSObject
@property (nonatomic, strong) NSURL *url;
@end
@implementation MTQuickScrollClipboardFile
- (void)dealloc {
    NSString *path = _url.path;
    if (path) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    });
}
@end

@implementation MTClipboardWriter

+ (void)copyImageFileAsync:(NSString *)path completion:(void (^)(BOOL))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ @autoreleasepool {
        // The task directory is removed after output. Keep the provider's file in
        // an independent cache so pasting later cannot refer to a deleted task.
        NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/com.lindo.metis.capture/Clipboard"];
        NSError *error = nil;
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
        NSString *destination = [directory stringByAppendingPathComponent:
            [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"]];
        BOOL copied = !error && [NSFileManager.defaultManager copyItemAtPath:path toPath:destination error:&error];
        MTQuickScrollClipboardFile *file = [MTQuickScrollClipboardFile new];
        file.url = [NSURL fileURLWithPath:destination];
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL ok = copied;
            @try {
                if (ok) {
                    NSItemProvider *provider = [NSItemProvider new];
                    provider.suggestedName = @"longshot.png";
                    [provider registerFileRepresentationForTypeIdentifier:@"public.png" fileOptions:0
                        visibility:NSItemProviderRepresentationVisibilityAll loadHandler:^NSProgress *(void (^done)(NSURL *, BOOL, NSError *)) {
                            done(file.url, NO, nil); return nil;
                        }];
                    [UIPasteboard.generalPasteboard setItemProviders:@[provider] localOnly:NO expirationDate:nil];
                }
            } @catch (NSException *exception) {
                MTCaptureLogError(@"clipboard file write exception: %@", exception.name); ok = NO;
            }
            if (!ok) [NSFileManager.defaultManager removeItemAtPath:destination error:nil];
            completion(ok);
        });
    }});
}

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
