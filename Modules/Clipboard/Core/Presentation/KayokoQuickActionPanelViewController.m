//
//  KayokoQuickActionPanelViewController.m
//  Kayoko
//

#import "KayokoQuickActionPanelViewController.h"

#import "KayokoApplicationMetadataProvider.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoTagColorFormatter.h"

#import <math.h>

static NSUInteger const kKayokoQuickActionPanelColumnCount = 4;
static CGFloat const kKayokoQuickActionPanelHorizontalInset = 16.0;

@interface KayokoQuickActionPanelItemControl : UIControl

@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, assign) CGFloat contentScale;

- (instancetype)initWithTitle:(NSString *)title symbolName:(NSString *)symbolName;

@end


@implementation KayokoQuickActionPanelItemControl

- (instancetype)initWithTitle:(NSString *)title symbolName:(NSString *)symbolName {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _contentScale = 1.0;
        [self setAccessibilityLabel:title];
        [self setAccessibilityTraits:[self accessibilityTraits] | UIAccessibilityTraitButton];

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        [_iconView setContentMode:UIViewContentModeScaleAspectFit];
        [_iconView setTintColor:[UIColor labelColor]];
        NSString *iconName = [symbolName length] > 0 ? symbolName : @"link";
        UIImage *symbolImage = [UIImage systemImageNamed:iconName];
        UIImage *displayImage = symbolImage;
        if (!symbolImage) {
            KayokoApplicationMetadataProvider *metadataProvider = [[KayokoApplicationMetadataProvider alloc] init];
            if ([metadataProvider hasApplicationForBundleIdentifier:iconName]) {
                displayImage = [[metadataProvider iconForBundleIdentifier:iconName]
                    imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            }
        }
        [_iconView setImage:displayImage ?: [UIImage systemImageNamed:@"link"]];
        [[_iconView layer] setMasksToBounds:YES];
        [[_iconView layer] setCornerCurve:kCACornerCurveContinuous];
        [_iconView setUserInteractionEnabled:NO];
        [self addSubview:_iconView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        [_titleLabel setText:title];
        [_titleLabel setTextAlignment:NSTextAlignmentCenter];
        [_titleLabel setTextColor:[UIColor labelColor]];
        [_titleLabel setNumberOfLines:2];
        [_titleLabel setLineBreakMode:NSLineBreakByTruncatingTail];
        [_titleLabel setUserInteractionEnabled:NO];
        [self addSubview:_titleLabel];
    }
    return self;
}

- (void)setContentScale:(CGFloat)contentScale {
    _contentScale = contentScale;
    [[self titleLabel] setFont:[UIFont systemFontOfSize:14.0 * contentScale weight:UIFontWeightRegular]];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat scale = [self contentScale];
    CGFloat iconSide = 34.0 * scale;
    [[self iconView] layer].cornerRadius = iconSide * 0.22;
    CGFloat labelHeight = 38.0 * scale;
    CGFloat spacing = 8.0 * scale;
    CGFloat totalHeight = iconSide + spacing + labelHeight;
    CGFloat originY = floor((CGRectGetHeight([self bounds]) - totalHeight) * 0.5);
    [[self iconView] setFrame:CGRectMake(floor((CGRectGetWidth([self bounds]) - iconSide) * 0.5),
                                         originY,
                                         iconSide,
                                         iconSide)];
    [[self titleLabel] setFrame:CGRectMake(3.0,
                                           CGRectGetMaxY([[self iconView] frame]) + spacing,
                                           MAX(0.0, CGRectGetWidth([self bounds]) - 6.0),
                                           labelHeight)];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.10 animations:^{
      [self setAlpha:highlighted ? 0.45 : 1.0];
      [self setTransform:highlighted ? CGAffineTransformMakeScale(0.94, 0.94) : CGAffineTransformIdentity];
    }];
}

@end


@interface KayokoQuickActionPanelViewController () <UIGestureRecognizerDelegate>

@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *actions;
@property(nonatomic, copy) KayokoQuickActionPanelSelectionHandler selectionHandler;
@property(nonatomic, weak, nullable) UIView *anchorView;
@property(nonatomic, assign) KayokoQuickActionPanelPlacement placement;
@property(nonatomic, strong) UIVisualEffectView *panelView;
@property(nonatomic, strong) UIView *panelTintView;
@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, copy) NSArray<KayokoQuickActionPanelItemControl *> *itemControls;
@property(nonatomic, assign) CGFloat panelScale;

@end


@implementation KayokoQuickActionPanelViewController

