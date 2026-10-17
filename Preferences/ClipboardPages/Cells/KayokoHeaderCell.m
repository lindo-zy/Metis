//
//  KayokoHeaderCell.m
//  Kayoko
//

#import "KayokoHeaderCell.h"

@implementation KayokoHeaderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];

    if (self) {
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        [self setSelectionStyle:UITableViewCellSelectionStyleNone];
        [[self contentView] setBackgroundColor:[UIColor clearColor]];
        [self setBackgroundColor:[UIColor clearColor]];
        UILayoutGuide *margins = [self layoutMarginsGuide];

        UIImage *icon = [UIImage imageNamed:@"KayokoIcon" inBundle:bundle compatibleWithTraitCollection:nil];
        [self setIconImageView:[[UIImageView alloc] initWithImage:icon]];
        [[self iconImageView] setContentMode:UIViewContentModeScaleAspectFit];
        [[self iconImageView] setClipsToBounds:YES];
        [[[self iconImageView] layer] setCornerRadius:10];
        [[[self iconImageView] layer] setBorderWidth:0.5];
        [[[self iconImageView] layer] setBorderColor:[[[UIColor labelColor] colorWithAlphaComponent:0.10] CGColor]];
        [[self contentView] addSubview:[self iconImageView]];

        [[self iconImageView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self iconImageView] leadingAnchor] constraintEqualToAnchor:[margins leadingAnchor]],
            [[[self iconImageView] centerYAnchor] constraintEqualToAnchor:[[self contentView] centerYAnchor]],
            [[[self iconImageView] widthAnchor] constraintEqualToConstant:46],
            [[[self iconImageView] heightAnchor] constraintEqualToConstant:46]
        ]];

        NSString *titleKey = [specifier propertyForKey:@"headerTitle"] ?: [specifier propertyForKey:@"label"];
        NSString *title = [bundle localizedStringForKey:titleKey value:nil table:@"Root"];
        [self setHeaderTitleLabel:[[UILabel alloc] init]];
        [[self headerTitleLabel] setText:title];
        [[self headerTitleLabel] setFont:[UIFont systemFontOfSize:22 weight:UIFontWeightSemibold]];
        [[self headerTitleLabel] setTextColor:[UIColor labelColor]];
        [[self headerTitleLabel] setAdjustsFontSizeToFitWidth:YES];
        [[self headerTitleLabel] setMinimumScaleFactor:0.82];
        [[self headerTitleLabel] setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                                 forAxis:UILayoutConstraintAxisHorizontal];
        [[self contentView] addSubview:[self headerTitleLabel]];

        [[self headerTitleLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self headerTitleLabel] leadingAnchor] constraintEqualToAnchor:[[self iconImageView] trailingAnchor]
                                                                    constant:13],
            [[[self headerTitleLabel] topAnchor] constraintEqualToAnchor:[[self iconImageView] topAnchor] constant:1],
            [[[self headerTitleLabel] trailingAnchor] constraintEqualToAnchor:[margins trailingAnchor]]
        ]];

        NSString *subtitleKey = [specifier propertyForKey:@"headerSubtitle"] ?: [specifier propertyForKey:@"subtitle"];
        NSString *subtitle = [bundle localizedStringForKey:subtitleKey value:nil table:@"Root"];
        [self setSubtitleLabel:[[UILabel alloc] init]];
        [[self subtitleLabel] setText:subtitle];
        [[self subtitleLabel] setFont:[UIFont systemFontOfSize:12 weight:UIFontWeightRegular]];
        [[self subtitleLabel] setTextColor:[UIColor secondaryLabelColor]];
        [[self subtitleLabel] setNumberOfLines:2];
        [[self contentView] addSubview:[self subtitleLabel]];

        [[self subtitleLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self subtitleLabel] leadingAnchor] constraintEqualToAnchor:[[self headerTitleLabel] leadingAnchor]],
            [[[self subtitleLabel] trailingAnchor] constraintEqualToAnchor:[margins trailingAnchor]],
            [[[self subtitleLabel] topAnchor] constraintEqualToAnchor:[[self headerTitleLabel] bottomAnchor]
                                                             constant:4],
            [[[self subtitleLabel] bottomAnchor] constraintLessThanOrEqualToAnchor:[[self iconImageView] bottomAnchor]
                                                                          constant:-1]
        ]];
    }

    return self;
}

@end
