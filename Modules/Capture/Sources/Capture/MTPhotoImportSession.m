#import "MTPhotoImportSession.h"
#import <PhotosUI/PhotosUI.h>
#import "../Overlay/MTCaptureWindow.h"
#import "../Common/MTCaptureLog.h"

@interface MTPhotoImportSession () <PHPickerViewControllerDelegate>
@property (nonatomic, copy) void (^completion)(UIImage * _Nullable image);
@property (nonatomic, strong) MTCaptureWindow *window;
@property (nonatomic, strong) PHPickerViewController *picker;
@property (nonatomic, strong) NSProgress *loadingProgress;
@property (nonatomic, assign) BOOL finished;
@end

@implementation MTPhotoImportSession

- (instancetype)initWithCompletion:(void (^)(UIImage * _Nullable))completion {
    if ((self = [super init])) _completion = [completion copy];
    return self;
}

- (BOOL)start {
    if (!NSThread.isMainThread || self.finished || self.window) return NO;
    UIViewController *host = [UIViewController new];
    host.view.backgroundColor = UIColor.systemBackgroundColor;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [host.view addSubview:spinner];
    [spinner startAnimating];
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"取消导入" forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(mtUserCancelled) forControlEvents:UIControlEventTouchUpInside];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    [host.view addSubview:cancel];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:host.view.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:host.view.centerYAnchor],
        [cancel.centerXAnchor constraintEqualToAnchor:host.view.centerXAnchor],
        [cancel.topAnchor constraintEqualToAnchor:spinner.bottomAnchor constant:20.0],
    ]];

    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFullScreen;
    picker.modalInPresentation = YES;
    self.picker = picker;
    MTCaptureWindow *window = [MTCaptureWindow mtCaptureWindow];
    window.rootViewController = host;
    self.window = window;
    [window showAnimated:NO];
    [host presentViewController:picker animated:YES completion:nil];
    return YES;
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    if (self.finished || picker != self.picker) return;
    // 先解除 delegate，防止重复完成回调启动第二次加载。
    picker.delegate = nil;
    self.picker = nil;
    NSItemProvider *provider = results.firstObject.itemProvider;
    __weak typeof(self) weakSelf = self;
    [picker dismissViewControllerAnimated:YES completion:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.finished) return;
        if (![provider canLoadObjectOfClass:UIImage.class]) {
            [self mtFinishWithImage:nil];
            return;
        }
        self.loadingProgress = [provider loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || self.finished) return;
                UIImage *image = [object isKindOfClass:UIImage.class] ? (UIImage *)object : nil;
                if (error || image.size.width <= 0.0 || image.size.height <= 0.0) image = nil;
                if (!image) MTCaptureLogWarn(@"photo import failed to load an image");
                [self mtFinishWithImage:image];
            });
        }];
    }];
}

- (void)mtUserCancelled {
    [self mtFinishWithImage:nil];
}

- (void)mtFinishWithImage:(UIImage *)image {
    if (self.finished) return;
    void (^completion)(UIImage *) = self.completion;
    [self cancel];
    if (completion) completion(image);
}

- (void)cancel {
    if (self.finished) return;
    self.finished = YES;
    self.completion = nil;
    [self.loadingProgress cancel];
    self.loadingProgress = nil;
    self.picker.delegate = nil;
    self.picker = nil;
    [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];
    [self.window hideAndDestroyWithCompletion:nil];
    self.window = nil;
}

@end
