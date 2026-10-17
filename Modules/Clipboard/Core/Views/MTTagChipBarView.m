//
//  MTTagChipBarView.m
//  Mt
//

#import "MTTagChipBarView.h"

#import "MTEdgeFadingScrollView.h"
#import "MTPasteboardManager.h"
#import "MTTag.h"
#import "MTTagColorFormatter.h"
#import "MTTagDotView.h"

#import <QuartzCore/QuartzCore.h>

static CGFloat const kMTTagChipBarHeight = 54;
static CGFloat const kMTTagChipHeight = 32;
static CGFloat const kMTTagChipMaximumWidth = 136;
static CGFloat const kMTTagChipHorizontalInset = 20;
static CGFloat const kMTTagChipSpacing = 8;
static CGFloat const kMTTagChipLeadingInset = 11;
static CGFloat const kMTTagChipTrailingInset = 13;
static CGFloat const kMTTagChipDotSlotSize = 20;
static CGFloat const kMTTagChipDotSize = 14;
static CGFloat const kMTTagChipDotBorderWidth = 1.25;
static CGFloat const kMTTagChipDotLabelSpacing = 7;
static CGFloat const kMTTagChipFadeHeight = 20;
static CGFloat const kMTTagChipFloatingLightMaterialAlpha = 1.0;
static CGFloat const kMTTagChipFloatingDarkMaterialAlpha = 0.38;
static CGFloat const kMTTagChipFloatingLightFadeAlpha = 0.58;
static CGFloat const kMTTagChipFloatingDarkFadeAlpha = 0.0;
static CGFloat const kMTTagChipFloatingProgressDistance = 42;

@interface MTTagChipButton : UIControl

#pragma mark - State

@property(nonatomic, copy, nullable) NSString *tagUUID;
@property(nonatomic, copy, nullable) NSString *hexColor;

#pragma mark - Views

@property(nonatomic, strong) MTTagDotView *dotView;
@property(nonatomic, strong) UILabel *textLabel;

#pragma mark - Configuration

- (void)configureWithTitle:(NSString *)title
                   tagUUID:(nullable NSString *)tagUUID
                  hexColor:(nullable NSString *)hexColor
                  selected:(BOOL)selected;
- (UIColor *)colorByResolvingColor:(UIColor *)color alpha:(CGFloat)alpha;
- (UIColor *)resolvedColorForCurrentTrait:(UIColor *)color;
- (CGFloat)preferredWidth;
@end

@implementation MTTagChipButton

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setIsAccessibilityElement:YES];
        [[self layer] setCornerRadius:kMTTagChipHeight / 2.0];
        [[self layer] setCornerCurve:kCACornerCurveContinuous];
        [[self layer] setBorderWidth:1.0 / [UIScreen mainScreen].scale];

        _dotView = [[MTTagDotView alloc] init];
        [_dotView setDotDiameter:kMTTagChipDotSize];
        [_dotView setBorderWidth:kMTTagChipDotBorderWidth];
        [self addSubview:_dotView];

        _textLabel = [[UILabel alloc] init];
        [_textLabel setFont:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium]];
        [_textLabel setLineBreakMode:NSLineBreakByTruncatingTail];
        [self addSubview:_textLabel];
    }
    return self;
}

#pragma mark - Configuration

- (void)configureWithTitle:(NSString *)title
                   tagUUID:(nullable NSString *)tagUUID
                  hexColor:(nullable NSString *)hexColor
                  selected:(BOOL)selected {
    [self setTagUUID:[tagUUID copy]];
    [self setHexColor:[hexColor copy]];
    [self setSelected:selected];
    [[self textLabel] setText:title ?: @""];
    [self setAccessibilityLabel:title ?: @""];
    [self updateStyle];
    [self setNeedsLayout];
}

#pragma mark - Colors

