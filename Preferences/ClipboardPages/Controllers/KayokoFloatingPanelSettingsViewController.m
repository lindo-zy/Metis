//
//  KayokoFloatingPanelSettingsViewController.m
//  Kayoko
//

#import "KayokoFloatingPanelSettingsViewController.h"

#import "KayokoNotificationKeys.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoTagColorFormatter.h"

#import <math.h>

@interface KayokoFloatingPanelSampleView : UIView

@property(nonatomic, assign) CGFloat panelScale;
@property(nonatomic, strong) UIColor *panelColor;

@end


@implementation KayokoFloatingPanelSampleView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _panelScale = kKayokoPreferenceKeyFloatingPanelScaleDefaultValue;
        _panelColor = [KayokoTagColorFormatter colorFromHexColor:kKayokoPreferenceKeyFloatingPanelColorDefaultValue];
        [self setBackgroundColor:[UIColor systemBackgroundColor]];
        [[self layer] setCornerRadius:12.0];
        [[self layer] setCornerCurve:kCACornerCurveContinuous];
        [self setClipsToBounds:YES];
    }
    return self;
}

- (void)setPanelColor:(UIColor *)panelColor {
    _panelColor = panelColor;
    [self setNeedsDisplay];
}

- (void)setPanelScale:(CGFloat)panelScale {
    _panelScale = panelScale;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        return;
    }

    CGFloat scale = [self panelScale];
    CGRect bounds = [self bounds];
    CGFloat fixedWidth = MIN(CGRectGetWidth(bounds) - 24.0, 320.0);
    CGFloat panelHeight = 88.0 * scale;
    CGRect panelRect = CGRectMake(floor((CGRectGetWidth(bounds) - fixedWidth) * 0.5),
                                      floor((CGRectGetHeight(bounds) - panelHeight) * 0.5),
                                      fixedWidth,
                                      panelHeight);
    UIBezierPath *panelPath = [UIBezierPath bezierPathWithRoundedRect:panelRect cornerRadius:18.0 * scale];
    [[[self panelColor] colorWithAlphaComponent:0.20] setFill];
    [panelPath fill];

    NSArray<NSString *> *symbolNames = @[ @"doc.on.clipboard", @"photo", @"hand.tap", @"keyboard" ];
    CGFloat columnWidth = fixedWidth / [symbolNames count];
    CGFloat symbolSide = 27.0 * scale;
    UIFont *font = [UIFont systemFontOfSize:10.0 * scale weight:UIFontWeightRegular];
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : [UIColor labelColor],
        NSParagraphStyleAttributeName : ({
          NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
          [style setAlignment:NSTextAlignmentCenter];
          style;
        }),
    };
    NSArray<NSString *> *titles = @[ @"剪贴板", @"最近照片", @"手势设置", @"脚本编辑" ];

    [symbolNames enumerateObjectsUsingBlock:^(NSString *symbolName, NSUInteger index, __unused BOOL *stop) {
      UIImage *image = [[UIImage systemImageNamed:symbolName] imageWithTintColor:[UIColor labelColor]
                                                                   renderingMode:UIImageRenderingModeAlwaysOriginal];
      CGRect imageRect = CGRectMake(CGRectGetMinX(panelRect) + index * columnWidth +
                                        floor((columnWidth - symbolSide) * 0.5),
                                    CGRectGetMinY(panelRect) + 10.0 * scale,
                                    symbolSide,
                                    symbolSide);
      [image drawInRect:imageRect];
      CGRect titleRect = CGRectMake(CGRectGetMinX(panelRect) + index * columnWidth + 2.0,
                                    CGRectGetMaxY(imageRect) + 5.0 * scale,
                                    columnWidth - 4.0,
                                    25.0 * scale);
      [titles[index] drawInRect:titleRect withAttributes:attributes];
    }];
}

@end


@interface KayokoFloatingPanelSettingsViewController () <UITableViewDataSource, UITableViewDelegate>

