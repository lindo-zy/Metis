#import "MTStandaloneEditorController.h"
#import "../../Modules/Capture/Sources/Common/MTCaptureLog.h"
#import "../../Modules/Capture/Sources/Editor/MTEditorViewController.h"
#import "../../Modules/Capture/Sources/Output/MTClipboardWriter.h"
#import "../../Modules/Capture/Sources/Output/MTSharePresenter.h"
#import <PhotosUI/PhotosUI.h>

@interface MTStandaloneEditorController () <MTEditorViewControllerDelegate, PHPickerViewControllerDelegate>
@property (nonatomic, weak) UIViewController *hostViewController;
@property (nonatomic, strong, nullable) MTEditorViewController *editor;
/// 一轮「取图 → 编辑 → 输出」的独占标记：防止连点导致重复弹选择器/编辑器。
@property (nonatomic, assign, getter=isRunning) BOOL running;
@end

@implementation MTStandaloneEditorController

- (instancetype)initWithHostViewController:(UIViewController *)hostViewController {
    if (self = [super init]) {
        _hostViewController = hostViewController;
    }
    return self;
}

- (void)dealloc {
    // 设置页被弹出时宿主可能连同编辑器一起释放：断开引用环，避免视图树成孤岛。
    [_editor prepareForDismissal];
}

#pragma mark - 入口

- (BOOL)start {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ (void)[self start]; });
        return NO;
    }
    UIViewController *host = self.hostViewController;
    if (!host) {
        MTCaptureLogWarn(@"standalone editor: host released");
        return NO;
    }
    if (!host.view.window || host.presentedViewController) {
        MTCaptureLogWarn(@"standalone editor: host not presentable");
        return NO;
    }
    if (self.isRunning) {
        MTCaptureLogWarn(@"standalone editor: previous session still running");
        return NO;
    }
    self.running = YES;

    UIImage *clipboardImage = [self mtImageFromPasteboard];
    if (clipboardImage) {
        MTCaptureLogInfo(@"standalone editor: source=clipboard");
        [self mtOpenEditorWithImage:clipboardImage];
        return YES;
    }
    MTCaptureLogInfo(@"standalone editor: clipboard has no image, prompting photo library");
    [self mtPromptPhotoLibraryImport];
    return YES;
}

#pragma mark - 图片来源

/// 检测型 API（hasImages）不触发 iOS 16+ 读取授权弹窗，取值才可能触发。
- (nullable UIImage *)mtImageFromPasteboard {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    if (!pasteboard.hasImages) return nil;
    UIImage *image = pasteboard.image;
    if (![image isKindOfClass:UIImage.class]) return nil;
    CGSize size = image.size;
    if (size.width <= 0.0 || size.height <= 0.0) return nil;
    return image;
}

- (void)mtPromptPhotoLibraryImport {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"剪贴板没有图片"
                                                                  message:@"可以从相册选择一张图片进入编辑器。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"从相册选择"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf mtDismissHostPresentedThen:^{ [weakSelf mtPresentPhotoPicker]; }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self) self.running = NO;
    }]];
    [self.hostViewController presentViewController:alert animated:YES completion:nil];
}

- (void)mtPresentPhotoPicker {
    __weak typeof(self) weakSelf = self;
    [self mtRunIfHostPresentable:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (!NSClassFromString(@"PHPickerViewController")) {
            MTCaptureLogError(@"standalone editor: PhotosUI unavailable");
            self.running = NO;
            return;
        }
        PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
        configuration.filter = [PHPickerFilter imagesFilter];
        configuration.selectionLimit = 1;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
        picker.delegate = self;
        // 全屏呈现：iPad 分栏下默认的弹出框会让选图网格过窄。
        picker.modalPresentationStyle = UIModalPresentationFullScreen;
        [self.hostViewController presentViewController:picker animated:YES completion:nil];
    }];
}

#pragma mark - PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    __weak typeof(self) weakSelf = self;
    [picker dismissViewControllerAnimated:YES completion:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        PHPickerResult *result = results.firstObject;
        if (!result) {
            MTCaptureLogInfo(@"standalone editor: picker cancelled");
            self.running = NO;
            return;
        }
        [self mtLoadImageFromPickerResult:result];
    }];
}