- (UIColor *)selectedFillColor {
    if ([[self hexColor] length] > 0) {
        return [[MTTagColorFormatter visibleColorFromHexColor:[self hexColor]] colorWithAlphaComponent:0.12];
    }
    return [UIColor tertiarySystemFillColor];
}

- (UIColor *)normalFillColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
      BOOL dark = [traitCollection userInterfaceStyle] == UIUserInterfaceStyleDark;
      return [UIColor colorWithWhite:(dark ? 1.0 : 0.0) alpha:(dark ? 0.09 : 0.035)];
    }];
}

- (UIColor *)borderColor {
    if ([self isSelected] && [[self hexColor] length] > 0) {
        return [[MTTagColorFormatter borderColorFromHexColor:[self hexColor]] colorWithAlphaComponent:0.78];
    }
    if ([self isSelected]) {
        return [self colorByResolvingColor:[UIColor labelColor] alpha:0.24];
    }
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
      BOOL dark = [traitCollection userInterfaceStyle] == UIUserInterfaceStyleDark;
      UIColor *separatorColor = [[UIColor separatorColor] resolvedColorWithTraitCollection:traitCollection];
      return [separatorColor colorWithAlphaComponent:(dark ? 0.32 : 0.24)];
    }];
}

- (void)updateStyle {
    UIColor *textColor = [self isSelected] ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    [[self textLabel] setTextColor:textColor];
    [self setBackgroundColor:[self isSelected] ? [self selectedFillColor] : [self normalFillColor]];
    [[self layer] setBorderWidth:[self isSelected] ? 1.0 : 1.0 / [UIScreen mainScreen].scale];
    [[self layer] setBorderColor:[[self resolvedColorForCurrentTrait:[self borderColor]] CGColor]];
    [self updateDotStyle];
    [self setAlpha:[self isHighlighted] ? 0.72 : 1.0];
}

- (void)updateDotStyle {
    if ([[self hexColor] length] > 0) {
        [[self dotView] configureWithFillColor:[MTTagColorFormatter visibleColorFromHexColor:[self hexColor]]
                                   borderColor:[MTTagColorFormatter borderColorFromHexColor:[self hexColor]]];
        return;
    }

    UIColor *tintColor = [self isSelected] ? [self colorByResolvingColor:[UIColor labelColor] alpha:0.64]
                                           : [self colorByResolvingColor:[UIColor secondaryLabelColor] alpha:0.54];
    [[self dotView] configureNoTagWithTintColor:tintColor];
}

- (UIColor *)colorByResolvingColor:(UIColor *)color alpha:(CGFloat)alpha {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
      UIColor *resolvedColor = [color resolvedColorWithTraitCollection:traitCollection];
      return [resolvedColor colorWithAlphaComponent:alpha];
    }];
}

- (UIColor *)resolvedColorForCurrentTrait:(UIColor *)color {
    return [color resolvedColorWithTraitCollection:[self traitCollection]];
}

#pragma mark - State

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self updateStyle];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self updateStyle];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateStyle];
}

#pragma mark - Layout

- (CGFloat)preferredWidth {
    CGFloat maximumLabelWidth = kMTTagChipMaximumWidth - kMTTagChipLeadingInset - kMTTagChipDotSlotSize -
                                kMTTagChipDotLabelSpacing - kMTTagChipTrailingInset;
    CGSize labelSize = [[self textLabel] sizeThatFits:CGSizeMake(maximumLabelWidth, kMTTagChipHeight)];
    CGFloat width = kMTTagChipLeadingInset + kMTTagChipDotSlotSize + kMTTagChipDotLabelSpacing +
                    ceil(labelSize.width) + kMTTagChipTrailingInset;
    return MIN(MAX(width, kMTTagChipHeight), kMTTagChipMaximumWidth);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect bounds = [self bounds];
    CGFloat dotY = floor((CGRectGetHeight(bounds) - kMTTagChipDotSlotSize) / 2.0);
    [[self dotView]
        setFrame:CGRectMake(kMTTagChipLeadingInset, dotY, kMTTagChipDotSlotSize, kMTTagChipDotSlotSize)];

    CGFloat x = CGRectGetMaxX([[self dotView] frame]) + kMTTagChipDotLabelSpacing;
    CGFloat labelWidth = MAX(CGRectGetWidth(bounds) - x - kMTTagChipTrailingInset, 0);
    [[self textLabel] setFrame:CGRectMake(x, 0, labelWidth, CGRectGetHeight(bounds))];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateStyle];
}
#pragma clang diagnostic pop