@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UISlider *sizeSlider;
@property(nonatomic, strong) UILabel *sizeValueLabel;
@property(nonatomic, strong) UIColorWell *colorWell;
@property(nonatomic, strong) KayokoFloatingPanelSampleView *sampleView;
@property(nonatomic, strong) NSUserDefaults *preferences;

@end


@implementation KayokoFloatingPanelSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setTitle:[self localizedStringForKey:@"Floating Panel"]];
    [[self view] setBackgroundColor:[UIColor systemGroupedBackgroundColor]];

    _preferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [_preferences registerDefaults:@{
        kKayokoPreferenceKeyFloatingPanelScale : @(kKayokoPreferenceKeyFloatingPanelScaleDefaultValue),
        kKayokoPreferenceKeyFloatingPanelColor : kKayokoPreferenceKeyFloatingPanelColorDefaultValue,
    }];

    _sizeSlider = [[UISlider alloc] init];
    [_sizeSlider setMinimumValue:kKayokoPreferenceKeyFloatingPanelScaleMinimumValue];
    [_sizeSlider setMaximumValue:kKayokoPreferenceKeyFloatingPanelScaleMaximumValue];
    [_sizeSlider setContinuous:YES];
    [_sizeSlider setValue:[self normalizedPanelScale] animated:NO];
    [_sizeSlider addTarget:self action:@selector(sizeSliderChanged:) forControlEvents:UIControlEventValueChanged];

    _sizeValueLabel = [[UILabel alloc] init];
    [_sizeValueLabel setTextAlignment:NSTextAlignmentRight];
    [_sizeValueLabel setFont:[UIFont monospacedDigitSystemFontOfSize:16.0 weight:UIFontWeightRegular]];
    [_sizeValueLabel setTextColor:[UIColor secondaryLabelColor]];
    [self updateSizeValueLabel];

    _colorWell = [[UIColorWell alloc] init];
    [_colorWell setSupportsAlpha:NO];
    [_colorWell setSelectedColor:[self storedPanelColor]];
    [_colorWell addTarget:self action:@selector(colorWellChanged:) forControlEvents:UIControlEventValueChanged];
    [_colorWell setFrame:CGRectMake(0.0, 0.0, 44.0, 44.0)];

    _sampleView = [[KayokoFloatingPanelSampleView alloc] initWithFrame:CGRectZero];
    [_sampleView setPanelScale:[self normalizedPanelScale]];
    [_sampleView setPanelColor:[self storedPanelColor]];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [[self view] addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [[_tableView topAnchor] constraintEqualToAnchor:[[self view] topAnchor]],
        [[_tableView leadingAnchor] constraintEqualToAnchor:[[self view] leadingAnchor]],
        [[_tableView trailingAnchor] constraintEqualToAnchor:[[self view] trailingAnchor]],
        [[_tableView bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]],
    ]];
}

- (UIColor *)storedPanelColor {
    return [KayokoTagColorFormatter colorFromHexColor:
        [[self preferences] stringForKey:kKayokoPreferenceKeyFloatingPanelColor]];
}

- (void)postPreferencesReload {
    [[self preferences] synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kKayokoNotificationKeyPreferencesReload,
                                         nil,
                                         nil,
                                         YES);
}

- (CGFloat)normalizedPanelScale {
    CGFloat scale = [[self preferences] doubleForKey:kKayokoPreferenceKeyFloatingPanelScale];
    if (!isfinite(scale)) {
        scale = kKayokoPreferenceKeyFloatingPanelScaleDefaultValue;
    }
    return MIN(MAX(scale, kKayokoPreferenceKeyFloatingPanelScaleMinimumValue),
               kKayokoPreferenceKeyFloatingPanelScaleMaximumValue);
}

