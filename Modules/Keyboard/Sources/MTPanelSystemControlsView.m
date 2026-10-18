#import "MTPanelSystemControlsView.h"
#import "MTPanelControlState.h"
#import "MTKeyboardPanelPreferences.h"

@interface MTPanelPillSlider : UIControl
@property(nonatomic) float value;
@property(nonatomic, strong) UIView *fill;
@property(nonatomic, strong) UIImageView *icon;
@end
@implementation MTPanelPillSlider
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        self.fill = [UIView new]; self.fill.backgroundColor = UIColor.whiteColor;
        self.icon = [UIImageView new]; self.icon.contentMode = UIViewContentModeScaleAspectFit;
        self.fill.userInteractionEnabled = NO; self.icon.userInteractionEnabled = NO;
        [self addSubview:self.fill]; [self addSubview:self.icon];
        // The white fill needs a fixed capsule outline against a light panel,
        // including at 100%, when no unfilled track remains visible.
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.8].CGColor;
        self.isAccessibilityElement = YES; self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    }
    return self;
}
- (void)setValue:(float)value { _value = MIN(1, MAX(0, value)); [self setNeedsLayout]; }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; self.alpha = enabled ? 1 : 0.35; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    self.layer.cornerRadius = height / 2;
    self.fill.frame = CGRectMake(0, 0, width * self.value, height);
    self.icon.frame = CGRectMake((width - 24) / 2, (height - 24) / 2, 24, 24);
    self.icon.tintColor = self.value >= 0.5 ? [UIColor colorWithWhite:0.12 alpha:1] : UIColor.whiteColor;
    self.accessibilityValue = self.enabled ? [NSString stringWithFormat:@"%ld%%", (long)lroundf(self.value * 100)] : @"不可用";
}
- (void)updateFromTouch:(UITouch *)touch {
    if (!self.enabled || self.bounds.size.width <= 0) return;
    self.value = [touch locationInView:self].x / self.bounds.size.width;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event; if (!self.enabled) return NO;
    [self updateFromTouch:touch]; return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { (void)event; [self updateFromTouch:touch]; return YES; }
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { (void)event; if (touch) [self updateFromTouch:touch]; }
- (void)accessibilityIncrement { if (self.enabled) { self.value += 0.05; [self sendActionsForControlEvents:UIControlEventValueChanged]; } }
- (void)accessibilityDecrement { if (self.enabled) { self.value -= 0.05; [self sendActionsForControlEvents:UIControlEventValueChanged]; } }
@end

@interface MTPanelSystemControlsView ()
@property(nonatomic, strong) NSArray<UIButton *> *buttons;
@property(nonatomic, strong) NSArray<UILabel *> *labels;
@property(nonatomic, strong) MTPanelPillSlider *brightness;
@property(nonatomic, strong) MTPanelPillSlider *volume;
@property(nonatomic, strong) NSDictionary *state;
@property(nonatomic, strong) UILabel *message;
@property(nonatomic) BOOL preview;
@property(nonatomic) BOOL busy;
@property(nonatomic, readwrite) BOOL showsToggleRow;
@property(nonatomic, readwrite) BOOL showsSliderRow;
@end
@implementation MTPanelSystemControlsView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        NSArray *names = @[@"勿扰模式", @"无线网络", @"静音", @"蓝牙", @"方向锁定"];
        NSArray *icons = @[@"moon.fill", @"wifi", @"bell.slash.fill", @"antenna.radiowaves.left.and.right", @"lock.rotation"];
        NSMutableArray *buttons = [NSMutableArray array], *labels = [NSMutableArray array];
        for (NSUInteger index = 0; index < names.count; index++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom]; button.tag = index;
            [button setImage:[UIImage systemImageNamed:icons[index] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular]] forState:UIControlStateNormal];
            button.accessibilityLabel = names[index];
            [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button]; [buttons addObject:button];
            UILabel *label = [UILabel new]; label.text = names[index]; label.textAlignment = NSTextAlignmentCenter;
            label.font = [UIFont systemFontOfSize:11]; label.numberOfLines = 2;
            label.adjustsFontSizeToFitWidth = YES; label.minimumScaleFactor = 0.8;
            [self addSubview:label]; [labels addObject:label];
        }
        self.buttons = buttons; self.labels = labels;
        self.brightness = [MTPanelPillSlider new]; self.volume = [MTPanelPillSlider new];
        self.brightness.icon.image = [UIImage systemImageNamed:@"sun.max.fill"];
        self.volume.icon.image = [UIImage systemImageNamed:@"speaker.wave.2.fill"];
        self.brightness.accessibilityLabel = @"亮度"; self.volume.accessibilityLabel = @"媒体音量";
        for (MTPanelPillSlider *slider in @[self.brightness, self.volume]) {
            [slider addTarget:self action:@selector(adjusted:) forControlEvents:UIControlEventValueChanged]; [self addSubview:slider];
        }
        self.message = [UILabel new]; self.message.font = [UIFont systemFontOfSize:10];
        self.message.textAlignment = NSTextAlignmentCenter; self.message.adjustsFontSizeToFitWidth = YES;
        [self addSubview:self.message];
        self.showsToggleRow = YES; self.showsSliderRow = YES;
        [self configurePreview:NO];
    }
    return self;
}
- (void)configureWithPreferences:(NSDictionary *)preferences preview:(BOOL)preview {
    if (!NSThread.isMainThread) return;
    self.showsToggleRow = MTKeyboardPanelBool(preferences, kMTPanelSystemTogglesVisible, YES);
    self.showsSliderRow = MTKeyboardPanelBool(preferences, kMTPanelSystemSlidersVisible, YES);
    for (UIButton *button in self.buttons) button.hidden = !self.showsToggleRow;
    for (UILabel *label in self.labels) label.hidden = !self.showsToggleRow;
    self.brightness.hidden = !self.showsSliderRow;
    self.volume.hidden = !self.showsSliderRow;
    self.hidden = !self.showsToggleRow && !self.showsSliderRow;
    self.message.hidden = self.hidden;
    [self configurePreview:preview];
    [self setNeedsLayout];
}
- (CGFloat)preferredHeightForWidth:(CGFloat)width {
    return MTPanelSystemControlsHeightForRows(width, self.showsToggleRow, self.showsSliderRow);
}
- (void)configurePreview:(BOOL)preview {
    self.preview = preview; self.userInteractionEnabled = !preview;
    if (preview) self.state = @{@"do-not-disturb": @NO, @"wifi": @YES, @"silent": @YES, @"bluetooth": @YES, @"orientation-lock": @YES, @"brightness": @0.62, @"volume": @0.38};
    [self applyState:self.state ?: @{} busy:NO];
}
- (void)applyState:(NSDictionary *)state busy:(BOOL)busy {
    // A nil state is an in-flight marker, not a replacement for known values.
    if (state) {
        self.state = [state copy];
    }
    self.busy = busy;
    self.message.textColor = UIColor.labelColor;
    NSArray *ids = MTPanelToggleIdentifiers();
    for (NSUInteger index = 0; index < self.buttons.count; index++) {
        UIButton *button = self.buttons[index]; NSNumber *value = self.state[ids[index]];
        BOOL known = [value isKindOfClass:NSNumber.class], on = known && value.boolValue;
        // 关闭态圆钮统一深色底 + 白图标（浅色面板配深色按钮）。
        button.backgroundColor = on ? UIColor.systemBlueColor : [UIColor colorWithWhite:0.12 alpha:0.88];
        button.tintColor = UIColor.whiteColor;
        button.alpha = known ? 1 : 0.35;
        BOOL enabled = known && !busy;
        if (button.enabled != enabled) button.enabled = enabled;
        button.accessibilityValue = known ? (on ? @"已开启" : @"已关闭") : @"不可用";
        self.labels[index].textColor = UIColor.labelColor;
    }
    for (NSUInteger index = 0; index < 2; index++) {
        MTPanelPillSlider *slider = index ? self.volume : self.brightness;
        NSNumber *value = self.state[index ? @"volume" : @"brightness"];
        slider.enabled = [value isKindOfClass:NSNumber.class];
        if (slider.enabled && !slider.tracking) slider.value = value.floatValue;
    }
}
- (void)showMessage:(NSString *)message { self.message.text = message; }
- (void)tapped:(UIButton *)button { if (self.showsToggleRow && !self.preview && !self.busy && button.enabled && self.actionHandler) self.actionHandler(MTPanelToggleIdentifiers()[button.tag], nil); }
- (void)adjusted:(MTPanelPillSlider *)slider { if (self.showsSliderRow && !self.preview && self.actionHandler) self.actionHandler(slider == self.brightness ? @"brightness" : @"volume", @(slider.value)); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, itemWidth = width / 5, circle = MTPanelControlCircle(width);
    for (NSUInteger index = 0; index < self.buttons.count; index++) {
        self.buttons[index].frame = CGRectMake(index * itemWidth + (itemWidth - circle) / 2, 0, circle, circle);
        self.buttons[index].layer.cornerRadius = circle / 2;
        self.labels[index].frame = CGRectMake(index * itemWidth, circle + 4, itemWidth, 24);
    }
    CGFloat sliderTop = MTPanelSystemControlsSliderTop(width, self.showsToggleRow), half = MAX(0, (width - 12) / 2);
    self.brightness.frame = CGRectMake(0, sliderTop, half, 50);
    self.volume.frame = CGRectMake(half + 12, sliderTop, half, 50);
    self.message.frame = CGRectMake(0, MAX(0, [self preferredHeightForWidth:width] - 14), width, 14);
}
@end
