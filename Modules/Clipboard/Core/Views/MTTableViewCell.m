//
//  MTTableViewCell.m
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import "MTTableViewCell.h"
#import "MTTableViewCellContent.h"

static CGFloat const kMTTableViewCellContentImageWidth = 70;
static CGFloat const kMTTableViewCellContentImageSingleLineHeight = 40;
static CGFloat const kMTTableViewCellContentImageAdditionalLineHeight = 15;
static NSUInteger const kMTTableViewCellMaximumPreviewLineCount = 3;

@interface MTTableViewCellPreviewLabel : UILabel
@end

@implementation MTTableViewCellPreviewLabel

- (void)drawTextInRect:(CGRect)rect {
    CGRect textRect = [self textRectForBounds:rect limitedToNumberOfLines:[self numberOfLines]];
    textRect.origin = rect.origin;
    textRect.size.width = rect.size.width;
    [super drawTextInRect:textRect];
}

@end

@interface MTTableViewCell ()
@property(nonatomic, copy, nullable) NSString *representedImageName;
@end

@implementation MTTableViewCell

+ (NSString *)reuseIdentifierForContent:(MTTableViewCellContent *)content {
    NSUInteger lineCount = MIN(MAX([content previewLineCount], 1), kMTTableViewCellMaximumPreviewLineCount);
    BOOL hasContentImageSlot = [content contentImage] || [[content thumbnailImageName] length] > 0;
    BOOL hasContentText = [[content contentText] length] > 0;
    return [NSString stringWithFormat:@"MTTableViewCell-%lu-%d-%d-%d", (unsigned long)lineCount,
                                      hasContentImageSlot, hasContentText, [content showsDetail]];
}

+ (NSString *)galleryReuseIdentifierForContent:(MTTableViewCellContent *)content {
    BOOL hasContentImageSlot = [content contentImage] || [[content thumbnailImageName] length] > 0;
    return [NSString stringWithFormat:@"MTGalleryCell-%d-%d", hasContentImageSlot, [content showsDetail]];
}

+ (CGSize)contentImageViewSizeForPreviewLineCount:(NSUInteger)previewLineCount {
    NSUInteger lineCount = MIN(MAX(previewLineCount, 1), kMTTableViewCellMaximumPreviewLineCount);
    CGFloat height = kMTTableViewCellContentImageSingleLineHeight +
                     (lineCount - 1) * kMTTableViewCellContentImageAdditionalLineHeight;
    return CGSizeMake(kMTTableViewCellContentImageWidth, height);
}

+ (CGSize)contentImageThumbnailSize {
    CGSize maximumViewSize = [self contentImageViewSizeForPreviewLineCount:kMTTableViewCellMaximumPreviewLineCount];
    CGFloat sideLength = MAX(maximumViewSize.width, maximumViewSize.height);
    return CGSizeMake(sideLength, sideLength);
}

+ (CGSize)galleryContentImageThumbnailSize {
    return CGSizeMake(240, 180);
}

