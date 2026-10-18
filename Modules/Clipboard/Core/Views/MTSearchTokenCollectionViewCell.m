//
//  MTSearchTokenCollectionViewCell.m
//  Mt
//

#import "MTSearchTokenCollectionViewCell.h"

#import <QuartzCore/QuartzCore.h>

static CGFloat const kMTSearchTokenCellIconSize = 20;

@interface MTSearchTokenCollectionViewCell ()
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *titleLabel;
@end

@implementation MTSearchTokenCollectionViewCell

+ (NSString *)reuseIdentifier {
    return @"MTSearchTokenCollectionViewCell";
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [[self contentView] setBackgroundColor:[UIColor tertiarySystemFillColor]];
        [[[self contentView] layer] setCornerRadius:8];
        [[[self contentView] layer] setCornerCurve:kCACornerCurveContinuous];

        _iconView = [[UIImageView alloc] init];
        [_iconView setContentMode:UIViewContentModeScaleAspectFit];
        [_iconView setTintColor:[UIColor labelColor]];
        [[self contentView] addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        [_titleLabel setFont:[UIFont systemFontOfSize:14 weight:UIFontWeightMedium]];
        [_titleLabel setTextColor:[UIColor labelColor]];
        [_titleLabel setLineBreakMode:NSLineBreakByTruncatingTail];
        [[self contentView] addSubview:_titleLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect bounds = [[self contentView] bounds];
    CGFloat iconX = 12;
    CGFloat iconY = floor((CGRectGetHeight(bounds) - kMTSearchTokenCellIconSize) / 2.0);
    CGRect iconFrame = CGRectMake(iconX, iconY, kMTSearchTokenCellIconSize, kMTSearchTokenCellIconSize);
    [[self iconView] setFrame:iconFrame];

    CGFloat titleX = CGRectGetMaxX([[self iconView] frame]) + 8;
    [[self titleLabel] setFrame:CGRectMake(titleX, 0, CGRectGetWidth(bounds) - titleX - 10, CGRectGetHeight(bounds))];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [[self iconView] setImage:nil];
    [[self iconView] setHidden:NO];
    [[self titleLabel] setText:nil];
    [self setActiveFilterHighlighted:NO];
}

- (void)setActiveFilterHighlighted:(BOOL)activeFilterHighlighted {
    _activeFilterHighlighted = activeFilterHighlighted;
    if (activeFilterHighlighted) {
        [[self contentView] setBackgroundColor:[[UIColor systemBlueColor] colorWithAlphaComponent:0.16]];
        [[self titleLabel] setTextColor:[UIColor systemBlueColor]];
        [[self iconView] setTintColor:[UIColor systemBlueColor]];
    } else {
        [[self contentView] setBackgroundColor:[UIColor tertiarySystemFillColor]];
        [[self titleLabel] setTextColor:[UIColor labelColor]];
        [[self iconView] setTintColor:[UIColor labelColor]];
    }
}

- (void)configureWithTitle:(NSString *)title icon:(nullable UIImage *)icon {
    [[self titleLabel] setText:title];
    [[self iconView] setImage:icon];
    [[self iconView] setHidden:icon == nil];
}

@end
