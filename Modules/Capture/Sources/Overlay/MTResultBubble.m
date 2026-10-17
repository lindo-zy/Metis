#import "MTResultBubble.h"
#import "MTCaptureWindow.h"
#import "../Common/MTCaptureLog.h"

@class MTCaptureTask;

@interface MTResultBubble ()
@property (nonatomic, strong) MTCaptureWindow *window;
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong, nullable) MTCaptureTask *task;
@property (nonatomic, assign) NSUInteger dismissGeneration;
@end

@implementation MTResultBubble

+ (instancetype)presentWithImage:(nullable UIImage *)thumbnail
                         message:(NSString *)message
                            task:(nullable MTCaptureTask *)task
                       succeeded:(BOOL)succeeded
                        delegate:(id<MTResultBubbleDelegate>)delegate {
    if (![NSThread isMainThread]) {
        // 调用契约是主线程；误从后台调用时降级为异步弹出并返回 nil（不做等待式 sync，防死锁埋雷）。
        MTCaptureLogWarn(@"result bubble present called off main thread, deferring");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self mtPresentWithImage:thumbnail message:message task:task succeeded:succeeded delegate:delegate];
        });
        return nil;
    }
    return [self mtPresentWithImage:thumbnail message:message task:task succeeded:succeeded delegate:delegate];
}

+ (instancetype)mtPresentWithImage:(UIImage *)thumbnail
                           message:(NSString *)message
                              task:(MTCaptureTask *)task
                         succeeded:(BOOL)succeeded
                          delegate:(id<MTResultBubbleDelegate>)delegate {
    // 成功态：只显示缩略图（点击按输出动作分流）；失败态：错误文字（诊断优先）。
    BOOL failureStyle = !succeeded || (task == nil);
    CGFloat bubbleWidth = failureStyle ? 240.0 : 60.0;
    CGFloat bubbleHeight = 60.0;
    CGRect frame = CGRectMake(0, 0, bubbleWidth, bubbleHeight);

    MTResultBubble *bubble = [[MTResultBubble alloc] initWithFrame:frame];
    bubble.task = task;
    bubble.delegate = delegate;
    bubble.thumbView.image = thumbnail;
    bubble.messageLabel.text = message ?: (failureStyle ? @"截图失败" : @"截图完成");
    bubble.thumbView.hidden = failureStyle;
    bubble.messageLabel.hidden = !failureStyle;

    MTCaptureWindow *window = [MTCaptureWindow mtCaptureWindow];
    window.windowLevel = 1000001.0;   // 高于选区窗口，低于系统紧急层级
    window.passesTouchesOutsideHostedContent = YES;
    bubble.window = window;
    UIView *bubbleHost = [[UIView alloc] initWithFrame:window.bounds];
    bubbleHost.backgroundColor = [UIColor clearColor];
    [bubbleHost addSubview:bubble];
    [window hostContentView:bubbleHost];
    bubble.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [bubble.trailingAnchor constraintEqualToAnchor:bubbleHost.safeAreaLayoutGuide.trailingAnchor constant:-14.0],
        [bubble.bottomAnchor constraintEqualToAnchor:bubbleHost.safeAreaLayoutGuide.bottomAnchor constant:-14.0],
        [bubble.widthAnchor constraintEqualToConstant:bubbleWidth],
        [bubble.heightAnchor constraintEqualToConstant:bubbleHeight],
    ]];
    [window showAnimated:NO becomeKey:NO];

    bubble.transform = CGAffineTransformMakeTranslation(bubbleWidth + 20, 0);
    [UIView animateWithDuration:0.25 animations:^{ bubble.transform = CGAffineTransformIdentity; }];

    // 4 秒自动消失；generation 令牌防止与手动关闭竞态。
    __weak MTResultBubble *weakBubble = bubble;
    NSUInteger generation = ++bubble.dismissGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakBubble mtAutoDismissIfGeneration:generation];
    });

    return bubble;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;
        self.layer.cornerRadius = 18.0;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
        self.clipsToBounds = YES;

        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
        blur.frame = self.bounds;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blur.contentView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.04];
        blur.userInteractionEnabled = NO;
        [self addSubview:blur];

        _thumbView = [[UIImageView alloc] init];
        _thumbView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbView.clipsToBounds = YES;
        _thumbView.layer.cornerRadius = 12.0;
        _thumbView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        _thumbView.userInteractionEnabled = YES;
        _thumbView.isAccessibilityElement = YES;
        // 点击语义按输出动作分流（代理决定），无障碍标签用中性描述。
        _thumbView.accessibilityLabel = @"截图结果";
        _thumbView.accessibilityTraits = UIAccessibilityTraitButton;
        [self addSubview:_thumbView];

        _messageLabel = [[UILabel alloc] init];
        _messageLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _messageLabel.textColor = [UIColor whiteColor];
        _messageLabel.adjustsFontSizeToFitWidth = YES;
        // 失败文案可能超过可用宽度（诊断优先），允许缩字而不是截断。
        _messageLabel.minimumScaleFactor = 0.7;
        _messageLabel.text = @"截图完成";
        [self addSubview:_messageLabel];

        // 整个气泡可点（缩略图/文案区/空白），语义由代理按输出动作分流。
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(mtTapGesture:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = 44.0;
    CGFloat padding = 8.0;
    CGFloat y = (CGRectGetHeight(self.bounds) - side) / 2.0;
    _thumbView.frame = CGRectMake(padding, y, side, side);
    _messageLabel.frame = CGRectMake(12.0, 0, CGRectGetWidth(self.bounds) - 24.0,
                                     CGRectGetHeight(self.bounds));
}

#pragma mark - 动作

- (void)mtTapGesture:(UITapGestureRecognizer *)gesture {
    if (self.delegate && [self.delegate respondsToSelector:@selector(resultBubbleDidTapBody:)]) {
        [self.delegate resultBubbleDidTapBody:self];
    }
}

#pragma mark - 关闭

- (void)updateThumbnailImage:(UIImage *)image {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateThumbnailImage:image]; });
        return;
    }
    if (self.window == nil) {
        return;   // 已关闭
    }
    self.thumbView.image = image;
}

- (void)mtAutoDismissIfGeneration:(NSUInteger)generation {
    if (generation != self.dismissGeneration) return;
    [self dismissWithCompletion:nil];
}

- (void)dismissWithCompletion:(void (^)(void))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismissWithCompletion:completion]; });
        return;
    }

    self.dismissGeneration++;   // 令牌失效：取消尚未触发的自动消失
    MTCaptureWindow *window = self.window;
    id<MTResultBubbleDelegate> delegate = self.delegate;
    self.delegate = nil;

    void (^finish)(void) = ^{
        // 打断 bubble <-> window 的引用闭环，避免隐藏后泄漏。
        self.window = nil;
        if (completion) completion();
        if (delegate && [delegate respondsToSelector:@selector(resultBubbleDidDismiss:)]) {
            [delegate resultBubbleDidDismiss:self];
        }
    };

    [window hideAndDestroyWithCompletion:finish];
}

@end