- (instancetype)initWithGalleryContent:(MTTableViewCellContent *)content
                         reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (!self) {
        return nil;
    }

    [self setBackgroundColor:[UIColor clearColor]];
    [self setSelectionStyle:UITableViewCellSelectionStyleNone];
    [[self contentView] setBackgroundColor:[UIColor secondarySystemBackgroundColor]];
    [[[self contentView] layer] setCornerRadius:12];
    [[[self contentView] layer] setBorderWidth:1.0 / [UIScreen mainScreen].scale];
    [[[self contentView] layer] setBorderColor:[[UIColor separatorColor] colorWithAlphaComponent:0.55].CGColor];
    [[self contentView] setClipsToBounds:YES];

    UIView *previewView = [[UIView alloc] init];
    [previewView setBackgroundColor:[UIColor tertiarySystemBackgroundColor]];
    [[self contentView] addSubview:previewView];
    [previewView setTranslatesAutoresizingMaskIntoConstraints:NO];

    [self setIconImageView:[[UIImageView alloc] init]];
    [[self iconImageView] setContentMode:UIViewContentModeScaleAspectFit];
    [[self iconImageView] setClipsToBounds:YES];
    [[[self iconImageView] layer] setCornerRadius:6];
    [[self contentView] addSubview:[self iconImageView]];
    [[self iconImageView] setTranslatesAutoresizingMaskIntoConstraints:NO];

    [self setHeaderLabel:[[UILabel alloc] init]];
    [[self headerLabel] setFont:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]];
    [[self headerLabel] setTextColor:[UIColor labelColor]];
    [[self headerLabel] setLineBreakMode:NSLineBreakByTruncatingTail];
    [[self contentView] addSubview:[self headerLabel]];
    [[self headerLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];

    [self setDetailLabel:[[UILabel alloc] init]];
    [[self detailLabel] setFont:[UIFont systemFontOfSize:10]];
    [[self detailLabel] setTextColor:[UIColor secondaryLabelColor]];
    [[self detailLabel] setLineBreakMode:NSLineBreakByTruncatingTail];
    [[self contentView] addSubview:[self detailLabel]];
    [[self detailLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];

    BOOL hasContentImageSlot = [content contentImage] || [[content thumbnailImageName] length] > 0;
    UIImageView *contentTypeImageView = nil;
    if (hasContentImageSlot) {
        [self setContentImageView:[[UIImageView alloc] init]];
        [[self contentImageView] setContentMode:UIViewContentModeScaleAspectFill];
        [[self contentImageView] setClipsToBounds:YES];
        [previewView addSubview:[self contentImageView]];
        [[self contentImageView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self contentImageView] leadingAnchor] constraintEqualToAnchor:[previewView leadingAnchor]],
            [[[self contentImageView] trailingAnchor] constraintEqualToAnchor:[previewView trailingAnchor]],
            [[[self contentImageView] topAnchor] constraintEqualToAnchor:[previewView topAnchor]],
            [[[self contentImageView] bottomAnchor] constraintEqualToAnchor:[previewView bottomAnchor]]
        ]];
    } else {
        contentTypeImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"text.alignleft"]];
        [contentTypeImageView setPreferredSymbolConfiguration:
                                  [UIImageSymbolConfiguration configurationWithPointSize:11
                                                                                 weight:UIImageSymbolWeightMedium]];
        [contentTypeImageView setTintColor:[UIColor secondaryLabelColor]];
        [contentTypeImageView setContentMode:UIViewContentModeScaleAspectFit];
        [[self contentView] addSubview:contentTypeImageView];
        [contentTypeImageView setTranslatesAutoresizingMaskIntoConstraints:NO];

        [self setContentLabel:[[MTTableViewCellPreviewLabel alloc] init]];
        [[self contentLabel] setFont:[UIFont systemFontOfSize:12]];
        [[self contentLabel] setTextColor:[UIColor labelColor]];
        [[self contentLabel] setLineBreakMode:NSLineBreakByTruncatingTail];
        [[self contentLabel] setNumberOfLines:3];
        [previewView addSubview:[self contentLabel]];
        [[self contentLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self contentLabel] leadingAnchor] constraintEqualToAnchor:[previewView leadingAnchor] constant:9],
            [[[self contentLabel] trailingAnchor] constraintEqualToAnchor:[previewView trailingAnchor] constant:-9],
            [[[self contentLabel] topAnchor] constraintEqualToAnchor:[previewView topAnchor] constant:7],
            [[[self contentLabel] bottomAnchor] constraintLessThanOrEqualToAnchor:[previewView bottomAnchor] constant:-7]
        ]];
    }

    NSLayoutXAxisAnchor *metadataTrailingAnchor =
        contentTypeImageView ? [contentTypeImageView leadingAnchor] : [[self contentView] trailingAnchor];
    CGFloat metadataTrailingConstant = contentTypeImageView ? -6 : -8;

    [NSLayoutConstraint activateConstraints:@[
        [[previewView leadingAnchor] constraintEqualToAnchor:[[self contentView] leadingAnchor]],
        [[previewView trailingAnchor] constraintEqualToAnchor:[[self contentView] trailingAnchor]],
        [[previewView topAnchor] constraintEqualToAnchor:[[self contentView] topAnchor]],
        [[previewView heightAnchor] constraintEqualToAnchor:[[self contentView] heightAnchor] multiplier:0.60],
        [[[self iconImageView] leadingAnchor] constraintEqualToAnchor:[[self contentView] leadingAnchor] constant:8],
        [[[self iconImageView] bottomAnchor] constraintEqualToAnchor:[[self contentView] bottomAnchor] constant:-8],
        [[[self iconImageView] widthAnchor] constraintEqualToConstant:25],
        [[[self iconImageView] heightAnchor] constraintEqualToConstant:25],
        [[[self headerLabel] leadingAnchor] constraintEqualToAnchor:[[self iconImageView] trailingAnchor] constant:7],
        [[[self headerLabel] topAnchor] constraintEqualToAnchor:[previewView bottomAnchor] constant:5],
        [[[self headerLabel] trailingAnchor] constraintLessThanOrEqualToAnchor:metadataTrailingAnchor
                                                                      constant:metadataTrailingConstant],
        [[[self detailLabel] leadingAnchor] constraintEqualToAnchor:[[self headerLabel] leadingAnchor]],
        [[[self detailLabel] topAnchor] constraintEqualToAnchor:[[self headerLabel] bottomAnchor] constant:1],
        [[[self detailLabel] trailingAnchor] constraintLessThanOrEqualToAnchor:metadataTrailingAnchor
                                                                      constant:metadataTrailingConstant]
    ]];

    if (contentTypeImageView) {
        [NSLayoutConstraint activateConstraints:@[
            [[contentTypeImageView trailingAnchor] constraintEqualToAnchor:[[self contentView] trailingAnchor]
                                                                  constant:-8],
            [[contentTypeImageView bottomAnchor] constraintEqualToAnchor:[[self contentView] bottomAnchor] constant:-8],
            [[contentTypeImageView widthAnchor] constraintEqualToConstant:16],
            [[contentTypeImageView heightAnchor] constraintEqualToConstant:16]
        ]];
    }

    [self applyContent:content];
    return self;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
                      content:(MTTableViewCellContent *)content
              reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];

    if (self) {
        NSUInteger lineCount = MIN(MAX([content previewLineCount], 1), kMTTableViewCellMaximumPreviewLineCount);
        CGSize contentImageViewSize = [[self class] contentImageViewSizeForPreviewLineCount:lineCount];
        BOOL hasContentText = [[content contentText] length] > 0;
        BOOL showsDetail = [content showsDetail];
        [self setBackgroundColor:[UIColor clearColor]];
        UIView *selectedBackgroundView = [[UIView alloc] init];
        UIColor *selectedBackgroundColor =
            [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
              if ([traitCollection userInterfaceStyle] == UIUserInterfaceStyleDark) {
                  return [UIColor colorWithWhite:1 alpha:0.08];
              }

              return [UIColor colorWithWhite:0 alpha:0.055];
            }];
        [selectedBackgroundView setBackgroundColor:selectedBackgroundColor];
        [self setSelectedBackgroundView:selectedBackgroundView];

        [self setIconImageView:[[UIImageView alloc] init]];
        [[self iconImageView] setContentMode:UIViewContentModeScaleAspectFit];
        [[self iconImageView] setClipsToBounds:YES];
        [[[self iconImageView] layer] setCornerRadius:10];
        [self addSubview:[self iconImageView]];

        [[self iconImageView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self iconImageView] widthAnchor] constraintEqualToConstant:40],
            [[[self iconImageView] heightAnchor] constraintEqualToConstant:40],
            [[[self iconImageView] centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
            [[[self iconImageView] leadingAnchor] constraintEqualToAnchor:[self leadingAnchor] constant:24]
        ]];

        UIImage *contentImage = [content contentImage];
        NSString *thumbnailImageName = [content thumbnailImageName];
        BOOL hasContentImageSlot = contentImage || [thumbnailImageName length] > 0;
        [self setRepresentedImageName:thumbnailImageName];
        if (hasContentImageSlot) {
            [self setContentImageView:[[UIImageView alloc] init]];
            [[self contentImageView] setImage:contentImage];

            [[self contentImageView] setContentMode:UIViewContentModeScaleAspectFill];
            [[self contentImageView] setClipsToBounds:YES];
            [[self contentImageView]
                setBackgroundColor:contentImage ? [UIColor clearColor] : [UIColor tertiarySystemFillColor]];
            [[[self contentImageView] layer] setCornerRadius:4];
            [self addSubview:[self contentImageView]];

            [[self contentImageView] setTranslatesAutoresizingMaskIntoConstraints:NO];
            [NSLayoutConstraint activateConstraints:@[
                [[[self contentImageView] widthAnchor] constraintEqualToConstant:contentImageViewSize.width],
                [[[self contentImageView] heightAnchor] constraintEqualToConstant:contentImageViewSize.height],
                [[[self contentImageView] centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
                [[[self contentImageView] trailingAnchor] constraintEqualToAnchor:[self trailingAnchor] constant:-24]
            ]];
        }

        [self setHeaderLabel:[[UILabel alloc] init]];
        [[self headerLabel] setFont:[UIFont systemFontOfSize:16 weight:UIFontWeightMedium]];
        [[self headerLabel] setTextColor:[UIColor labelColor]];
        [[self headerLabel] setLineBreakMode:NSLineBreakByTruncatingTail];
        [[self headerLabel] setContentHuggingPriority:UILayoutPriorityDefaultHigh
                                              forAxis:UILayoutConstraintAxisHorizontal];
        [[self headerLabel] setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                            forAxis:UILayoutConstraintAxisHorizontal];
        [self addSubview:[self headerLabel]];

        [[self headerLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[ [[[self headerLabel] leadingAnchor]
                                                    constraintEqualToAnchor:[[self iconImageView] trailingAnchor]
                                                                   constant:16] ]];

        NSLayoutXAxisAnchor *textTrailingAnchor =
            [self contentImageView] ? [[self contentImageView] leadingAnchor] : [self trailingAnchor];
        CGFloat textTrailingConstant = [self contentImageView] ? -16 : -24;

        [NSLayoutConstraint activateConstraints:@[ [[[self headerLabel] trailingAnchor]
                                                    constraintEqualToAnchor:textTrailingAnchor
                                                                   constant:textTrailingConstant] ]];

        if (hasContentText) {
            [self setContentLabel:[[MTTableViewCellPreviewLabel alloc] init]];
            [[self contentLabel] setFont:[UIFont systemFontOfSize:14]];
            [[self contentLabel] setTextColor:[[UIColor labelColor] colorWithAlphaComponent:0.8]];
            [[self contentLabel] setLineBreakMode:NSLineBreakByTruncatingTail];
            [[self contentLabel] setNumberOfLines:lineCount];
            [self addSubview:[self contentLabel]];
            [[self contentLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
            CGFloat previewLabelHeight = ceil([[[self contentLabel] font] lineHeight] * lineCount);
            [NSLayoutConstraint activateConstraints:@[
                [[[self contentLabel] topAnchor] constraintEqualToAnchor:[[self headerLabel] bottomAnchor] constant:2],
                [[[self contentLabel] leadingAnchor] constraintEqualToAnchor:[[self headerLabel] leadingAnchor]],
                [[[self contentLabel] trailingAnchor] constraintEqualToAnchor:textTrailingAnchor
                                                                     constant:textTrailingConstant],
                [[[self contentLabel] heightAnchor] constraintEqualToConstant:previewLabelHeight]
            ]];
        }

        if (showsDetail) {
            [self setDetailLabel:[[UILabel alloc] init]];
            [[self detailLabel] setFont:[UIFont systemFontOfSize:12]];
            [[self detailLabel] setTextColor:[UIColor secondaryLabelColor]];
            [[self detailLabel] setLineBreakMode:NSLineBreakByTruncatingTail];
            [self addSubview:[self detailLabel]];
            [[self detailLabel] setTranslatesAutoresizingMaskIntoConstraints:NO];
            [NSLayoutConstraint activateConstraints:@[
                [[[self detailLabel] leadingAnchor] constraintEqualToAnchor:[[self headerLabel] leadingAnchor]],
                [[[self detailLabel] trailingAnchor] constraintEqualToAnchor:textTrailingAnchor
                                                                    constant:textTrailingConstant]
            ]];
        }

        if (hasContentText) {
            [NSLayoutConstraint activateConstraints:@[ [[[self headerLabel] topAnchor]
                                                        constraintEqualToAnchor:[self topAnchor]
                                                                       constant:showsDetail ? 13 : 12] ]];
            if (showsDetail) {
                [NSLayoutConstraint activateConstraints:@[
                    [[[self detailLabel] topAnchor] constraintEqualToAnchor:[[self contentLabel] bottomAnchor]
                                                                   constant:2],
                    [[[self detailLabel] bottomAnchor] constraintLessThanOrEqualToAnchor:[self bottomAnchor]
                                                                                constant:-8]
                ]];
            } else {
                [NSLayoutConstraint activateConstraints:@[ [[[self contentLabel] bottomAnchor]
                                                            constraintLessThanOrEqualToAnchor:[self bottomAnchor]
                                                                                     constant:-10] ]];
            }
        } else if (showsDetail) {
            [NSLayoutConstraint activateConstraints:@[
                [[[self headerLabel] centerYAnchor] constraintEqualToAnchor:[self centerYAnchor] constant:-8],
                [[[self headerLabel] topAnchor] constraintGreaterThanOrEqualToAnchor:[self topAnchor] constant:8],
                [[[self detailLabel] topAnchor] constraintEqualToAnchor:[[self headerLabel] bottomAnchor] constant:1],
                [[[self detailLabel] bottomAnchor] constraintLessThanOrEqualToAnchor:[self bottomAnchor] constant:-8]
            ]];
        } else {
            [NSLayoutConstraint activateConstraints:@[ [[[self headerLabel] centerYAnchor]
                                                        constraintEqualToAnchor:[self centerYAnchor]] ]];
        }

        [self applyContent:content];
    }

    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self setHidden:NO];
    [self setRepresentedImageName:nil];
    [[self iconImageView] setImage:nil];
    [[self headerLabel] setAttributedText:nil];
    [[self headerLabel] setText:nil];
    [[self contentLabel] setAttributedText:nil];
    [[self contentLabel] setText:nil];
    [[self detailLabel] setAttributedText:nil];
    [[self detailLabel] setText:nil];
    [[self contentImageView] setImage:nil];
    [[self contentImageView] setBackgroundColor:[UIColor tertiarySystemFillColor]];
}

- (void)applyDetailContent:(MTTableViewCellContent *)content {
    NSAttributedString *attributedDetailText = [content attributedDetailText];
    if (!attributedDetailText) {
        [[self detailLabel] setAttributedText:nil];
        [[self detailLabel] setText:nil];
        return;
    }

    NSMutableAttributedString *styledDetailText = [attributedDetailText mutableCopy];
    [styledDetailText addAttribute:NSFontAttributeName
                             value:[[self detailLabel] font]
                             range:NSMakeRange(0, [styledDetailText length])];
    [[self detailLabel] setAttributedText:styledDetailText];
}

- (void)applyContent:(MTTableViewCellContent *)content {
    [[self iconImageView] setImage:[content icon]];

    if ([content attributedDisplayName]) {
        NSMutableAttributedString *attributedDisplayName = [[content attributedDisplayName] mutableCopy];
        NSRange fullRange = NSMakeRange(0, [attributedDisplayName length]);
        [attributedDisplayName addAttribute:NSFontAttributeName value:[[self headerLabel] font] range:fullRange];
        [attributedDisplayName addAttribute:NSForegroundColorAttributeName
                                      value:[[self headerLabel] textColor]
                                      range:fullRange];
        [[self headerLabel] setAttributedText:attributedDisplayName];
    } else {
        [[self headerLabel] setAttributedText:nil];
        [[self headerLabel] setText:[content displayName]];
    }

    NSUInteger lineCount = MIN(MAX([content previewLineCount], 1), kMTTableViewCellMaximumPreviewLineCount);
    [[self contentLabel] setNumberOfLines:lineCount];
    if ([content attributedContentText]) {
        NSMutableAttributedString *attributedText = [[content attributedContentText] mutableCopy];
        NSRange fullRange = NSMakeRange(0, [attributedText length]);
        [attributedText addAttribute:NSFontAttributeName value:[[self contentLabel] font] range:fullRange];
        [attributedText addAttribute:NSForegroundColorAttributeName
                               value:[[self contentLabel] textColor]
                               range:fullRange];
        [[self contentLabel] setAttributedText:attributedText];
    } else {
        [[self contentLabel] setAttributedText:nil];
        [[self contentLabel] setText:[content contentText] ?: @""];
    }
    [self applyDetailContent:content];

    UIImage *contentImage = [content contentImage];
    [self setRepresentedImageName:[content thumbnailImageName]];
    [[self contentImageView] setImage:contentImage];
    [[self contentImageView]
        setBackgroundColor:contentImage ? [UIColor clearColor] : [UIColor tertiarySystemFillColor]];
}

- (void)setContentImage:(UIImage *)image forImageName:(NSString *)imageName {
    if ([[self representedImageName] length] == 0 || ![[self representedImageName] isEqualToString:imageName]) {
        return;
    }

    if (![self contentImageView]) {
        return;
    }

    [[self contentImageView] setImage:image];
    [[self contentImageView] setBackgroundColor:image ? [UIColor clearColor] : [UIColor tertiarySystemFillColor]];
}

@end
