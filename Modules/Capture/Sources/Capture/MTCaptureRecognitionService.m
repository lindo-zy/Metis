#import "MTCaptureRecognitionService.h"
#import "../Common/MTCapturePreferences.h"
#import "../Common/MTOCRResponse.h"
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import "../Common/MTCaptureLog.h"

static CGImagePropertyOrientation MTRecognitionOrientation(UIImageOrientation orientation) {
    switch (orientation) {
        case UIImageOrientationDown: return kCGImagePropertyOrientationDown;
        case UIImageOrientationLeft: return kCGImagePropertyOrientationLeft;
        case UIImageOrientationRight: return kCGImagePropertyOrientationRight;
        case UIImageOrientationUpMirrored: return kCGImagePropertyOrientationUpMirrored;
        case UIImageOrientationDownMirrored: return kCGImagePropertyOrientationDownMirrored;
        case UIImageOrientationLeftMirrored: return kCGImagePropertyOrientationLeftMirrored;
        case UIImageOrientationRightMirrored: return kCGImagePropertyOrientationRightMirrored;
        default: return kCGImagePropertyOrientationUp;
    }
}

@interface MTCaptureRecognitionService () <NSURLSessionTaskDelegate>
@property (nonatomic, strong) NSProgress *progress;
@property (nonatomic, strong) NSURLSession *session;
@property (atomic, strong) VNRequest *visionRequest;
@property (nonatomic, copy) void (^textCompletion)(NSString *, NSString *);
@property (nonatomic, copy) void (^codesCompletion)(NSArray<NSString *> *, NSString *);
@end

@implementation MTCaptureRecognitionService
- (instancetype)init {
    if ((self = [super init])) _progress = [NSProgress progressWithTotalUnitCount:1];
    return self;
}

- (void)cancel {
    NSAssert(NSThread.isMainThread, @"recognition lifecycle must run on main");
    [self.progress cancel];
    [self.visionRequest cancel];
    self.visionRequest = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
    self.textCompletion = nil;
    self.codesCompletion = nil;
}

- (void)finishText:(NSString *)text error:(NSString *)error {
    if (self.progress.cancelled) return;
    void (^completion)(NSString *, NSString *) = self.textCompletion;
    [self cancel];
    if (completion) completion(text, error);
}

