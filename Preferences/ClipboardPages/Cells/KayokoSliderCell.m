#import "KayokoSliderCell.h"

#import <Preferences/PSSpecifier.h>

@implementation KayokoSliderCell {
    UISlider *_slider;
    UILabel *_customTitleLabel;
    UILabel *_valueLabel;
    NSString *_formatString;
    CGFloat _titleLabelWidth;
    CGFloat _valueLabelWidth;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];

    if (!self) {
        return nil;
    }

    NSNumber *labelWidthNum = [specifier propertyForKey:@"valueLabelWidth"];

    if (labelWidthNum && [labelWidthNum isKindOfClass:[NSNumber class]]) {
        _valueLabelWidth = [labelWidthNum floatValue];
    } else {
        _valueLabelWidth = 50.0;
    }

    NSNumber *titleLabelWidthNum = [specifier propertyForKey:@"titleLabelWidth"];
    _titleLabelWidth = titleLabelWidthNum ? [titleLabelWidthNum floatValue] : 88.0;

    NSString *title = [specifier name];
    if ([title isKindOfClass:[NSString class]] && [title length] > 0) {
        _customTitleLabel = [[UILabel alloc] init];
        _customTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _customTitleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
        _customTitleLabel.adjustsFontForContentSizeCategory = NO;
        _customTitleLabel.numberOfLines = 1;
        _customTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _customTitleLabel.text = title;
        [self.contentView addSubview:_customTitleLabel];
    }

    _slider = [[UISlider alloc] init];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    [_slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_slider];

    NSNumber *showValue = [specifier propertyForKey:@"showValue"];

    if (!showValue || [showValue boolValue]) {
        _valueLabel = [[UILabel alloc] init];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:[UIFont systemFontSize] weight:UIFontWeightRegular];
        _valueLabel.textColor = [UIColor secondaryLabelColor];
        _valueLabel.numberOfLines = 1;
        _valueLabel.lineBreakMode = NSLineBreakByClipping;
        _valueLabel.userInteractionEnabled = YES;
        [_valueLabel addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                              initWithTarget:self
                                                      action:@selector(handleValueLabelTapped)]];
        [self.contentView addSubview:_valueLabel];
    }

    [self _syncWithSpecifier:specifier];

    [self setupConstraints];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.titleLabel.hidden = YES;
    self.textLabel.hidden = YES;
}