@end

@interface MTTagChipBarFadeView : UIView
@end

@implementation MTTagChipBarFadeView

#pragma mark - Layer

+ (Class)layerClass {
    return [CAGradientLayer class];
}

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self updateGradientColors];
    }
    return self;
}

#pragma mark - Appearance

- (void)updateGradientColors {
    BOOL dark = [[self traitCollection] userInterfaceStyle] == UIUserInterfaceStyleDark;
    UIColor *backgroundColor = dark ? [UIColor clearColor] : [UIColor systemBackgroundColor];
    CGFloat endAlpha = dark ? 0.0 : 0.08;
    CAGradientLayer *gradientLayer = (CAGradientLayer *)[self layer];
    [gradientLayer setStartPoint:CGPointMake(0.5, 0.0)];
    [gradientLayer setEndPoint:CGPointMake(0.5, 1.0)];
    [gradientLayer setColors:@[
        (__bridge id)[[backgroundColor colorWithAlphaComponent:0.0] CGColor],
        (__bridge id)[[backgroundColor colorWithAlphaComponent:endAlpha] CGColor]
    ]];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateGradientColors];
}
#pragma clang diagnostic pop

@end

@interface MTTagChipBarView ()

#pragma mark - Views

@property(nonatomic, strong) UIVisualEffectView *materialView;
@property(nonatomic, strong) CAGradientLayer *materialMaskLayer;
@property(nonatomic, strong) MTTagChipBarFadeView *fadeView;
@property(nonatomic, strong) MTEdgeFadingScrollView *scrollView;

#pragma mark - Data

@property(nonatomic, strong) NSMutableArray<MTTagChipButton *> *chipButtons;

#pragma mark - State

@property(nonatomic, assign, readwrite, getter=isSettled) BOOL settled;
@property(nonatomic, assign) CGFloat floatingProgress;
@property(nonatomic, assign) BOOL shouldRevealSelectedTagAfterLayout;
@end

@implementation MTTagChipBarView

#pragma mark - Metrics

+ (CGFloat)preferredHeight {
    return kMTTagChipBarHeight;
}

+ (CGFloat)floatingProgressForScrollView:(UIScrollView *)scrollView {
    UIEdgeInsets adjustedInset = [scrollView adjustedContentInset];
    CGFloat viewportHeight = CGRectGetHeight([scrollView bounds]) - adjustedInset.top - adjustedInset.bottom;
    CGFloat contentHeight = [scrollView contentSize].height;
    if (viewportHeight <= 0 || contentHeight <= viewportHeight + 0.5) {
        return 0.0;
    }

    CGFloat visibleBottomY = [scrollView contentOffset].y + CGRectGetHeight([scrollView bounds]) - adjustedInset.bottom;
    CGFloat distanceToBottom = contentHeight - visibleBottomY;
    return MIN(MAX(distanceToBottom / kMTTagChipFloatingProgressDistance, 0.0), 1.0);
}

#pragma mark - Appearance

- (BOOL)isDarkMode {
    return [[self traitCollection] userInterfaceStyle] == UIUserInterfaceStyleDark;
}

- (CGFloat)floatingMaterialAlpha {
    return [self isDarkMode] ? kMTTagChipFloatingDarkMaterialAlpha : kMTTagChipFloatingLightMaterialAlpha;
}