- (void)recognizeTextInImage:(UIImage *)image config:(MTConfig *)config
                 completion:(void (^)(NSString *, NSString *))completion {
    NSAssert(NSThread.isMainThread, @"recognition must start on main");
    self.textCompletion = completion;
    if (config.ocrEngine == 1 && (!config.ocrBaiduAPIKey.length || !config.ocrBaiduSecretKey.length)) {
        [self finishText:nil error:@"请先在截图 → 文字识别中填写百度 API Key 和 Secret Key"];
        return;
    }
    if (config.ocrEngine == 2 && !config.ocrStudioToken.length) {
        [self finishText:nil error:@"请先在 OCR 设置中填写 AI Studio Access Token"];
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ @autoreleasepool {
        if (self.progress.cancelled) return;
        if (config.ocrEngine == 2) {
            NSData *jpeg = UIImageJPEGRepresentation(image, 0.85);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.progress.cancelled) return;
                if (!jpeg || jpeg.length > 20 * 1024 * 1024) [self finishText:nil error:@"图片无法上传，请缩小选区后重试"];
                else [self recognizeStudioImage:jpeg config:config];
            });
            return;
        }
        if (config.ocrEngine == 1) {
            // 标准版限制：短边 >= 15px、长边 <= 4096px、base64 + URL 编码后 <= 8M。
            CGSize pixels = CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));
            CGFloat scale = MIN(1.0, 4096.0 / MAX(1.0, MAX(pixels.width, pixels.height)));
            CGSize size = CGSizeMake(floor(pixels.width * scale), floor(pixels.height * scale));
            if (MIN(size.width, size.height) < 15.0) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self finishText:nil error:@"选区过窄，请扩大选区后重试"]; });
                return;
            }
            UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
            format.scale = 1.0;
            format.opaque = YES;
            UIImage *upload = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format]
                imageWithActions:^(UIGraphicsImageRendererContext *context) {
                    [UIColor.whiteColor setFill];
                    UIRectFill((CGRect){CGPointZero, size});
                    [image drawInRect:(CGRect){CGPointZero, size}];
                }];
            NSData *body = nil;
            for (NSNumber *quality in @[@0.9, @0.65, @0.4]) {
                NSData *jpeg = UIImageJPEGRepresentation(upload, quality.doubleValue);
                if (!jpeg) break;
                body = MTOCRFormBody(@{@"image": [jpeg base64EncodedStringWithOptions:0],
                    @"language_type": @"CHN_ENG", @"detect_direction": @"true"});
                if (body.length <= 8 * 1024 * 1024) break;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.progress.cancelled) return;
                if (!body || body.length > 8 * 1024 * 1024) {
                    [self finishText:nil error:@"图片过大，请缩小选区或使用本地识别"];
                } else [self recognizeBaiduBody:body config:config];
            });
            return;
        }
        NSMutableArray *lines = [NSMutableArray array];
        BOOL anySucceeded = NO;
        // Revision 2 provides a second, explicit Chinese/English path on iOS 16.
        for (NSUInteger pass = 0; pass < 2 && !self.progress.cancelled && !lines.count; pass++) {
            VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
            if (pass == 1) request.revision = VNRecognizeTextRequestRevision2;
            self.visionRequest = request;
            if (self.progress.cancelled) { [request cancel]; break; }
            request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
            request.usesLanguageCorrection = pass == 0;
            request.automaticallyDetectsLanguage = pass == 0;
            NSArray *supported = [request supportedRecognitionLanguagesAndReturnError:nil];
            NSMutableArray *languages = [NSMutableArray array];
            for (NSString *language in @[@"zh-Hans", @"zh-Hant", @"en-US"]) {
                if ([supported containsObject:language]) [languages addObject:language];
            }
            if (languages.count) request.recognitionLanguages = languages;
            NSError *error = nil;
            BOOL ok = image.CGImage && [[[VNImageRequestHandler alloc] initWithCGImage:image.CGImage
                orientation:MTRecognitionOrientation(image.imageOrientation) options:@{}] performRequests:@[request] error:&error];
            anySucceeded |= ok;
            if (!ok && !self.progress.cancelled) MTCaptureLogWarn(@"local OCR pass=%lu failed domain=%@ code=%ld", (unsigned long)pass, error.domain ?: @"image", (long)error.code);
            if (ok) for (VNRecognizedTextObservation *observation in request.results) {
                NSString *line = [observation topCandidates:1].firstObject.string;
                if ([line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) [lines addObject:line];
            }
        }
        self.visionRequest = nil;
        NSString *text = lines.count ? [lines componentsJoinedByString:@"\n"] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishText:text error:anySucceeded ? nil : @"本地文字识别失败，请重试"];
        });
    }});
}

- (void)postURL:(NSURL *)url body:(NSData *)body completion:(void (^)(NSDictionary *, NSString *))completion {
    if (self.progress.cancelled) return;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 20.0;
    request.HTTPBody = body;
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![json isKindOfClass:NSDictionary.class]) json = nil;
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        NSString *message = nil;
        if (error) message = error.code == NSURLErrorTimedOut ? @"百度识别超时，请重试" : @"无法连接百度，请检查网络后重试";
        else if (!json || status < 200 || status >= 300) message = @"百度服务返回异常，请检查密钥与服务状态";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.progress.cancelled) completion(json, message);
        });
    }] resume];
}

- (void)recognizeBaiduBody:(NSData *)body config:(MTConfig *)config {
    NSURLSessionConfiguration *sessionConfig = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    sessionConfig.timeoutIntervalForResource = 45.0;
    sessionConfig.URLCache = nil;
    sessionConfig.HTTPCookieStorage = nil;
    self.session = [NSURLSession sessionWithConfiguration:sessionConfig];
    // 凭证在 POST body，不进入 URL、持久缓存或日志；token 仅在这次会话内存中使用。
    NSData *authBody = MTOCRFormBody(@{@"grant_type": @"client_credentials",
        @"client_id": config.ocrBaiduAPIKey, @"client_secret": config.ocrBaiduSecretKey});
    [self postURL:[NSURL URLWithString:@"https://aip.baidubce.com/oauth/2.0/token"] body:authBody
        completion:^(NSDictionary *auth, NSString *error) {
        NSString *token = [auth[@"access_token"] isKindOfClass:NSString.class] ? auth[@"access_token"] : nil;
        if (error || !token.length) {
            [self finishText:nil error:error ?: @"百度授权失败，请检查 API Key 和 Secret Key"];
            return;
        }
        NSURLComponents *url = [NSURLComponents componentsWithString:@"https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic"];
        url.queryItems = @[[NSURLQueryItem queryItemWithName:@"access_token" value:token]];
        [self postURL:url.URL body:body completion:^(NSDictionary *result, NSString *failure) {
            if (failure) { [self finishText:nil error:failure]; return; }
            id code = result[@"error_code"];
            if (code) {
                [self finishText:nil error:[code isKindOfClass:NSNumber.class]
                    ? MTOCRBaiduErrorMessage([code integerValue]) : @"百度服务返回异常"];
                return;
            }
            if (![result[@"words_result"] isKindOfClass:NSArray.class]) {
                [self finishText:nil error:@"百度服务返回异常"];
                return;
            }
            [self finishText:MTOCRTextFromResponse(result) error:nil];
        }];
    }];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    // Never forward an API token to a redirected host.
    completionHandler([task.originalRequest valueForHTTPHeaderField:@"Authorization"] ? nil : request);
}