- (void)setupConstraints {
    UILayoutGuide *margins = self.layoutMarginsGuide;
    NSLayoutXAxisAnchor *sliderLeadingAnchor = margins.leadingAnchor;

    if (_customTitleLabel) {
        [NSLayoutConstraint activateConstraints:@[
            [_customTitleLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [_customTitleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_customTitleLabel.widthAnchor constraintEqualToConstant:_titleLabelWidth],
        ]];
        sliderLeadingAnchor = _customTitleLabel.trailingAnchor;
    }

    if (_valueLabel) {
        [NSLayoutConstraint activateConstraints:@[
            [_valueLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_valueLabel.widthAnchor constraintEqualToConstant:_valueLabelWidth],

            [_slider.leadingAnchor constraintEqualToAnchor:sliderLeadingAnchor constant:(_customTitleLabel ? 12.0 : 0.0)],
            [_slider.trailingAnchor constraintEqualToAnchor:_valueLabel.leadingAnchor constant:-12],
            [_slider.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [_slider.leadingAnchor constraintEqualToAnchor:sliderLeadingAnchor constant:(_customTitleLabel ? 12.0 : 0.0)],
            [_slider.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [_slider.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
    ]];
}

- (void)_syncWithSpecifier:(PSSpecifier *)specifier {
    if (!specifier) {
        return;
    }

    _formatString = [specifier propertyForKey:@"format"];

    if (!_formatString || ![_formatString isKindOfClass:[NSString class]]) {
        _formatString = @"%.0f";
    }

    NSNumber *minValue = [specifier propertyForKey:@"min"];
    NSNumber *maxValue = [specifier propertyForKey:@"max"];

    if (minValue) {
        _slider.minimumValue = [minValue floatValue];
    }

    if (maxValue) {
        _slider.maximumValue = [maxValue floatValue];
    }

    NSNumber *isContinuous = [specifier propertyForKey:@"isContinuous"];
    _slider.continuous = isContinuous ? [isContinuous boolValue] : YES;

    NSNumber *enabled = [specifier propertyForKey:@"enabled"];
    BOOL isEnabled = !enabled || [enabled boolValue];
    [self setKayokoControlEnabled:isEnabled];

    id value = [specifier performGetter];

    if ([value isKindOfClass:[NSNumber class]]) {
        _slider.value = [value floatValue];
    } else {
        NSNumber *defaultValue = [specifier propertyForKey:@"default"];

        if (defaultValue) {
            _slider.value = [defaultValue floatValue];
        }
    }

    [self updateValueLabel];
}

- (void)setKayokoControlEnabled:(BOOL)enabled {
    _slider.enabled = enabled;
    _customTitleLabel.textColor = enabled ? [UIColor labelColor] : [UIColor tertiaryLabelColor];
    _valueLabel.textColor = enabled ? [UIColor secondaryLabelColor] : [UIColor tertiaryLabelColor];
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    [self _syncWithSpecifier:specifier];
}

- (void)updateValueLabel {
    if (_valueLabel) {
        _valueLabel.text = [NSString stringWithFormat:_formatString, _slider.value];
    }
}

- (void)sliderValueChanged:(UISlider *)slider {
    PSSpecifier *specifier = self.specifier;

    NSNumber *isSegmented = [specifier propertyForKey:@"isSegmented"];

    if (isSegmented && [isSegmented boolValue]) {
        NSNumber *segmentCount = [specifier propertyForKey:@"segmentCount"];

        if (segmentCount && [segmentCount integerValue] > 0) {
            NSInteger segments = [segmentCount integerValue];
            CGFloat range = slider.maximumValue - slider.minimumValue;
            CGFloat step = range / (CGFloat)segments;
            CGFloat normalizedValue = (slider.value - slider.minimumValue) / step;
            CGFloat snappedValue = slider.minimumValue + (round(normalizedValue) * step);
            slider.value = snappedValue;
        }
    }

    [self updateValueLabel];

    if (specifier) {
        NSNumber *value = @(slider.value);
        [specifier performSetterWithValue:value];
    }
}

- (void)handleValueLabelTapped {
    if (!_slider.enabled) {
        return;
    }
    NSInteger minValue = (NSInteger)_slider.minimumValue;
    NSInteger maxValue = (NSInteger)_slider.maximumValue;
    UIViewController *controller = [[self specifier] target];
    if (![controller isKindOfClass:[UIViewController class]]) {
        return;
    }

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *rangeFormat = [bundle localizedStringForKey:@"Value Range: %ld - %ld"
                                                    value:nil
                                                    table:@"Root"];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"Enter Value" value:nil table:@"Root"]
                         message:[NSString stringWithFormat:rangeFormat, (long)minValue, (long)maxValue]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
      [textField setKeyboardType:UIKeyboardTypeNumberPad];
      [textField setText:[NSString stringWithFormat:@"%ld", (long)(NSInteger)_slider.value]];
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Confirm" value:nil table:@"Root"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                              __strong typeof(weakSelf) strongSelf = weakSelf;
                                              if (!strongSelf) {
                                                  return;
                                              }
                                              NSInteger entered = [[alert textFields].firstObject.text integerValue];
                                              entered = MAX(minValue, MIN(maxValue, entered));
                                              strongSelf->_slider.value = (float)entered;
                                              [strongSelf updateValueLabel];
                                              [[strongSelf specifier] performSetterWithValue:@(entered)];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel" value:nil table:@"Root"]
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self _syncWithSpecifier:specifier];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _slider.value = _slider.minimumValue;
    [self updateValueLabel];
}

@end