- (instancetype)initWithActions:(NSArray<NSDictionary<NSString *, id> *> *)actions
              anchoringAboveView:(UIView * _Nullable)anchorView
                       placement:(KayokoQuickActionPanelPlacement)placement
                selectionHandler:(KayokoQuickActionPanelSelectionHandler)selectionHandler {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _actions = [actions copy];
        _selectionHandler = [selectionHandler copy];
        _anchorView = anchorView;
        _placement = placement;
        _panelScale = [self.class storedPanelScale];
        [self setModalPresentationStyle:UIModalPresentationOverFullScreen];
        [self setModalTransitionStyle:UIModalTransitionStyleCrossDissolve];
    }
    return self;
}

+ (UIColor *)storedPanelColor {
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [preferences registerDefaults:@{
        kKayokoPreferenceKeyFloatingPanelColor : kKayokoPreferenceKeyFloatingPanelColorDefaultValue,
    }];
    return [KayokoTagColorFormatter colorFromHexColor:
        [preferences stringForKey:kKayokoPreferenceKeyFloatingPanelColor]];
}

+ (CGFloat)storedPanelScale {
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [preferences registerDefaults:@{
        kKayokoPreferenceKeyFloatingPanelScale : @(kKayokoPreferenceKeyFloatingPanelScaleDefaultValue),
    }];
    CGFloat scale = [preferences doubleForKey:kKayokoPreferenceKeyFloatingPanelScale];
    if (!isfinite(scale)) {
        scale = kKayokoPreferenceKeyFloatingPanelScaleDefaultValue;
    }
    return MIN(MAX(scale, kKayokoPreferenceKeyFloatingPanelScaleMinimumValue),
               kKayokoPreferenceKeyFloatingPanelScaleMaximumValue);
}