// AI Studio uses an asynchronous job; the result URL is fetched without credentials.
- (void)studioRequest:(NSMutableURLRequest *)request token:(NSString *)token completion:(void (^)(NSData *, NSString *))completion {
    if (self.progress.cancelled) return;
    request.timeoutInterval = 30;
    if (token) [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        NSString *failure = error ? (error.code == NSURLErrorTimedOut ? @"AI Studio 请求超时" : @"无法连接 AI Studio，请检查网络") :
            (status == 401 || status == 403 ? @"AI Studio 授权失败，请检查 Access Token" :
             (status == 429 ? @"AI Studio 请求过于频繁或额度不足" : (status < 200 || status >= 300 ? @"AI Studio 服务返回异常" : nil)));
        dispatch_async(dispatch_get_main_queue(), ^{ if (!self.progress.cancelled) completion(data, failure); });
    }] resume];
}

- (NSDictionary *)studioResponse:(NSData *)data {
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![json isKindOfClass:NSDictionary.class] || (json[@"code"] && ![json[@"code"] isEqual:@0])) return nil;
    return [json[@"data"] isKindOfClass:NSDictionary.class] ? json[@"data"] : nil;
}

- (void)recognizeStudioImage:(NSData *)jpeg config:(MTConfig *)config {
    NSURLSessionConfiguration *sessionConfig = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    sessionConfig.URLCache = nil;
    sessionConfig.HTTPCookieStorage = nil;
    self.session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:nil];
    NSString *boundary = [@"Metis-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSMutableData *body = [NSMutableData data];
    void (^append)(NSString *) = ^(NSString *value) { [body appendData:[value dataUsingEncoding:NSUTF8StringEncoding]]; };
    append([NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n%@\r\n", boundary, config.ocrStudioModel]);
    append([NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"optionalPayload\"\r\n\r\n{\"visualize\":false}\r\n", boundary]);
    append([NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"capture.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n", boundary]);
    [body appendData:jpeg];
    append([NSString stringWithFormat:@"\r\n--%@--\r\n", boundary]);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://paddleocr.aistudio-app.com/api/v2/ocr/jobs"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    [request setValue:[@"multipart/form-data; boundary=" stringByAppendingString:boundary] forHTTPHeaderField:@"Content-Type"];
    [self studioRequest:request token:config.ocrStudioToken completion:^(NSData *data, NSString *failure) {
        if (failure) { [self finishText:nil error:failure]; return; }
        id job = [self studioResponse:data][@"jobId"];
        if (![job isKindOfClass:NSString.class] || ![job length]) { [self finishText:nil error:@"AI Studio 任务提交失败"]; return; }
        [self pollStudioJob:job token:config.ocrStudioToken attempts:0];
    }];
}

- (void)pollStudioJob:(NSString *)job token:(NSString *)token attempts:(NSUInteger)attempts {
    if (self.progress.cancelled) return;
    if (attempts >= 60) { [self finishText:nil error:@"AI Studio 识别超时，请重试"]; return; }
    NSString *escaped = [job stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet];
    NSURL *url = [NSURL URLWithString:[@"https://paddleocr.aistudio-app.com/api/v2/ocr/jobs/" stringByAppendingString:escaped]];
    [self studioRequest:[NSMutableURLRequest requestWithURL:url] token:token completion:^(NSData *data, NSString *failure) {
        if (failure) { [self finishText:nil error:failure]; return; }
        NSDictionary *result = [self studioResponse:data];
        id state = result[@"state"];
        if ([state isEqual:@"pending"] || [state isEqual:@"running"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self pollStudioJob:job token:token attempts:attempts + 1]; });
        } else if ([state isEqual:@"done"]) {
            id resultURL = [result[@"resultUrl"] isKindOfClass:NSDictionary.class] ? result[@"resultUrl"][@"jsonUrl"] : nil;
            NSURL *download = [resultURL isKindOfClass:NSString.class] ? [NSURL URLWithString:resultURL] : nil;
            if (![download.scheme.lowercaseString isEqual:@"https"] || !download.host.length) { [self finishText:nil error:@"AI Studio 返回的结果地址无效"]; return; }
            [self studioRequest:[NSMutableURLRequest requestWithURL:download] token:nil completion:^(NSData *content, NSString *err) {
                if (err) { [self finishText:nil error:err]; return; }
                NSString *jsonl = [[NSString alloc] initWithData:content encoding:NSUTF8StringEncoding];
                NSMutableArray *lines = [NSMutableArray array];
                BOOL valid = NO;
                for (NSString *line in [jsonl componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                    if (!line.length) continue;
                    id obj = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                    id resultObject = [obj isKindOfClass:NSDictionary.class] ? obj[@"result"] : nil;
                    id pages = [resultObject isKindOfClass:NSDictionary.class] ? resultObject[@"ocrResults"] : nil;
                    if (![pages isKindOfClass:NSArray.class]) { [self finishText:nil error:@"AI Studio 结果格式异常"]; return; }
                    valid = YES;
                    for (id page in pages) {
                        id pruned = [page isKindOfClass:NSDictionary.class] ? page[@"prunedResult"] : nil;
                        id texts = [pruned isKindOfClass:NSDictionary.class] ? pruned[@"rec_texts"] : nil;
                        if (![texts isKindOfClass:NSArray.class]) { [self finishText:nil error:@"AI Studio 结果格式异常"]; return; }
                        for (id text in texts) if ([text isKindOfClass:NSString.class] && [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) [lines addObject:text];
                    }
                }
                [self finishText:lines.count ? [lines componentsJoinedByString:@"\n"] : nil error:valid ? nil : @"AI Studio 结果格式异常"];
            }];
        } else [self finishText:nil error:[state isEqual:@"failed"] ? @"AI Studio 识别失败，请稍后重试" : @"AI Studio 任务状态异常"];
    }];
}

- (void)recognizeCodesInImage:(UIImage *)image completion:(void (^)(NSArray<NSString *> *, NSString *))completion {
    NSAssert(NSThread.isMainThread, @"recognition must start on main");
    self.codesCompletion = completion;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ @autoreleasepool {
        if (self.progress.cancelled) return;
        VNDetectBarcodesRequest *request = [VNDetectBarcodesRequest new];
        self.visionRequest = request;
        if (self.progress.cancelled) { [request cancel]; self.visionRequest = nil; return; }
        NSError *error = nil;
        BOOL ok = image.CGImage && [[[VNImageRequestHandler alloc] initWithCGImage:image.CGImage
            orientation:MTRecognitionOrientation(image.imageOrientation) options:@{}] performRequests:@[request] error:&error];
        NSMutableOrderedSet<NSString *> *codes = [NSMutableOrderedSet orderedSet];
        if (ok) for (VNBarcodeObservation *observation in request.results) {
            if (observation.payloadStringValue.length) [codes addObject:observation.payloadStringValue];
        }
        self.visionRequest = nil;
        // Core Image supplies an independent QR decoder for cases Vision misses.
        BOOL fallbackAvailable = NO;
        if (!codes.count && !self.progress.cancelled && image.CGImage) {
            CIImage *input = [[CIImage imageWithCGImage:image.CGImage] imageByApplyingOrientation:MTRecognitionOrientation(image.imageOrientation)];
            CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
            fallbackAvailable = detector != nil;
            for (CIQRCodeFeature *feature in [detector featuresInImage:input]) {
                if (self.progress.cancelled) break;
                if ([feature isKindOfClass:CIQRCodeFeature.class] && feature.messageString.length) [codes addObject:feature.messageString];
            }
        }
        if (!ok && !self.progress.cancelled) MTCaptureLogWarn(@"barcode Vision failed domain=%@ code=%ld", error.domain ?: @"image", (long)error.code);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.progress.cancelled) return;
            void (^done)(NSArray *, NSString *) = self.codesCompletion;
            [self cancel];
            if (done) done(codes.array, (ok || fallbackAvailable) ? nil : @"扫码失败，请重试");
        });
    }});
}
@end
