#import "MTCaptureCompletionToast.h"
#import "MTCaptureWindow.h"
#import "MTCaptureBubbleStyle.h"
#import "../Common/MTCaptureLog.h"
#import "../Common/MTRecentPhotoShortcut.h"

static const NSTimeInterval MTCompletionToastDuration = 2.0;

// SpringBoard 内 UIApplication openURL 对 photos-navigation 这类非公开 scheme 可能被
// LaunchServices 直接拒绝；敏感打开通道是特权进程的标准入口，失败后仍回落 openURL。
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(NSDictionary *)options error:(NSError **)error;
@end

static void MTOpenPhotoURL(NSURL *url, void (^completion)(BOOL)) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    LSApplicationWorkspace *workspace =
        [workspaceClass respondsToSelector:@selector(defaultWorkspace)] ? [(id)workspaceClass defaultWorkspace] : nil;
    if ([workspace respondsToSelector:@selector(openSensitiveURL:withOptions:error:)]) {
        NSError *error = nil;
        if ([workspace openSensitiveURL:url withOptions:@{} error:&error]) {
            MTCaptureLogInfo(@"completion toast sensitive route %@ accepted", url.absoluteString);
            if (completion) completion(YES);
            return;
        }
        MTCaptureLogWarn(@"completion toast sensitive route %@ rejected: %@",
                         url.absoluteString, error.localizedDescription ?: @"(no error)");
    }
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:completion];
}

@interface MTCompletionToastContent : UIView
@property (nonatomic, strong) UIButton *button;
@end

@implementation MTCompletionToastContent
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat available = MAX(0.0, self.bounds.size.width - self.safeAreaInsets.left -
                            self.safeAreaInsets.right - 24.0);
    CGFloat padding = 2.0 * MTCaptureBubbleHorizontalPadding;
    CGSize titleSize = [self.button.titleLabel sizeThatFits:CGSizeMake(MAX(0.0, available - padding), CGFLOAT_MAX)];
    CGFloat width = MIN(available, ceil(titleSize.width) + padding);
    CGFloat height = MTCaptureBubbleHeight;
    CGFloat centerX = self.safeAreaInsets.left +
        (self.bounds.size.width - self.safeAreaInsets.left - self.safeAreaInsets.right) / 2.0;
    self.button.frame = CGRectMake(centerX - width / 2.0, self.safeAreaInsets.top + 10.0, width, height);
    self.button.layer.cornerRadius = MTCaptureBubbleCornerRadius;
}
@end

@interface MTCaptureCompletionToast ()
@property (nonatomic, strong) MTCaptureWindow *window;
@property (nonatomic, copy) NSString *assetIdentifier;
@property (nonatomic, assign) BOOL opensPhoto;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, copy) void (^cancellationHandler)(void);
@property (nonatomic, weak) UIButton *contentButton;
@end

@implementation MTCaptureCompletionToast

- (void)showCopied {
    [self mtShowMessage:@"截图已复制" assetIdentifier:nil opensPhoto:NO];
}

- (void)showTextCopied {
    [self mtShowMessage:@"识别文字已复制" assetIdentifier:nil opensPhoto:NO];
}

- (void)showProcessingMessage:(NSString *)message cancellation:(void (^)(void))cancellation {
    [self mtShowMessage:message assetIdentifier:nil opensPhoto:NO];
    self.cancellationHandler = cancellation;
    self.contentButton.accessibilityHint = @"取消识别";
}

- (void)showErrorMessage:(NSString *)message {
    [self mtShowMessage:message assetIdentifier:nil opensPhoto:NO];
}

- (void)showSavedAssetIdentifier:(NSString *)identifier {
    [self mtShowMessage:@"截图已保存，点击查看" assetIdentifier:identifier opensPhoto:YES];
}