- (CGFloat)floatingFadeAlpha {
    return [self isDarkMode] ? kMTTagChipFloatingDarkFadeAlpha : kMTTagChipFloatingLightFadeAlpha;
}

- (UIBlurEffect *)materialEffect {
    UIBlurEffectStyle style =
        [self isDarkMode] ? UIBlurEffectStyleSystemUltraThinMaterialDark : UIBlurEffectStyleSystemUltraThinMaterial;
    return [UIBlurEffect effectWithStyle:style];
}

- (void)updateMaterialEffect {
    [UIView performWithoutAnimation:^{
      [[self materialView] setEffect:[self materialEffect]];
    }];
}

- (void)updateFloatingLayerAlphas {
    [[self materialView] setAlpha:[self floatingMaterialAlpha] * [self floatingProgress]];
    [[self fadeView] setAlpha:[self floatingFadeAlpha] * [self floatingProgress]];
}

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setClipsToBounds:NO];
        [self setHidden:YES];

        _materialView = [[UIVisualEffectView alloc] initWithEffect:[self materialEffect]];
        [_materialView setUserInteractionEnabled:NO];
        [_materialView setHidden:YES];
        [_materialView setAlpha:0.0];
        _materialMaskLayer = [CAGradientLayer layer];
        [_materialMaskLayer setStartPoint:CGPointMake(0.5, 0.0)];
        [_materialMaskLayer setEndPoint:CGPointMake(0.5, 1.0)];
        [_materialMaskLayer setColors:@[
            (__bridge id)[[UIColor clearColor] CGColor], (__bridge id)[[UIColor blackColor] CGColor],
            (__bridge id)[[UIColor blackColor] CGColor]
        ]];
        [[_materialView layer] setMask:_materialMaskLayer];
        [self addSubview:_materialView];

        _fadeView = [[MTTagChipBarFadeView alloc] init];
        [_fadeView setUserInteractionEnabled:NO];
        [_fadeView setAlpha:0.0];
        [self addSubview:_fadeView];

        _scrollView = [[MTEdgeFadingScrollView alloc] init];
        [_scrollView setShowsHorizontalScrollIndicator:NO];
        [_scrollView setAlwaysBounceHorizontal:YES];
        [_scrollView setBackgroundColor:[UIColor clearColor]];
        [_scrollView setEdgeFadeAxis:MTEdgeFadeAxisHorizontal];
        [_scrollView setEdgeFadeWidth:kMTTagChipHorizontalInset];
        [_scrollView setEdgeFadeEnabled:YES];
        [self addSubview:_scrollView];

        _chipButtons = [[NSMutableArray alloc] init];
        _settled = YES;
    }
    return self;
}

#pragma mark - Configuration

- (void)configureWithTags:(NSArray<MTTag *> *)tags selectedTagUUID:(NSString *)selectedTagUUID {
    for (MTTagChipButton *button in [self chipButtons]) {
        [button removeFromSuperview];
    }
    [[self chipButtons] removeAllObjects];

    [self setSelectedTagUUID:[selectedTagUUID copy]];
    [self setShouldRevealSelectedTagAfterLayout:([selectedTagUUID length] > 0)];
    [self setHidden:[tags count] == 0];
    if ([tags count] == 0) {
        [self setShouldRevealSelectedTagAfterLayout:NO];
        [[self scrollView] setContentSize:CGSizeZero];
        return;
    }

    NSBundle *bundle = [MTPasteboardManager localizationBundle];
    NSString *noTagTitle = [bundle localizedStringForKey:@"No Tag" value:nil table:@"Tweak"];
    [self addChipWithTitle:noTagTitle tagUUID:nil hexColor:nil];
    for (MTTag *tag in tags) {
        [self addChipWithTitle:[tag title] tagUUID:[tag uuid] hexColor:[tag hexColor]];
    }

    [[self scrollView] setContentOffset:CGPointZero animated:NO];
    [[self scrollView] updateEdgeFadeMask];
    [self setNeedsLayout];
}

