#import "MTCaptureCompletionToast.h"
#import "MTCaptureWindow.h"
#import "MTCaptureBubbleStyle.h"
#import "../Common/MTCaptureLog.h"

static const NSTimeInterval MTCompletionToastDuration = 2.0;

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
@end

@implementation MTCaptureCompletionToast

- (void)showCopied {
    [self mtShowMessage:@"截图已复制" assetIdentifier:nil opensPhoto:NO];
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
        if (self && self.generation == generation) [self dismiss];
    });
}

- (void)dismiss {
    NSAssert(NSThread.isMainThread, @"completion toast must run on main");
    self.generation++;
    [self.window hideAndDestroyWithCompletion:nil];
    self.window = nil;
    self.assetIdentifier = nil;
    self.opensPhoto = NO;
}

- (void)mtTapped {
    BOOL opensPhoto = self.opensPhoto;
    NSString *identifier = self.assetIdentifier;
    [self dismiss];
    if (!opensPhoto) return;

    // PHAsset.localIdentifier 是 UUID/L0/001；照片路由需要不带库后缀的 UUID。
    NSString *uuid = [identifier componentsSeparatedByString:@"/"].firstObject;
    if (!uuid.length || ![[NSUUID alloc] initWithUUIDString:uuid]) uuid = nil;
    NSURLComponents *recent = [NSURLComponents new];
    recent.scheme = @"photos-navigation";
    recent.host = @"album";
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObject:
        [NSURLQueryItem queryItemWithName:@"name" value:@"recents"]];
    if (uuid) [items addObject:[NSURLQueryItem queryItemWithName:@"revealassetuuid" value:uuid]];
    recent.queryItems = items;

    // SpringBoard 请求照片的单图路由；不能打开或没有资产 ID 时退到最近项目。
    if (uuid) {
        NSURLComponents *asset = [NSURLComponents new];
        asset.scheme = @"photos";
        asset.host = @"asset";
        asset.queryItems = @[[NSURLQueryItem queryItemWithName:@"uuid" value:uuid]];
        [UIApplication.sharedApplication openURL:asset.URL options:@{} completionHandler:^(BOOL success) {
            if (!success) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self mtOpenRecentURL:recent.URL]; });
            }
            MTCaptureLogInfo(@"completion toast photo route accepted=%d", success);
        }];
    } else {
        [self mtOpenRecentURL:recent.URL];
    }
}

- (void)mtOpenRecentURL:(NSURL *)url {
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        MTCaptureLogInfo(@"completion toast recents route accepted=%d", success);
        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"photos-redirect://"]
                                                 options:@{} completionHandler:^(BOOL opened) {
                    MTCaptureLogInfo(@"completion toast Photos fallback accepted=%d", opened);
                }];
            });
        }
    }];
}

@end
