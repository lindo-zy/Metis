#import "MTPhotoWriter.h"
#import "../Common/MTConstants.h"
#import "../Common/MTCaptureLog.h"
#import <Photos/Photos.h>

@implementation MTPhotoWriter

+ (void)saveImage:(UIImage *)image
       completion:(void (^)(NSString *, NSError *))completion {
    NSParameterAssert(completion);

    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    if (status == PHAuthorizationStatusNotDetermined) {
        // SpringBoard 进程内授权弹窗行为依赖系统版本，失败路径必须可回退（保留临时文件）。
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite
                                                  handler:^(PHAuthorizationStatus newStatus) {
            [self mtSaveIfAuthorized:image status:newStatus completion:completion];
        }];
        return;
    }
    [self mtSaveIfAuthorized:image status:status completion:completion];
}

+ (void)saveImageFileAtPath:(NSString *)path
                 completion:(void (^)(NSString *, NSError *))completion {
    NSParameterAssert(completion);

    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite
                                                  handler:^(PHAuthorizationStatus newStatus) {
            [self mtSaveFileIfAuthorized:path status:newStatus completion:completion];
        }];
        return;
    }
    [self mtSaveFileIfAuthorized:path status:status completion:completion];
}

+ (void)mtSaveIfAuthorized:(UIImage *)image
                    status:(PHAuthorizationStatus)status
                completion:(void (^)(NSString *, NSError *))completion {
    if (status != PHAuthorizationStatusAuthorized) {
        NSError *error = [NSError errorWithDomain:@"com.lindo.metis.capture.output"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"相册权限被拒绝"}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
        return;
    }

    __block NSString *identifier = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        identifier = request.placeholderForCreatedAsset.localIdentifier;
    } completionHandler:^(BOOL success, NSError *changeError) {
        NSError *finalError = nil;
        if (!success) {
            finalError = changeError ?: [NSError errorWithDomain:@"com.lindo.metis.capture.output"
                                                            code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"相册保存失败"}];
        }
        // 成功但拿不到 identifier 时保持 nil，不产出假 ID。
        dispatch_async(dispatch_get_main_queue(), ^{ completion(identifier, finalError); });
    }];
}

+ (void)mtSaveFileIfAuthorized:(NSString *)path
                        status:(PHAuthorizationStatus)status
                    completion:(void (^)(NSString *, NSError *))completion {
    if (status != PHAuthorizationStatusAuthorized) {
        NSError *error = [NSError errorWithDomain:@"com.lindo.metis.capture.output"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"相册权限被拒绝"}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
        return;
    }

    __block NSString *identifier = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        // 文件资源直导：同 UTI 的 JPEG 原样入库，不做整幅解码与重编码。
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        [request addResourceWithType:PHAssetResourceTypePhoto
                             fileURL:[NSURL fileURLWithPath:path]
                             options:nil];
        identifier = request.placeholderForCreatedAsset.localIdentifier;
    } completionHandler:^(BOOL success, NSError *changeError) {
        NSError *finalError = nil;
        if (!success) {
            finalError = changeError ?: [NSError errorWithDomain:@"com.lindo.metis.capture.output"
                                                            code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"相册保存失败"}];
        }
        // 成功但拿不到 identifier 时保持 nil，不产出假 ID。
        dispatch_async(dispatch_get_main_queue(), ^{ completion(identifier, finalError); });
    }];
}

@end