- (void)mtLoadImageFromPickerResult:(PHPickerResult *)result {
    NSItemProvider *provider = result.itemProvider;
    if (![provider canLoadObjectOfClass:UIImage.class]) {
        MTCaptureLogWarn(@"standalone editor: picker item is not an image");
        self.running = NO;
        return;
    }
    __weak typeof(self) weakSelf = self;
    [provider loadObjectOfClass:UIImage.class
              completionHandler:^(id<NSItemProviderReading> _Nullable object, NSError * _Nullable error) {
        // 加载回调线程由系统决定，编辑器的构建与呈现必须回到主线程。
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (![object isKindOfClass:UIImage.class]) {
                MTCaptureLogError(@"standalone editor: picker load failed");
                self.running = NO;
                return;
            }
            [self mtOpenEditorWithImage:(UIImage *)object];
        });
    }];
}

#pragma mark - 编辑器

- (void)mtOpenEditorWithImage:(UIImage *)image {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self mtOpenEditorWithImage:image]; });
        return;
    }
    if (self.editor) {
        MTCaptureLogWarn(@"standalone editor: editor already open");
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self mtRunIfHostPresentable:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        // 独立模式沿用区域图片布局（圆角卡片）：全屏标记是截图专有模式。
        MTEditorViewController *editor = [[MTEditorViewController alloc] initWithImage:image delegate:self];
        editor.fullscreenMarkup = NO;
        editor.backdropImage = nil;
        editor.modalPresentationStyle = UIModalPresentationFullScreen;
        editor.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        self.editor = editor;
        MTCaptureLogInfo(@"standalone editor: open (%.0fx%.0f pt)", image.size.width, image.size.height);
        [self.hostViewController presentViewController:editor animated:YES completion:nil];
    }];
}

#pragma mark - MTEditorViewControllerDelegate

- (void)editorController:(MTEditorViewController *)controller didFinishWithImage:(UIImage *)image action:(MTOutputAction)action {
    if (controller != self.editor) return;
    MTCaptureLogInfo(@"standalone editor: finish (action %ld)", (long)action);
    __weak typeof(self) weakSelf = self;
    [self mtCloseEditorThen:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (action == MTOutputActionSave || action == MTOutputActionSaveAndCopy) {
            // 保存降级：设置进程没有相册写入授权，改由分享面板内的「存储到照片」
            // 完成入库；SaveAndCopy 保留其复制语义，其余保存类动作原样降级。
            if (action == MTOutputActionSaveAndCopy) {
                [MTClipboardWriter copyImageAsync:image completion:^(BOOL ok) {}];
            }
            [self mtPresentShareForImage:image];
            return;
        }
        if (action == MTOutputActionCopy) {
            [MTClipboardWriter copyImageAsync:image completion:^(BOOL ok) {}];
        }
    }];
}

- (void)editorControllerDidCancel:(MTEditorViewController *)controller {
    if (controller != self.editor) return;
    MTCaptureLogInfo(@"standalone editor: cancel");
    [self mtCloseEditorThen:nil];
}

#pragma mark - 收尾

/// 先断开手势引用环再关闭（编辑器头文件约定），否则整棵视图树不释放。
- (void)mtCloseEditorThen:(void (^_Nullable)(void))then {
    MTEditorViewController *editor = self.editor;
    self.editor = nil;
    self.running = NO;
    if (!editor) {
        if (then) then();
        return;
    }
    [editor prepareForDismissal];
    [editor dismissViewControllerAnimated:YES completion:then];
}

- (void)mtPresentShareForImage:(UIImage *)image {
    __weak typeof(self) weakSelf = self;
    [self mtRunIfHostPresentable:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [MTSharePresenter shareImage:image
                  fromViewController:self.hostViewController
                          completion:^(BOOL completed) {
            MTCaptureLogInfo(@"standalone editor: share completed %d", completed);
        }];
    }];
}

/// 宿主可呈现才执行：无窗口 / 已在呈现其他控制器时放弃本轮并复位独占标记。
- (void)mtRunIfHostPresentable:(void (^NS_NOESCAPE)(void))block {
    UIViewController *host = self.hostViewController;
    if (!host || !host.view.window) {
        MTCaptureLogWarn(@"standalone editor: host window unavailable");
        self.running = NO;
        return;
    }
    if (host.presentedViewController) {
        __weak typeof(self) weakSelf = self;
        [host dismissViewControllerAnimated:NO completion:^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (!self.hostViewController.view.window || self.hostViewController.presentedViewController) {
                MTCaptureLogWarn(@"standalone editor: still not presentable after dismiss");
                self.running = NO;
                return;
            }
            block();
        }];
        return;
    }
    block();
}

- (void)mtDismissHostPresentedThen:(void (^)(void))then {
    UIViewController *host = self.hostViewController;
    if (!host) return;
    if (host.presentedViewController) {
        [host dismissViewControllerAnimated:YES completion:then];
        return;
    }
    then();
}

@end