#pragma mark - Selection

- (MTTagChipButton *)chipButtonForSelectedTag {
    if ([[self selectedTagUUID] length] == 0) {
        return nil;
    }

    for (MTTagChipButton *button in [self chipButtons]) {
        if ([[button tagUUID] isEqualToString:[self selectedTagUUID]]) {
            return button;
        }
    }

    return nil;
}

- (BOOL)revealSelectedTagIfPossible {
    if ([[self selectedTagUUID] length] == 0) {
        return YES;
    }

    MTEdgeFadingScrollView *scrollView = [self scrollView];
    CGFloat visibleWidth = CGRectGetWidth([scrollView bounds]);
    CGFloat contentWidth = [scrollView contentSize].width;
    if (visibleWidth <= 0 || contentWidth <= 0) {
        return NO;
    }

    MTTagChipButton *button = [self chipButtonForSelectedTag];
    if (!button) {
        return YES;
    }

    CGFloat currentOffsetX = [scrollView contentOffset].x;
    CGRect visibleRect = CGRectMake(currentOffsetX, 0, visibleWidth, CGRectGetHeight([scrollView bounds]));
    CGRect comfortableRect = CGRectInset(visibleRect, kMTTagChipHorizontalInset, 0);
    CGRect checkRect =
        CGRectGetWidth(comfortableRect) >= CGRectGetWidth([button frame]) ? comfortableRect : visibleRect;
    if (CGRectContainsRect(checkRect, [button frame])) {
        return YES;
    }

    CGFloat targetOffsetX = currentOffsetX;
    if (CGRectGetMinX([button frame]) < CGRectGetMinX(checkRect)) {
        targetOffsetX = CGRectGetMinX([button frame]) - kMTTagChipHorizontalInset;
    } else if (CGRectGetMaxX([button frame]) > CGRectGetMaxX(checkRect)) {
        targetOffsetX = CGRectGetMaxX([button frame]) - visibleWidth + kMTTagChipHorizontalInset;
    }

    CGFloat maximumOffsetX = MAX(contentWidth - visibleWidth, 0);
    targetOffsetX = MIN(MAX(floor(targetOffsetX), 0), maximumOffsetX);
    [scrollView setContentOffset:CGPointMake(targetOffsetX, [scrollView contentOffset].y) animated:NO];
    [scrollView updateEdgeFadeMask];
    return YES;
}