- (void)sizeSliderChanged:(UISlider *)sender {
    CGFloat scale = [sender value];
    scale = MIN(MAX(scale, kKayokoPreferenceKeyFloatingPanelScaleMinimumValue),
                kKayokoPreferenceKeyFloatingPanelScaleMaximumValue);
    [[self preferences] setDouble:scale forKey:kKayokoPreferenceKeyFloatingPanelScale];
    [[self sampleView] setPanelScale:scale];
    [self updateSizeValueLabel];
    [self postPreferencesReload];
}

- (void)colorWellChanged:(UIColorWell *)sender {
    UIColor *color = [sender selectedColor] ?: [self storedPanelColor];
    [[self preferences] setObject:[KayokoTagColorFormatter hexColorFromColor:[color colorWithAlphaComponent:1.0]]
                          forKey:kKayokoPreferenceKeyFloatingPanelColor];
    [[self sampleView] setPanelColor:color];
    [self postPreferencesReload];
}

- (void)updateSizeValueLabel {
    [[self sizeValueLabel] setText:[NSString stringWithFormat:@"%.0f%%", [[self sizeSlider] value] * 100.0]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case 0:
            return [self localizedStringForKey:@"Panel Size"];
        case 1:
            return [self localizedStringForKey:@"Color"];
        default:
            return [self localizedStringForKey:@"Preview"];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) {
        return [self localizedStringForKey:@"Changing the size scales the icons, text, spacing, and height while keeping the panel width fixed."];
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *reuseIdentifier = [NSString stringWithFormat:@"KayokoFloatingPanelCell-%ld", (long)[indexPath section]];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
        [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
    }

    if ([indexPath section] == 0) {
        if ([[self sizeSlider] superview] != [cell contentView]) {
            [[cell contentView] addSubview:[self sizeSlider]];
            [[cell contentView] addSubview:[self sizeValueLabel]];
            [[self sizeSlider] setTranslatesAutoresizingMaskIntoConstraints:NO];
            [[self sizeValueLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
            [NSLayoutConstraint activateConstraints:@[
                [[[self sizeSlider] leadingAnchor] constraintEqualToAnchor:[[cell contentView] layoutMarginsGuide].leadingAnchor],
                [[[self sizeSlider] trailingAnchor] constraintEqualToAnchor:[[self sizeValueLabel] leadingAnchor] constant:-12.0],
                [[[self sizeSlider] centerYAnchor] constraintEqualToAnchor:[[cell contentView] centerYAnchor]],
                [[[self sizeValueLabel] trailingAnchor] constraintEqualToAnchor:[[cell contentView] layoutMarginsGuide].trailingAnchor],
                [[[self sizeValueLabel] centerYAnchor] constraintEqualToAnchor:[[cell contentView] centerYAnchor]],
                [[[self sizeValueLabel] widthAnchor] constraintEqualToConstant:58.0],
            ]];
        }
    } else if ([indexPath section] == 1) {
        [[cell textLabel] setText:[self localizedStringForKey:@"Color"]];
        [cell setAccessoryView:[self colorWell]];
    } else if ([[self sampleView] superview] != [cell contentView]) {
        [[cell contentView] addSubview:[self sampleView]];
        [[self sampleView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self sampleView] topAnchor] constraintEqualToAnchor:[[cell contentView] topAnchor] constant:12.0],
            [[[self sampleView] leadingAnchor] constraintEqualToAnchor:[[cell contentView] leadingAnchor] constant:12.0],
            [[[self sampleView] trailingAnchor] constraintEqualToAnchor:[[cell contentView] trailingAnchor] constant:-12.0],
            [[[self sampleView] bottomAnchor] constraintEqualToAnchor:[[cell contentView] bottomAnchor] constant:-12.0],
            [[[self sampleView] heightAnchor] constraintEqualToConstant:142.0],
        ]];
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return [indexPath section] == 2 ? 166.0 : 52.0;
}

- (NSString *)localizedStringForKey:(NSString *)key {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    return [bundle localizedStringForKey:key value:key table:@"Root"] ?: key;
}

@end
