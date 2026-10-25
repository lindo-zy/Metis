#import "MTQuickScrollHUD.h"
#import <QuartzCore/QuartzCore.h>

@interface MTQuickScrollHUD () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *phone, *speaker, *separator;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIButton *clipboardButton, *saveButton, *closeButton, *pauseButton;
@end

@implementation MTQuickScrollHUD
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _phone = [UIView new];
        _phone.backgroundColor = [UIColor colorWithWhite:0.20 alpha:0.97];
        _phone.layer.cornerRadius = 23;
        _phone.layer.shadowColor = UIColor.blackColor.CGColor;
        _phone.layer.shadowOpacity = 0.30; _phone.layer.shadowRadius = 7;
        _phone.layer.shadowOffset = CGSizeMake(0, 3);
        [self addSubview:_phone];
        _speaker = [UIView new]; _speaker.backgroundColor = [UIColor colorWithWhite:0.6 alpha:0.5];
        _speaker.layer.cornerRadius = 2; [_phone addSubview:_speaker];
        _preview = [UIImageView new]; _preview.backgroundColor = UIColor.blackColor;
        _preview.contentMode = UIViewContentModeScaleAspectFit;
        _preview.layer.cornerRadius = 13; _preview.clipsToBounds = YES;
        [_phone addSubview:_preview];
        _status = [UILabel new]; _status.textColor = [UIColor colorWithWhite:1 alpha:0.75];
        _status.font = [UIFont monospacedDigitSystemFontOfSize:8 weight:UIFontWeightMedium];
        _status.textAlignment = NSTextAlignmentCenter; _status.adjustsFontSizeToFitWidth = YES;
        _status.minimumScaleFactor = 0.75; [_phone addSubview:_status];
        _separator = [UIView new]; _separator.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
        [_phone addSubview:_separator];
        _clipboardButton = [self mtButton:@"doc.on.doc" label:@"完成并复制长截图" selector:@selector(mtCopy)];
        _clipboardButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
        _clipboardButton.layer.borderWidth = 0.5;
        _clipboardButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
        _saveButton = [self mtButton:@"square.and.arrow.down" label:@"完成并保存长截图" selector:@selector(mtSave)];
        _saveButton.backgroundColor = UIColor.systemBlueColor;
        _closeButton = [self mtButton:@"xmark" label:@"取消快速滚动截图" selector:@selector(mtClose)];
        _pauseButton = [self mtButton:@"pause.fill" label:@"暂停快速滚动截图" selector:@selector(mtPause)];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mtPan:)];
        pan.delegate = self; [_phone addGestureRecognizer:pan];
        self.accessibilityIdentifier = @"capture.quickScroll.preview";
        [self setStatus:@"直接滑动页面，点蓝键保存" paused:NO];
    }
    return self;
}
- (UIButton *)mtButton:(NSString *)symbol label:(NSString *)label selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor; button.layer.cornerRadius = 10;
    button.accessibilityLabel = label;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [self.phone addSubview:button]; return button;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.phone.frame = CGRectInset(self.bounds, 8, 8);
    CGFloat width = self.phone.bounds.size.width, height = self.phone.bounds.size.height;
    self.speaker.frame = CGRectMake((width - 30) / 2, 10, 30, 4);
    self.closeButton.frame = CGRectMake(5, 0, 30, 25);
    self.pauseButton.frame = CGRectMake(width - 35, 0, 30, 25);
    self.preview.frame = CGRectMake(10, 25, width - 20, MAX(30, height - 89));
    self.status.frame = CGRectMake(8, height - 62, width - 16, 13);
    self.separator.frame = CGRectMake(10, height - 48, width - 20, 0.5);
    CGFloat buttonWidth = (width - 26) / 2;
    self.clipboardButton.frame = CGRectMake(10, height - 42, buttonWidth, 33);
    self.saveButton.frame = CGRectMake(16 + buttonWidth, height - 42, buttonWidth, 33);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view && view != self; view = view.superview)
        if ([view isKindOfClass:UIControl.class]) return NO;
    return YES;
}
- (void)mtPan:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:self.window];
        [self.delegate quickScrollDidDragBy:translation]; [pan setTranslation:CGPointZero inView:self.window];
    }
}
- (void)setPreviewImage:(UIImage *)image { self.preview.image = image; }
- (void)setStatus:(NSString *)status paused:(BOOL)paused {
    self.status.text = status;
    [self.pauseButton setImage:[UIImage systemImageNamed:paused ? @"play.fill" : @"pause.fill"] forState:UIControlStateNormal];
    self.pauseButton.accessibilityLabel = paused ? @"继续快速滚动截图" : @"暂停快速滚动截图";
}
- (void)setFinishing {
    self.status.text = @"正在生成长截图…";
    self.clipboardButton.enabled = self.saveButton.enabled = self.pauseButton.enabled = NO;
    self.clipboardButton.alpha = self.saveButton.alpha = 0.45;
}
- (void)mtCopy { [self.delegate quickScrollDidRequestCopy]; }
- (void)mtSave { [self.delegate quickScrollDidRequestSave]; }
- (void)mtClose { [self.delegate quickScrollDidRequestCancel]; }
- (void)mtPause { [self.delegate quickScrollDidTogglePause]; }
@end
