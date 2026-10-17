//
//  KayokoFloatingPreviewSettingsViewController.m
//  Kayoko
//

#import "KayokoFloatingPreviewSettingsViewController.h"

#import "KayokoNotificationKeys.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoTagColorFormatter.h"

#import <math.h>

@interface KayokoFloatingPreviewSampleView : UIView

@property(nonatomic, strong) UIView *bubbleView;
@property(nonatomic, assign) CGFloat bubbleDiameter;
@property(nonatomic, strong) UIColor *bubbleColor;

@end

@implementation KayokoFloatingPreviewSampleView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setBackgroundColor:[UIColor systemBackgroundColor]];
        UIView *bubbleView = [[UIView alloc] initWithFrame:CGRectZero];
        [bubbleView setBackgroundColor:[UIColor colorWithWhite:0.20 alpha:0.72]];
        [[bubbleView layer] setShadowColor:[[UIColor blackColor] CGColor]];
        [[bubbleView layer] setShadowOpacity:0.20];
        [[bubbleView layer] setShadowRadius:6.0];
        [[bubbleView layer] setShadowOffset:CGSizeMake(0, 2)];
        [self addSubview:bubbleView];
        [self setBubbleView:bubbleView];
        [self setBubbleDiameter:kKayokoPreferenceKeyFloatingPreviewSizeDefaultValue];
        [self setBubbleColor:[UIColor colorWithWhite:0.20 alpha:0.72]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat diameter = MIN(MAX([self bubbleDiameter], 1.0), MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds)) - 24.0);
    diameter = MAX(diameter, 1.0);
    [[self bubbleView] setFrame:CGRectMake(CGRectGetMidX(self.bounds) - diameter * 0.5,
                                           CGRectGetMidY(self.bounds) - diameter * 0.5,
                                           diameter,
                                           diameter)];
    [[self bubbleView] layer].cornerRadius = diameter * 0.5;
}

- (void)setBubbleDiameter:(CGFloat)bubbleDiameter {
    _bubbleDiameter = bubbleDiameter;
    [self setNeedsLayout];
}

- (void)setBubbleColor:(UIColor *)bubbleColor {
    _bubbleColor = bubbleColor;
    [[self bubbleView] setBackgroundColor:[bubbleColor colorWithAlphaComponent:0.72]];
}

@end

@interface KayokoFloatingPreviewSettingsViewController () <UITableViewDataSource, UITableViewDelegate>

@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UISwitch *doubleTapActionSwitch;
@property(nonatomic, strong) UISwitch *countdownRingSwitch;
@property(nonatomic, strong) UISlider *sizeSlider;
@property(nonatomic, strong) UILabel *sizeValueLabel;
@property(nonatomic, strong) UISlider *durationSlider;
@property(nonatomic, strong) UILabel *durationValueLabel;
@property(nonatomic, strong) UIColorWell *colorWell;
@property(nonatomic, strong) KayokoFloatingPreviewSampleView *sampleView;
@property(nonatomic, strong) NSUserDefaults *preferences;

@end

@implementation KayokoFloatingPreviewSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setTitle:[self localizedStringForKey:@"Floating Preview"]];
    [[self view] setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
    self.preferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [self.preferences registerDefaults:@{
        kKayokoPreferenceKeyFloatingPreview : @(kKayokoPreferenceKeyFloatingPreviewDefaultValue),
        kKayokoPreferenceKeyFloatingPreviewDoubleTapAction : @(kKayokoPreferenceKeyFloatingPreviewDoubleTapActionDefaultValue),
        kKayokoPreferenceKeyFloatingPreviewCountdownRing : @(kKayokoPreferenceKeyFloatingPreviewCountdownRingDefaultValue),
        kKayokoPreferenceKeyFloatingPreviewSize : @(kKayokoPreferenceKeyFloatingPreviewSizeDefaultValue),
        kKayokoPreferenceKeyFloatingPreviewDuration : @(kKayokoPreferenceKeyFloatingPreviewDurationDefaultValue),
        kKayokoPreferenceKeyFloatingPreviewColor : kKayokoPreferenceKeyFloatingPreviewColorDefaultValue,
    }];

    _enabledSwitch = [[UISwitch alloc] init];
    [_enabledSwitch setOn:[self.preferences boolForKey:kKayokoPreferenceKeyFloatingPreview]];
    [_enabledSwitch addTarget:self action:@selector(enabledSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    _doubleTapActionSwitch = [[UISwitch alloc] init];
    [_doubleTapActionSwitch setOn:[self.preferences boolForKey:kKayokoPreferenceKeyFloatingPreviewDoubleTapAction]];
    [_doubleTapActionSwitch addTarget:self
                               action:@selector(doubleTapActionSwitchChanged:)
                     forControlEvents:UIControlEventValueChanged];

    _countdownRingSwitch = [[UISwitch alloc] init];
    [_countdownRingSwitch setOn:[self.preferences boolForKey:kKayokoPreferenceKeyFloatingPreviewCountdownRing]];
    [_countdownRingSwitch addTarget:self
                             action:@selector(countdownRingSwitchChanged:)
                   forControlEvents:UIControlEventValueChanged];

    _sizeSlider = [[UISlider alloc] init];
    [_sizeSlider setMinimumValue:kKayokoPreferenceKeyFloatingPreviewSizeMinimumValue];
    [_sizeSlider setMaximumValue:kKayokoPreferenceKeyFloatingPreviewSizeMaximumValue];
    [_sizeSlider setContinuous:YES];
    [_sizeSlider addTarget:self action:@selector(sizeSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_sizeSlider setValue:[self normalizedSize] animated:NO];

    _sizeValueLabel = [[UILabel alloc] init];
    [_sizeValueLabel setTextAlignment:NSTextAlignmentRight];
    [_sizeValueLabel setFont:[UIFont monospacedDigitSystemFontOfSize:17.0 weight:UIFontWeightRegular]];
    [_sizeValueLabel setTextColor:[UIColor secondaryLabelColor]];
    [self updateSizeValueLabel];

    _durationSlider = [[UISlider alloc] init];
    [_durationSlider setMinimumValue:kKayokoPreferenceKeyFloatingPreviewDurationMinimumValue];
    [_durationSlider setMaximumValue:kKayokoPreferenceKeyFloatingPreviewDurationMaximumValue];
    [_durationSlider setContinuous:YES];
    [_durationSlider addTarget:self action:@selector(durationSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_durationSlider setValue:[self normalizedDuration] animated:NO];

    _durationValueLabel = [[UILabel alloc] init];
    [_durationValueLabel setTextAlignment:NSTextAlignmentRight];
    [_durationValueLabel setFont:[UIFont monospacedDigitSystemFontOfSize:17.0 weight:UIFontWeightRegular]];
    [_durationValueLabel setTextColor:[UIColor secondaryLabelColor]];
    [self updateDurationValueLabel];

    _colorWell = [[UIColorWell alloc] init];
    [_colorWell setSupportsAlpha:NO];
    [_colorWell setSelectedColor:[self storedColor]];
    [_colorWell addTarget:self action:@selector(colorWellChanged:) forControlEvents:UIControlEventValueChanged];
    [_colorWell setFrame:CGRectMake(0.0, 0.0, 44.0, 44.0)];

    _sampleView = [[KayokoFloatingPreviewSampleView alloc] initWithFrame:CGRectZero];
    [_sampleView setBubbleDiameter:[self normalizedSize]];
    [_sampleView setBubbleColor:[self storedColor]];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setRowHeight:52.0];
    [[self view] addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [[_tableView topAnchor] constraintEqualToAnchor:[[self view] topAnchor]],
        [[_tableView leadingAnchor] constraintEqualToAnchor:[[self view] leadingAnchor]],
        [[_tableView trailingAnchor] constraintEqualToAnchor:[[self view] trailingAnchor]],
        [[_tableView bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]]
    ]];
}

- (CGFloat)normalizedSize {
    CGFloat size = [self.preferences doubleForKey:kKayokoPreferenceKeyFloatingPreviewSize];
    if (!isfinite(size)) {
        size = kKayokoPreferenceKeyFloatingPreviewSizeDefaultValue;
    }
    return MIN(MAX(size, kKayokoPreferenceKeyFloatingPreviewSizeMinimumValue),
               kKayokoPreferenceKeyFloatingPreviewSizeMaximumValue);
}

- (UIColor *)storedColor {
    return [KayokoTagColorFormatter colorFromHexColor:[self.preferences stringForKey:kKayokoPreferenceKeyFloatingPreviewColor]];
}

- (CGFloat)normalizedDuration {
    CGFloat duration = [self.preferences doubleForKey:kKayokoPreferenceKeyFloatingPreviewDuration];
    if (!isfinite(duration)) {
        duration = kKayokoPreferenceKeyFloatingPreviewDurationDefaultValue;
    }
    return MIN(MAX(roundf(duration), kKayokoPreferenceKeyFloatingPreviewDurationMinimumValue),
               kKayokoPreferenceKeyFloatingPreviewDurationMaximumValue);
}

- (void)postPreferencesReload {
    [self.preferences synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kKayokoNotificationKeyPreferencesReload, nil, nil, YES);
}

- (void)updateSizeValueLabel {
    [[self sizeValueLabel] setText:[NSString stringWithFormat:@"%.0f", [[self sizeSlider] value]]];
}

- (void)updateDurationValueLabel {
    [[self durationValueLabel] setText:[NSString stringWithFormat:@"%.0fs", [[self durationSlider] value]]];
}

- (void)enabledSwitchChanged:(UISwitch *)sender {
    [self.preferences setBool:[sender isOn] forKey:kKayokoPreferenceKeyFloatingPreview];
    [self postPreferencesReload];
}

- (void)doubleTapActionSwitchChanged:(UISwitch *)sender {
    [self.preferences setBool:[sender isOn] forKey:kKayokoPreferenceKeyFloatingPreviewDoubleTapAction];
    [self postPreferencesReload];
}

- (void)countdownRingSwitchChanged:(UISwitch *)sender {
    [self.preferences setBool:[sender isOn] forKey:kKayokoPreferenceKeyFloatingPreviewCountdownRing];
    [self postPreferencesReload];
}

- (void)sizeSliderChanged:(UISlider *)sender {
    CGFloat size = MIN(MAX([sender value], kKayokoPreferenceKeyFloatingPreviewSizeMinimumValue),
                       kKayokoPreferenceKeyFloatingPreviewSizeMaximumValue);
    [sender setValue:size animated:NO];
    [self.preferences setDouble:size forKey:kKayokoPreferenceKeyFloatingPreviewSize];
    [self updateSizeValueLabel];
    [[self sampleView] setBubbleDiameter:size];
    [self postPreferencesReload];
}

- (void)durationSliderChanged:(UISlider *)sender {
    CGFloat duration = MIN(MAX(roundf([sender value]), kKayokoPreferenceKeyFloatingPreviewDurationMinimumValue),
                           kKayokoPreferenceKeyFloatingPreviewDurationMaximumValue);
    [sender setValue:duration animated:NO];
    [self.preferences setDouble:duration forKey:kKayokoPreferenceKeyFloatingPreviewDuration];
    [self updateDurationValueLabel];
    [self postPreferencesReload];
}

- (void)colorWellChanged:(UIColorWell *)sender {
    UIColor *color = [sender selectedColor] ?: [UIColor colorWithWhite:0.20 alpha:1.0];
    [self.preferences setObject:[KayokoTagColorFormatter hexColorFromColor:[color colorWithAlphaComponent:1.0]]
                         forKey:kKayokoPreferenceKeyFloatingPreviewColor];
    [[self sampleView] setBubbleColor:color];
    [self postPreferencesReload];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 3 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
    case 1:
        return [self localizedStringForKey:@"Size"];
    case 2:
        return [self localizedStringForKey:@"Floating Duration"];
    case 3:
        return [self localizedStringForKey:@"Color"];
    case 4:
        return [self localizedStringForKey:@"Preview"];
    default:
        return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 4) {
        return [self localizedStringForKey:@"The floating preview is always semi-transparent and stays fully visible at the screen edge."];
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *reuseIdentifier = [NSString stringWithFormat:@"KayokoFloatingPreviewCell-%ld-%ld",
                                                           (long)[indexPath section], (long)[indexPath row]];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        UITableViewCellStyle style = [indexPath section] == 1 ? UITableViewCellStyleDefault : UITableViewCellStyleValue1;
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:reuseIdentifier];
        [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
    }
    [[cell textLabel] setTextColor:[UIColor labelColor]];
    [[cell textLabel] setHidden:NO];
    [cell setAccessoryView:nil];
    if ([indexPath section] == 0 && [indexPath row] == 0) {
        [[cell textLabel] setText:[self localizedStringForKey:@"Enable Floating Preview"]];
        [cell setAccessoryView:[self enabledSwitch]];
    } else if ([indexPath section] == 0 && [indexPath row] == 1) {
        [[cell textLabel] setText:[self localizedStringForKey:@"Double-Tap Action"]];
        [cell setAccessoryView:[self doubleTapActionSwitch]];
    } else if ([indexPath section] == 0) {
        [[cell textLabel] setText:[self localizedStringForKey:@"Countdown Light Ring"]];
        [cell setAccessoryView:[self countdownRingSwitch]];
    } else if ([indexPath section] == 1) {
        [[cell textLabel] setText:[self localizedStringForKey:@"Size"]];
        if ([[self sizeSlider] superview] != [cell contentView]) {
            [[cell contentView] addSubview:[self sizeSlider]];
            [[cell contentView] addSubview:[self sizeValueLabel]];
            [[self sizeSlider] setTranslatesAutoresizingMaskIntoConstraints:NO];
            [[self sizeValueLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
            [NSLayoutConstraint activateConstraints:@[
                [[[self sizeSlider] leadingAnchor] constraintEqualToAnchor:[[cell contentView] layoutMarginsGuide].leadingAnchor constant:70.0],
                [[[self sizeSlider] trailingAnchor] constraintEqualToAnchor:[[self sizeValueLabel] leadingAnchor] constant:-12.0],
                [[[self sizeSlider] centerYAnchor] constraintEqualToAnchor:[[cell contentView] centerYAnchor]],
                [[[self sizeValueLabel] trailingAnchor] constraintEqualToAnchor:[[cell contentView] layoutMarginsGuide].trailingAnchor],
                [[[self sizeValueLabel] centerYAnchor] constraintEqualToAnchor:[[cell contentView] centerYAnchor]],
                [[[self sizeValueLabel] widthAnchor] constraintEqualToConstant:42.0]
            ]];
        }
        [[cell textLabel] setHidden:YES];
    } else if ([indexPath section] == 2) {
        [[cell textLabel] setText:[self localizedStringForKey:@"Floating Duration"]];
        if ([[self durationSlider] superview] != [cell contentView]) {
            [[cell contentView] addSubview:[self durationSlider]];
            [[cell contentView] addSubview:[self durationValueLabel]];
            [[self durationSlider] setTranslatesAutoresizingMaskIntoConstraints:NO];
            [[self durationValueLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
            [NSLayoutConstraint activateConstraints:@[
                [[[self durationSlider] leadingAnchor] constraintEqualToAnchor:[[cell contentView] layoutMarginsGuide].leadingAnchor constant:70.0],
                [[[self durationSlider] trailingAnchor] constraintEqualToAnchor:[[self durationValueLabel] leadingAnchor] constant:-12.0],
                [[[self durationSlider] centerYAnchor] constraintEqualToAnchor:[[cell contentView] centerYAnchor]],
                [[[self durationValueLabel] trailingAnchor] constraintEqualToAnchor:[[cell contentView] layoutMarginsGuide].trailingAnchor],
                [[[self durationValueLabel] centerYAnchor] constraintEqualToAnchor:[[cell contentView] centerYAnchor]],
                [[[self durationValueLabel] widthAnchor] constraintEqualToConstant:42.0]
            ]];
        }
        [[cell textLabel] setHidden:YES];
    } else if ([indexPath section] == 3) {
        [[cell textLabel] setText:[self localizedStringForKey:@"Color"]];
        [cell setAccessoryView:[self colorWell]];
    } else {
        if ([[self sampleView] superview] != [cell contentView]) {
            [[cell contentView] addSubview:[self sampleView]];
            [[self sampleView] setTranslatesAutoresizingMaskIntoConstraints:NO];
            [NSLayoutConstraint activateConstraints:@[
                [[[self sampleView] topAnchor] constraintEqualToAnchor:[[cell contentView] topAnchor] constant:12.0],
                [[[self sampleView] leadingAnchor] constraintEqualToAnchor:[[cell contentView] leadingAnchor] constant:12.0],
                [[[self sampleView] trailingAnchor] constraintEqualToAnchor:[[cell contentView] trailingAnchor] constant:-12.0],
                [[[self sampleView] bottomAnchor] constraintEqualToAnchor:[[cell contentView] bottomAnchor] constant:-12.0],
                [[[self sampleView] heightAnchor] constraintEqualToConstant:160.0]
            ]];
        }
        [cell setAccessoryView:nil];
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return [indexPath section] == 4 ? 184.0 : 52.0;
}

- (NSString *)localizedStringForKey:(NSString *)key {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    return [bundle localizedStringForKey:key value:key table:@"Root"] ?: key;
}

@end