- (void)mtShowMessage:(NSString *)message assetIdentifier:(NSString *)identifier opensPhoto:(BOOL)opensPhoto {
    NSAssert(NSThread.isMainThread, @"completion toast must run on main");
    [self dismiss];
    self.assetIdentifier = identifier;
    self.opensPhoto = opensPhoto;

    MTCaptureWindow *window = [MTCaptureWindow mtCaptureWindow];
    window.passesTouchesOutsideHostedContent = YES;
    MTCompletionToastContent *content = [[MTCompletionToastContent alloc] initWithFrame:window.bounds];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = MTCaptureBubbleBackgroundColor();
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button setTitle:message forState:UIControlStateNormal];
    button.titleLabel.font = MTCaptureBubbleFont();
    button.titleLabel.numberOfLines = 1;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.75;
    button.clipsToBounds = YES;
    button.accessibilityLabel = message;
    button.accessibilityHint = opensPhoto ? @"打开刚保存的照片" : @"关闭提示";
    [button addTarget:self action:@selector(mtTapped) forControlEvents:UIControlEventTouchUpInside];
    content.button = button;
    self.contentButton = button;
    [content addSubview:button];
    [window hostContentView:content];
    self.window = window;
    [window showAnimated:YES becomeKey:NO];
    [content setNeedsLayout];
    [content layoutIfNeeded];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);

    // 新提示替换旧提示时，旧计时器不能关闭新窗口，也不保留任务或整幅截图。
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MTCompletionToastDuration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self && self.generation == generation && !self.cancellationHandler) [self dismiss];
    });
}

- (void)dismiss {
    NSAssert(NSThread.isMainThread, @"completion toast must run on main");
    self.generation++;
    [self.window hideAndDestroyWithCompletion:nil];
    self.window = nil;
    self.assetIdentifier = nil;
    self.opensPhoto = NO;
    self.cancellationHandler = nil;
    self.contentButton = nil;
}

- (void)mtTapped {
    void (^cancellation)(void) = self.cancellationHandler;
    BOOL opensPhoto = self.opensPhoto;
    NSString *identifier = self.assetIdentifier;
    [self dismiss];
    if (cancellation) { cancellation(); return; }
    if (!opensPhoto) return;

    // 首选照片 App 自带「最近一张照片」快捷方式：照片 App 在点击时刻自行解析
    // 最近资产，与保存期占位 ID 解耦——文件直存路径的 placeholderForCreatedAsset
    // 在 SpringBoard 内可能为空，URL 路由又只有受理/拒绝反馈，无法证明真正
    // 定位到了资产（1.7.2 起 photos-navigation 首位路由在真机上仍落在相册）。
    if (MTLaunchPhotosMostRecentShortcut()) return;

    // 兜底：快捷通道不可用时保留 URL 定位链，行为不劣于 1.7.2。
    // PHAsset.localIdentifier 是 UUID/L0/001；照片路由需要不带库后缀的 UUID。
    NSString *uuid = [identifier componentsSeparatedByString:@"/"].firstObject;
    if (!uuid.length || ![[NSUUID alloc] initWithUUIDString:uuid]) uuid = nil;

    // iOS 15 起 photos-navigation 才是有效路由：album=recents 配合 revealassetuuid
    // 可在最近项目中直接定位资产，photos://asset 只作旧系统后备。
    // 旧顺序把 photos://asset 放在首位，系统受理后只拉起 App 首页，成功回调又无法
    // 区分「已定位」与「仅打开」，导致永远走不到能定位的最近项目路由。
    NSURLComponents *recent = [NSURLComponents new];
    recent.scheme = @"photos-navigation";
    recent.host = @"album";
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObject:
        [NSURLQueryItem queryItemWithName:@"name" value:@"recents"]];
    if (uuid) [items addObject:[NSURLQueryItem queryItemWithName:@"revealassetuuid" value:uuid]];
    recent.queryItems = items;

    NSURL *legacy = nil;
    if (uuid) {
        NSURLComponents *asset = [NSURLComponents new];
        asset.scheme = @"photos";
        asset.host = @"asset";
        asset.queryItems = @[[NSURLQueryItem queryItemWithName:@"uuid" value:uuid]];
        legacy = asset.URL;
    }

    [self mtOpenPhotoURL:recent.URL next:legacy last:[NSURL URLWithString:@"photos-redirect://"]];
}

/// 逐级回退：最近项目定位 → 旧系统单图路由 → 仅打开照片 App。
- (void)mtOpenPhotoURL:(NSURL *)url next:(NSURL *)next last:(NSURL *)last {
    if (!url) {
        if (next) [self mtOpenPhotoURL:next next:last last:nil];
        return;
    }
    MTOpenPhotoURL(url, ^(BOOL success) {
        MTCaptureLogInfo(@"completion toast route %@ accepted=%d", url.absoluteString, success);
        if (success) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [self mtOpenPhotoURL:next next:last last:nil]; });
    });
}

@end