- (void)loadView {
    UIView *rootView = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [rootView setBackgroundColor:[UIColor colorWithWhite:0.0 alpha:0.08]];
    [rootView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [rootView setAccessibilityViewIsModal:YES];
    [self setView:rootView];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UITapGestureRecognizer *dismissRecognizer = [[UITapGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(handleDismissTap:)];
    [dismissRecognizer setDelegate:self];
    [dismissRecognizer setCancelsTouchesInView:NO];
    [[self view] addGestureRecognizer:dismissRecognizer];

    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    _panelView = [[UIVisualEffectView alloc] initWithEffect:effect];
    [[_panelView layer] setCornerRadius:24.0];
    [[_panelView layer] setCornerCurve:kCACornerCurveContinuous];
    [[_panelView layer] setShadowColor:[[UIColor blackColor] CGColor]];
    [[_panelView layer] setShadowOpacity:0.20];
    [[_panelView layer] setShadowRadius:18.0];
    [[_panelView layer] setShadowOffset:CGSizeMake(0.0, 7.0)];
    [_panelView setClipsToBounds:YES];
    [[self view] addSubview:_panelView];

    _panelTintView = [[UIView alloc] initWithFrame:CGRectZero];
    [_panelTintView setBackgroundColor:[[self.class storedPanelColor] colorWithAlphaComponent:0.20]];
    [_panelTintView setUserInteractionEnabled:NO];
    [[_panelView contentView] addSubview:_panelTintView];

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    [_scrollView setAlwaysBounceVertical:NO];
    [_scrollView setShowsVerticalScrollIndicator:NO];
    [_scrollView setClipsToBounds:YES];
    [[_panelView contentView] addSubview:_scrollView];

    NSMutableArray<KayokoQuickActionPanelItemControl *> *controls = [[NSMutableArray alloc] init];
    [[self actions] enumerateObjectsUsingBlock:^(NSDictionary<NSString *, id> *action,
                                                NSUInteger index,
                                                __unused BOOL *stop) {
      NSString *title = [action[@"title"] isKindOfClass:[NSString class]] ? action[@"title"] : @"";
      NSString *icon = [action[@"icon"] isKindOfClass:[NSString class]] ? action[@"icon"] : @"";
      KayokoQuickActionPanelItemControl *control = [[KayokoQuickActionPanelItemControl alloc]
          initWithTitle:title
             symbolName:icon];
      [control setTag:(NSInteger)index];
      [control setContentScale:[self panelScale]];
      [control addTarget:self action:@selector(handleItemPressed:) forControlEvents:UIControlEventTouchUpInside];
      [[self scrollView] addSubview:control];
      [controls addObject:control];
    }];
    [self setItemControls:[controls copy]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, [[self itemControls] firstObject]);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect bounds = [[self view] bounds];
    UIEdgeInsets safeAreaInsets = [[self view] safeAreaInsets];
    CGFloat availableWidth = MAX(0.0, CGRectGetWidth(bounds) - kKayokoQuickActionPanelHorizontalInset * 2.0);
    // The size preference deliberately never participates in this calculation.
    // The panel remains screen-width while only its internal content and height scale.
    CGFloat panelWidth = availableWidth;
    CGFloat scale = [self panelScale];
    CGFloat contentInset = 12.0 * scale;
    CGFloat itemHeight = 94.0 * scale;
    NSUInteger rowCount = (([[self itemControls] count] + kKayokoQuickActionPanelColumnCount - 1) /
                           kKayokoQuickActionPanelColumnCount);
    CGFloat desiredContentHeight = contentInset * 2.0 + itemHeight * rowCount;
    CGFloat availableHeight = MAX(1.0,
                                  CGRectGetHeight(bounds) - safeAreaInsets.top - safeAreaInsets.bottom - 24.0);
    CGFloat minimumPanelY = safeAreaInsets.top + 12.0;
    CGFloat panelHeight = MIN(desiredContentHeight, availableHeight * 0.72);
    CGFloat panelX = floor((CGRectGetWidth(bounds) - panelWidth) * 0.5);
    CGFloat panelY = 0.0;
    if ([self placement] == KayokoQuickActionPanelPlacementScreenUpperCenter) {
        CGFloat maximumPanelY = CGRectGetHeight(bounds) - safeAreaInsets.bottom - 12.0 - panelHeight;
        // Centered halfway between the screen middle and the top edge (a quarter
        // of the screen height down from the top).
        panelY = floor(CGRectGetHeight(bounds) * 0.25 - panelHeight * 0.5);
        panelY = MIN(MAX(panelY, minimumPanelY), MAX(minimumPanelY, maximumPanelY));
    } else {
        CGFloat preferredPanelBottom = CGRectGetHeight(bounds) - safeAreaInsets.bottom - 24.0;
        UIView *anchorView = [self anchorView];
        UIWindow *anchorWindow = [anchorView window];
        if (anchorView && anchorWindow) {
            CGRect anchorFrameInWindow = [anchorView convertRect:[anchorView bounds] toView:anchorWindow];
            CGFloat anchorTop = CGRectGetMinY(anchorFrameInWindow);
            if (isfinite(anchorTop) && anchorTop > minimumPanelY + 60.0) {
                preferredPanelBottom = MIN(preferredPanelBottom, anchorTop - 12.0);
            }
        }
        CGFloat heightAboveOperationView = MAX(1.0, preferredPanelBottom - minimumPanelY);
        panelHeight = MIN(panelHeight, heightAboveOperationView);
        panelY = MAX(minimumPanelY, preferredPanelBottom - panelHeight);
    }

    [[self panelView] setFrame:CGRectMake(panelX, panelY, panelWidth, panelHeight)];
    [[self panelView] layer].cornerRadius = 24.0 * scale;
    [[self panelTintView] setFrame:[[self panelView] bounds]];
    [[self scrollView] setFrame:[[self panelView] bounds]];
    [[self scrollView] setContentSize:CGSizeMake(panelWidth, desiredContentHeight)];
    [[self scrollView] setScrollEnabled:desiredContentHeight > panelHeight + 0.5];

    CGFloat contentWidth = MAX(0.0, panelWidth - contentInset * 2.0);
    CGFloat itemWidth = contentWidth / kKayokoQuickActionPanelColumnCount;
    [[self itemControls] enumerateObjectsUsingBlock:^(KayokoQuickActionPanelItemControl *control,
                                                      NSUInteger index,
                                                      __unused BOOL *stop) {
      NSUInteger row = index / kKayokoQuickActionPanelColumnCount;
      NSUInteger column = index % kKayokoQuickActionPanelColumnCount;
      [control setFrame:CGRectMake(contentInset + column * itemWidth,
                                   contentInset + row * itemHeight,
                                   itemWidth,
                                   itemHeight)];
    }];
}

- (void)handleDismissTap:(UITapGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer state] == UIGestureRecognizerStateEnded) {
        dispatch_block_t dismissalHandler = [self dismissalHandler];
        [self dismissViewControllerAnimated:YES completion:dismissalHandler];
    }
}

- (void)handleItemPressed:(KayokoQuickActionPanelItemControl *)sender {
    NSUInteger index = (NSUInteger)[sender tag];
    if (index >= [[self actions] count]) {
        return;
    }
    NSDictionary<NSString *, id> *action = [self actions][index];
    KayokoQuickActionPanelSelectionHandler handler = [self selectionHandler];
    [self dismissViewControllerAnimated:YES completion:^{
      if (handler) {
          handler(action);
      }
    }];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    (void)gestureRecognizer;
    UIView *touchedView = [touch view];
    while (touchedView && touchedView != [self view]) {
        if ([touchedView isKindOfClass:[UIControl class]]) {
            return NO;
        }
        touchedView = [touchedView superview];
    }
    return YES;
}

@end
