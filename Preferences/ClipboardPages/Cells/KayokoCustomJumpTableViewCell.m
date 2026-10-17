//
//  KayokoCustomJumpTableViewCell.m
//  Kayoko
//

#import "KayokoCustomJumpTableViewCell.h"
#import "KayokoCustomJump.h"
#import "KayokoAppInfo.h"

@interface KayokoCustomJumpTableViewCell ()
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *linkLabel;
@end

@implementation KayokoCustomJumpTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        [self configureSubviews];
    }
    return self;
}

- (void)configureSubviews {
    [self setSelectionStyle:UITableViewCellSelectionStyleDefault];
    [[self contentView] setPreservesSuperviewLayoutMargins:YES];

    _iconView = [[UIImageView alloc] init];
    [_iconView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_iconView setContentMode:UIViewContentModeScaleAspectFit];
    [_iconView setTintColor:[UIColor labelColor]];
    [[self contentView] addSubview:_iconView];

    _titleLabel = [[UILabel alloc] init];
    [_titleLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_titleLabel setFont:[UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular]];
    [_titleLabel setTextColor:[UIColor labelColor]];
    [_titleLabel setNumberOfLines:1];
    [[self contentView] addSubview:_titleLabel];

    _linkLabel = [[UILabel alloc] init];
    [_linkLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_linkLabel setFont:[UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular]];
    [_linkLabel setTextColor:[UIColor secondaryLabelColor]];
    [_linkLabel setNumberOfLines:2];
    [_linkLabel setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [[self contentView] addSubview:_linkLabel];

    UILayoutGuide *margins = [[self contentView] layoutMarginsGuide];
    [NSLayoutConstraint activateConstraints:@[
        [[_iconView widthAnchor] constraintEqualToConstant:38.0],
        [[_iconView heightAnchor] constraintEqualToConstant:38.0],
        [[_iconView leadingAnchor] constraintEqualToAnchor:[margins leadingAnchor]],
        [[_iconView centerYAnchor] constraintEqualToAnchor:[[self contentView] centerYAnchor]],
        [[_titleLabel leadingAnchor] constraintEqualToAnchor:[_iconView trailingAnchor] constant:12.0],
        [[_titleLabel trailingAnchor] constraintEqualToAnchor:[margins trailingAnchor]],
        [[_titleLabel topAnchor] constraintEqualToAnchor:[[self contentView] topAnchor] constant:9.0],
        [[_linkLabel leadingAnchor] constraintEqualToAnchor:[_titleLabel leadingAnchor]],
        [[_linkLabel trailingAnchor] constraintEqualToAnchor:[_titleLabel trailingAnchor]],
        [[_linkLabel topAnchor] constraintEqualToAnchor:[_titleLabel bottomAnchor] constant:2.0],
        [[_linkLabel bottomAnchor] constraintLessThanOrEqualToAnchor:[[self contentView] bottomAnchor] constant:-8.0]
    ]];
}

- (void)configureWithJump:(KayokoCustomJump *)jump editing:(BOOL)editing {
    [[self titleLabel] setText:[jump title]];
    // Shortcut payloads dispatch by the app-defined item type, so that is
    // the identifier worth showing; every other type shows its link.
    NSString *link = [[jump type] isEqualToString:kKayokoCustomJumpTypeShortcut] && [[jump shortcutType] length] > 0
        ? [jump shortcutType]
        : [jump link];
    [[self linkLabel] setText:link];
    [[self iconView] setImage:[self displayImageForJump:jump]];
    [self setAccessoryType:editing ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator];
}

- (UIImage *)displayImageForJump:(KayokoCustomJump *)jump {
    NSString *iconName = [jump icon];
    if ([iconName length] > 0 && [KayokoAppInfo isValidBundleIdentifier:iconName]) {
        UIImage *appIcon = [KayokoAppInfo iconForBundleID:iconName];
        if (appIcon) {
            return appIcon;
        }
    }
    // Blank or unknown icon names fall back to the shared default symbol so
    // every row keeps an identifiable glyph like the panel buttons do.
    NSString *symbolName = iconName;
    if ([symbolName length] == 0 || ![UIImage systemImageNamed:symbolName]) {
        symbolName = kKayokoCustomJumpDefaultIconName;
    }
    return [UIImage systemImageNamed:symbolName];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [self setAccessoryType:editing ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator];
}

@end