- (void)addChipWithTitle:(NSString *)title tagUUID:(NSString *)tagUUID hexColor:(NSString *)hexColor {
    MTTagChipButton *button = [[MTTagChipButton alloc] initWithFrame:CGRectZero];
    BOOL selected = ([tagUUID length] == 0 && [[self selectedTagUUID] length] == 0) ||
                    [[self selectedTagUUID] isEqualToString:tagUUID ?: @""];
    [[self scrollView] addSubview:button];
    [[self chipButtons] addObject:button];
    [button configureWithTitle:title tagUUID:tagUUID hexColor:hexColor selected:selected];
    [button addTarget:self action:@selector(handleChipPressed:) forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark - State

- (void)setSelectedTagUUID:(NSString *)selectedTagUUID {
    _selectedTagUUID = [selectedTagUUID length] > 0 ? [selectedTagUUID copy] : nil;
    for (MTTagChipButton *button in [self chipButtons]) {
        BOOL selected = ([[button tagUUID] length] == 0 && [_selectedTagUUID length] == 0) ||
                        [[button tagUUID] isEqualToString:_selectedTagUUID ?: @""];
        [button setSelected:selected];
    }
    [self setNeedsLayout];
}

#pragma mark - Actions

- (void)handleChipPressed:(MTTagChipButton *)button {
    if ([self selectionHandler]) {
        [self selectionHandler]([button tagUUID]);
    }
}

#pragma mark - Floating Material

- (void)setBottomMaterialExtension:(CGFloat)bottomMaterialExtension {
    CGFloat normalizedExtension = MAX(bottomMaterialExtension, 0.0);
    if (fabs(_bottomMaterialExtension - normalizedExtension) < 0.5) {
        return;
    }

    _bottomMaterialExtension = normalizedExtension;
    [self setNeedsLayout];
}

- (void)setFloatingProgress:(CGFloat)floatingProgress animated:(BOOL)animated {
    CGFloat normalizedProgress = MIN(MAX(floatingProgress, 0.0), 1.0);
    BOOL settled = normalizedProgress <= 0.001;
    if (fabs(_floatingProgress - normalizedProgress) < 0.001 && _settled == settled) {
        return;
    }

    _floatingProgress = normalizedProgress;
    _settled = settled;

    if (!settled) {
        [[self materialView] setHidden:NO];
    }

    void (^updates)(void) = ^{
      [self updateFloatingLayerAlphas];
    };

    if (!animated) {
        [UIView performWithoutAnimation:updates];
        [[self materialView] setHidden:settled];
        return;
    }

    [UIView animateWithDuration:0.18
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:updates
                     completion:^(BOOL finished) {
                       if (finished) {
                           [[self materialView] setHidden:[self isSettled]];
                       }
                     }];
}

- (void)setSettled:(BOOL)settled animated:(BOOL)animated {
    [self setFloatingProgress:(settled ? 0.0 : 1.0) animated:animated];
}

#pragma mark - Layout

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([[self traitCollection] hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateMaterialEffect];
        [UIView performWithoutAnimation:^{
          [self updateFloatingLayerAlphas];
        }];
    }
}
#pragma clang diagnostic pop

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect bounds = [self bounds];
    CGFloat bottomExtension = MAX([self bottomMaterialExtension], 0.0);
    CGRect materialFrame = CGRectMake(0, -kMTTagChipFadeHeight, CGRectGetWidth(bounds),
                                      CGRectGetHeight(bounds) + kMTTagChipFadeHeight + bottomExtension);
    CGFloat fadeLocation =
        CGRectGetHeight(materialFrame) > 0 ? MIN(kMTTagChipFadeHeight / CGRectGetHeight(materialFrame), 1.0) : 0.0;

    [UIView performWithoutAnimation:^{
      [[self materialView] setFrame:materialFrame];
      [[self fadeView]
          setFrame:CGRectMake(0, -kMTTagChipFadeHeight, CGRectGetWidth(bounds), kMTTagChipFadeHeight)];

      CGFloat scrollY = floor((CGRectGetHeight(bounds) - kMTTagChipHeight) / 2.0);
      [[self scrollView] setFrame:CGRectMake(0, scrollY, CGRectGetWidth(bounds), kMTTagChipHeight)];

      CGFloat x = kMTTagChipHorizontalInset;
      for (MTTagChipButton *button in [self chipButtons]) {
          CGFloat width = [button preferredWidth];
          [button setFrame:CGRectMake(x, 0, width, kMTTagChipHeight)];
          x += width + kMTTagChipSpacing;
      }
      x += kMTTagChipHorizontalInset - kMTTagChipSpacing;
      [[self scrollView]
          setContentSize:CGSizeMake(MAX(x, CGRectGetWidth([[self scrollView] bounds]) + 1), kMTTagChipHeight)];
      if ([self shouldRevealSelectedTagAfterLayout] && [self revealSelectedTagIfPossible]) {
          [self setShouldRevealSelectedTagAfterLayout:NO];
      }
      [[self scrollView] updateEdgeFadeMask];
    }];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [[self materialMaskLayer] setFrame:[[self materialView] bounds]];
    [[self materialMaskLayer] setLocations:@[ @0.0, @(fadeLocation), @1.0 ]];
    [CATransaction commit];
}

@end
