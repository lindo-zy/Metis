#import "MTCaptureTestCell.h"
#import <Preferences/PSSpecifier.h>
#import "../../Modules/Capture/Sources/Common/MTCaptureAction.h"

@implementation MTCaptureTestCell {
    UILabel *_actionTitleLabel;
    UILabel *_routeLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    // PSTableCell 的三参数初始化可能重新进入此方法，必须沿两参数 super 链初始化。
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        _actionTitleLabel = [UILabel new];
        _actionTitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _actionTitleLabel.textColor = UIColor.systemBlueColor;
        _actionTitleLabel.numberOfLines = 0;
        _actionTitleLabel.adjustsFontForContentSizeCategory = YES;
        _routeLabel = [UILabel new];
        _routeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _routeLabel.textColor = UIColor.secondaryLabelColor;
        _routeLabel.numberOfLines = 0;
        _routeLabel.lineBreakMode = NSLineBreakByCharWrapping;
        _routeLabel.adjustsFontForContentSizeCategory = YES;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_actionTitleLabel, _routeLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
        ]];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.specifier = specifier;
    MTCaptureAction *action = MTCaptureActionForIdentifier(specifier.identifier);
    _actionTitleLabel.text = action ? action.title : specifier.name;
    _routeLabel.text = action.URLRoute;
    _routeLabel.hidden = (action.URLRoute.length == 0);
    self.accessoryType = UITableViewCellAccessoryNone;
    self.accessoryView = nil;
    self.accessibilityLabel = _actionTitleLabel.text;
    self.accessibilityValue = action.URLRoute;
    [self mtHideSystemLabels];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self mtHideSystemLabels];
}

- (void)mtHideSystemLabels {
    self.textLabel.hidden = YES;
    self.detailTextLabel.hidden = YES;
    if ([self respondsToSelector:@selector(titleLabel)]) self.titleLabel.hidden = YES;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.specifier = nil;
    _actionTitleLabel.text = nil;
    _routeLabel.text = nil;
    _routeLabel.hidden = YES;
    self.accessibilityLabel = nil;
    self.accessibilityValue = nil;
}

@end
