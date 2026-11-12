#import "MTCaptureRecognitionService.h"
#import "../Common/MTCapturePreferences.h"
#import "../Common/MTOCRResponse.h"
#import <Vision/Vision.h>

@interface MTCaptureRecognitionService ()
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
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ @autoreleasepool {
        if (self.progress.cancelled) return;
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
        VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
        self.visionRequest = request;
        if (self.progress.cancelled) { [request cancel]; self.visionRequest = nil; return; }
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = YES;
        request.automaticallyDetectsLanguage = YES;
        NSArray *supported = [request supportedRecognitionLanguagesAndReturnError:nil];
        NSMutableArray *languages = [NSMutableArray array];
        for (NSString *language in @[@"zh-Hans", @"zh-Hant", @"en-US"]) {
            if ([supported containsObject:language]) [languages addObject:language];
        }
        if (languages.count) request.recognitionLanguages = languages;
        NSError *error = nil;
        BOOL ok = image.CGImage && [[[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}]
            performRequests:@[request] error:&error];
        NSMutableArray *lines = [NSMutableArray array];
        if (ok) for (VNRecognizedTextObservation *observation in request.results) {
            NSString *line = [observation topCandidates:1].firstObject.string;
            if ([line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) [lines addObject:line];
        }
        NSString *text = lines.count ? [lines componentsJoinedByString:@"\n"] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishText:text error:ok ? nil : @"本地文字识别失败，请重试"];
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

- (void)recognizeCodesInImage:(UIImage *)image completion:(void (^)(NSArray<NSString *> *, NSString *))completion {
    NSAssert(NSThread.isMainThread, @"recognition must start on main");
    self.codesCompletion = completion;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ @autoreleasepool {
        if (self.progress.cancelled) return;
        VNDetectBarcodesRequest *request = [VNDetectBarcodesRequest new];
        self.visionRequest = request;
        if (self.progress.cancelled) { [request cancel]; self.visionRequest = nil; return; }
        NSError *error = nil;
        BOOL ok = image.CGImage && [[[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}]
            performRequests:@[request] error:&error];
        NSMutableOrderedSet<NSString *> *codes = [NSMutableOrderedSet orderedSet];
        if (ok) for (VNBarcodeObservation *observation in request.results) {
            if (observation.payloadStringValue.length) [codes addObject:observation.payloadStringValue];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.progress.cancelled) return;
            void (^done)(NSArray *, NSString *) = self.codesCompletion;
            [self cancel];
            if (done) done(codes.array, ok ? nil : @"扫码失败，请重试");
        });
    }});
}
@end
