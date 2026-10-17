//
//  MTWordSelectionView.m
//  Mt
//

#import "MTWordSelectionView.h"
#import "MTEdgeFadingScrollView.h"
#import "MTHeaderView.h"
#import "MTMainView.h"
#import "MTPasteboardManager.h"
#import "MTWordSelectionTokenizer.h"
#import "MTWordTokenView.h"

static CGFloat const kMTWordSelectionHorizontalInset = 20;
static CGFloat const kMTWordSelectionVerticalFadeHeight = 20;
static CGFloat const kMTWordSelectionTopInset = 8;
static CGFloat const kMTWordSelectionTokenSpacing = 2;
static CGFloat const kMTWordSelectionLineSpacing = 9;
static CGFloat const kMTWordSelectionTokenHeight = 34;
static CGFloat const kMTWordSelectionTokenHorizontalInset = 3;
static CGFloat const kMTWordSelectionTokenCornerRadius = 4;
static CGFloat const kMTWordSelectionTokenBorderWidth = 0.5;
static CGFloat const kMTWordSelectionPreviewHeight = 92;
static CGFloat const kMTWordSelectionPreviewCornerRadius = 12;
static CGFloat const kMTWordSelectionPreviewSpacing = 10;

NS_ASSUME_NONNULL_BEGIN

@interface MTWordSelectionView () <UIGestureRecognizerDelegate, UIScrollViewDelegate>
#pragma mark - Views

@property(nonatomic, strong) MTEdgeFadingScrollView *scrollView;
@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong) UITextView *selectionPreviewTextView;
@property(nonatomic, strong, readwrite) MTHeaderView *headerView;
@property(nonatomic, strong, readwrite) UIView *transitionContentView;

#pragma mark - Tokens

@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *tokens;
@property(nonatomic, strong) NSMutableArray<MTWordTokenView *> *tokenButtons;
@property(nonatomic, strong) NSMutableIndexSet *selectedTokenIndexes;
@property(nonatomic, strong) NSMutableIndexSet *selectionGestureOriginalIndexes;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *selectedTokenOrderValues;
@property(nonatomic, copy, nullable) NSString *originalText;

#pragma mark - Gestures

@property(nonatomic, weak) UIPanGestureRecognizer *selectionGestureRecognizer;

#pragma mark - State

@property(nonatomic, assign, readwrite) BOOL hasCustomSelection;
@property(nonatomic, assign) NSUInteger selectionAnchorIndex;
@property(nonatomic, assign) BOOL selectionGestureSelectsTokens;
@property(nonatomic, assign) NSUInteger nextSelectionOrderValue;
@end

NS_ASSUME_NONNULL_END

@implementation MTWordSelectionView

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self setClipsToBounds:YES];
        [self setTokens:[[NSMutableArray alloc] init]];
        [self setTokenButtons:[[NSMutableArray alloc] init]];
        [self setSelectedTokenIndexes:[[NSMutableIndexSet alloc] init]];
        [self setSelectionGestureOriginalIndexes:[[NSMutableIndexSet alloc] init]];
        [self setSelectedTokenOrderValues:[[NSMutableDictionary alloc] init]];
        [self setSelectionAnchorIndex:NSNotFound];

        [self setHeaderView:[[MTHeaderView alloc] initWithTitle:@""]];
        [self addSubview:[self headerView]];

        [[self headerView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[ [[[self headerView] heightAnchor]
                                                    constraintEqualToConstant:[MTHeaderView preferredHeight]] ]];

        [self setTransitionContentView:[[UIView alloc] init]];
        [self insertSubview:[self transitionContentView] belowSubview:[self headerView]];
        [[self transitionContentView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self transitionContentView] topAnchor] constraintEqualToAnchor:[self topAnchor]],
            [[[self transitionContentView] leadingAnchor] constraintEqualToAnchor:[self leadingAnchor]],
            [[[self transitionContentView] trailingAnchor] constraintEqualToAnchor:[self trailingAnchor]],
            [[[self transitionContentView] bottomAnchor] constraintEqualToAnchor:[self bottomAnchor]]
        ]];

        [self setSelectionPreviewTextView:[[UITextView alloc] init]];
        [[self selectionPreviewTextView] setEditable:NO];
        [[self selectionPreviewTextView] setSelectable:NO];
        [[self selectionPreviewTextView] setScrollEnabled:YES];
        [[self selectionPreviewTextView] setAlwaysBounceVertical:NO];
        [[self selectionPreviewTextView] setAutomaticallyAdjustsScrollIndicatorInsets:NO];
        [[self selectionPreviewTextView] setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentNever];
        [[self selectionPreviewTextView] setFont:[UIFont systemFontOfSize:16 weight:UIFontWeightRegular]];
        [[self selectionPreviewTextView] setTextContainerInset:UIEdgeInsetsMake(12, 12, 12, 12)];
        [[[self selectionPreviewTextView] textContainer] setLineFragmentPadding:0];
        [[[self selectionPreviewTextView] layer] setCornerRadius:kMTWordSelectionPreviewCornerRadius];
        [[[self selectionPreviewTextView] layer] setBorderWidth:1.0 / [UIScreen mainScreen].scale];
        [[self transitionContentView] addSubview:[self selectionPreviewTextView]];

        [[self selectionPreviewTextView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self selectionPreviewTextView] topAnchor] constraintEqualToAnchor:[[self headerView] bottomAnchor]
                                                                        constant:kMTHeaderContentSpacing],
            [[[self selectionPreviewTextView] leadingAnchor]
                constraintEqualToAnchor:[[self safeAreaLayoutGuide] leadingAnchor]
                               constant:kMTWordSelectionHorizontalInset],
            [[[self selectionPreviewTextView] trailingAnchor]
                constraintEqualToAnchor:[[self safeAreaLayoutGuide] trailingAnchor]
                               constant:-kMTWordSelectionHorizontalInset],
            [[[self selectionPreviewTextView] heightAnchor] constraintEqualToConstant:kMTWordSelectionPreviewHeight]
        ]];

        [self setScrollView:[[MTEdgeFadingScrollView alloc] init]];
        [[self scrollView] setEdgeFadeAxis:MTEdgeFadeAxisVertical];
        [[self scrollView] setEdgeFadeWidth:kMTWordSelectionVerticalFadeHeight];
        [[self scrollView] setEdgeFadeEnabled:YES];
        [[self scrollView] setAlwaysBounceVertical:NO];
        [[self scrollView] setAutomaticallyAdjustsScrollIndicatorInsets:NO];
        [[self scrollView] setBackgroundColor:[UIColor clearColor]];
        [[self scrollView] setDelegate:self];
        [[self transitionContentView] addSubview:[self scrollView]];

        [[self scrollView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self scrollView] topAnchor] constraintEqualToAnchor:[[self selectionPreviewTextView] bottomAnchor]
                                                          constant:kMTWordSelectionPreviewSpacing],
            [[[self scrollView] leadingAnchor] constraintEqualToAnchor:[[self safeAreaLayoutGuide] leadingAnchor]],
            [[[self scrollView] trailingAnchor] constraintEqualToAnchor:[[self safeAreaLayoutGuide] trailingAnchor]],
            [[[self scrollView] bottomAnchor] constraintEqualToAnchor:[self bottomAnchor]]
        ]];

        [self setContentView:[[UIView alloc] init]];
        [[self scrollView] addSubview:[self contentView]];

        UITapGestureRecognizer *tapGesture =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
        [tapGesture setDelegate:self];
        [[self contentView] addGestureRecognizer:tapGesture];

        UIPanGestureRecognizer *selectionGesture =
            [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSelectionGesture:)];
        [selectionGesture setDelegate:self];
        [self setSelectionGestureRecognizer:selectionGesture];
        [[self contentView] addGestureRecognizer:selectionGesture];

        UILongPressGestureRecognizer *tokenizationGesture =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleTokenizationGesture:)];
        [tokenizationGesture setDelegate:self];
        [tokenizationGesture setMinimumPressDuration:0.5];
        [tokenizationGesture setAllowableMovement:12.0];
        [[self contentView] addGestureRecognizer:tokenizationGesture];
        [selectionGesture requireGestureRecognizerToFail:tokenizationGesture];

        [self updateSelectionPreviewStyle];
        [self updateSelectionPreview];
    }

    return self;
}

#pragma mark - Content

- (void)setText:(NSString *)text {
    [self reset];
    [self setOriginalText:[text copy]];

    NSArray<NSDictionary<NSString *, id> *> *tokens = [MTWordSelectionTokenizer tokensForText:text];
    [[self tokens] addObjectsFromArray:tokens];

    [self rebuildTokenButtons];
    [self updateButtonStyles];
    [self notifySelectionChanged];
    [self setNeedsLayout];
}

- (void)rebuildTokenButtons {
    for (MTWordTokenView *button in [self tokenButtons]) {
        [button removeFromSuperview];
    }
    [[self tokenButtons] removeAllObjects];

    for (NSUInteger index = 0; index < [[self tokens] count]; index++) {
        MTWordTokenView *button = [[MTWordTokenView alloc] initWithFrame:CGRectZero];
        NSDictionary<NSString *, id> *token = [self tokens][index];
        [button setTag:index];
        [button setTitle:token[@"text"] forState:UIControlStateNormal];
        [[button titleLabel] setFont:[UIFont systemFontOfSize:16 weight:UIFontWeightRegular]];
        [[button titleLabel] setLineBreakMode:NSLineBreakByTruncatingMiddle];
        [button setMtContentInsets:UIEdgeInsetsMake(0, kMTWordSelectionTokenHorizontalInset, 0,
                                                        kMTWordSelectionTokenHorizontalInset)];
        [button setUserInteractionEnabled:NO];
        [[button layer] setCornerRadius:kMTWordSelectionTokenCornerRadius];
        [[button layer] setBorderWidth:kMTWordSelectionTokenBorderWidth];
        [[self contentView] addSubview:button];
        [[self tokenButtons] addObject:button];
    }
}

- (void)reset {
    for (MTWordTokenView *button in [self tokenButtons]) {
        [button removeFromSuperview];
    }

    [[self tokenButtons] removeAllObjects];
    [[self tokens] removeAllObjects];
    [[self selectedTokenIndexes] removeAllIndexes];
    [[self selectionGestureOriginalIndexes] removeAllIndexes];
    [[self selectedTokenOrderValues] removeAllObjects];
    [self setOriginalText:nil];
    [self setHasCustomSelection:NO];
    [self setSelectionAnchorIndex:NSNotFound];
    [self setNextSelectionOrderValue:0];
    [[self scrollView] setContentOffset:CGPointZero];
    [[self scrollView] setContentSize:CGSizeZero];
    [self updateSelectionPreview];
}

- (void)setUsesSelectionOrderForSelectedText:(BOOL)usesSelectionOrderForSelectedText {
    if (_usesSelectionOrderForSelectedText == usesSelectionOrderForSelectedText) {
        return;
    }

    _usesSelectionOrderForSelectedText = usesSelectionOrderForSelectedText;
    [self updateSelectionPreview];
}

- (void)scrollToTopAnimated:(BOOL)animated {
    CGPoint contentOffset = [[self scrollView] contentOffset];
    contentOffset.y = -[[self scrollView] adjustedContentInset].top;
    [[self scrollView] setContentOffset:contentOffset animated:animated];
}

- (void)setKeyboardBottomInset:(CGFloat)keyboardBottomInset {
    keyboardBottomInset = MAX(keyboardBottomInset, 0);
    if (_keyboardBottomInset == keyboardBottomInset) {
        return;
    }

    _keyboardBottomInset = keyboardBottomInset;
    [self updateScrollInsets];
    [self setNeedsLayout];
}

- (void)requireSelectionGestureRecognizerToFailGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer) {
        [[self selectionGestureRecognizer] requireGestureRecognizerToFail:gestureRecognizer];
    }
}

- (CGFloat)safeAreaBottomInsetForScrollContent {
    UIView *view = self;
    while (view) {
        if ([view isKindOfClass:[MTMainView class]]) {
            return [(MTMainView *)view safeAreaBottomInsetForContentView:self];
        }
        view = [view superview];
    }

    return MAX([self safeAreaInsets].bottom, 0);
}

- (CGFloat)scrollBottomInset {
    if ([self keyboardBottomInset] > 0) {
        return [self keyboardBottomInset];
    }
    return [self safeAreaBottomInsetForScrollContent];
}

- (void)updateScrollInsets {
    CGFloat bottomInset = [self scrollBottomInset];

    UIEdgeInsets contentInset = [[self scrollView] contentInset];
    contentInset.bottom = bottomInset;
    [[self scrollView] setContentInset:contentInset];

    UIEdgeInsets indicatorInsets = UIEdgeInsetsMake(0, 0, bottomInset, 0);
    [[self scrollView] setVerticalScrollIndicatorInsets:indicatorInsets];
    [[self scrollView] setEdgeFadeInsets:UIEdgeInsetsMake(0, 0, [self keyboardBottomInset], 0)];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat scrollWidth = CGRectGetWidth([[self scrollView] bounds]);
    CGFloat scrollHeight = CGRectGetHeight([[self scrollView] bounds]);
    CGFloat availableWidth = MAX(scrollWidth - kMTWordSelectionHorizontalInset * 2, 1);
    CGFloat x = kMTWordSelectionHorizontalInset;
    CGFloat y = kMTWordSelectionTopInset;

    for (NSUInteger index = 0; index < [[self tokenButtons] count]; index++) {
        MTWordTokenView *button = [self tokenButtons][index];
        CGSize size = [button sizeThatFits:CGSizeMake(availableWidth, kMTWordSelectionTokenHeight)];
        CGFloat buttonWidth = MIN(MAX(ceil(size.width), kMTWordSelectionTokenHeight), availableWidth);

        if (x > kMTWordSelectionHorizontalInset &&
            x + buttonWidth > kMTWordSelectionHorizontalInset + availableWidth) {
            x = kMTWordSelectionHorizontalInset;
            y += kMTWordSelectionTokenHeight + kMTWordSelectionLineSpacing;
        }

        [button setFrame:CGRectMake(x, y, buttonWidth, kMTWordSelectionTokenHeight)];
        x += buttonWidth + kMTWordSelectionTokenSpacing;

        if ([self tokens][index][@"lineBreakAfter"] && index + 1 < [[self tokenButtons] count]) {
            x = kMTWordSelectionHorizontalInset;
            y += kMTWordSelectionTokenHeight + kMTWordSelectionLineSpacing;
        }
    }

    CGFloat contentHeight = [[self tokenButtons] count] > 0
                                ? y + kMTWordSelectionTokenHeight + kMTWordSelectionLineSpacing
                                : kMTWordSelectionTopInset;
    [[self contentView] setFrame:CGRectMake(0, 0, scrollWidth, contentHeight)];
    [[self scrollView] setContentSize:CGSizeMake(scrollWidth, contentHeight)];

    BOOL scrollable = contentHeight > scrollHeight + 0.5;
    [self updateScrollInsets];
    scrollable = contentHeight + [[self scrollView] contentInset].bottom > scrollHeight + 0.5;
    [[self scrollView] setBounces:scrollable];
    [[self scrollView] setAlwaysBounceVertical:scrollable];
}

- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    [self updateScrollInsets];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateSelectionPreviewStyle];
    [self updateButtonStyles];
}
#pragma clang diagnostic pop

#pragma mark - Gestures

- (void)handleTapGesture:(UITapGestureRecognizer *)gesture {
    NSUInteger tokenIndex = [self tokenIndexAtPoint:[gesture locationInView:[self contentView]]];
    if (tokenIndex != NSNotFound) {
        [self toggleTokenAtIndex:tokenIndex];
    }
}

- (void)handleSelectionGesture:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:[self contentView]];
    NSUInteger tokenIndex = [self tokenIndexForSelectionLocation:location];

    if ([gesture state] == UIGestureRecognizerStateBegan) {
        if (tokenIndex == NSNotFound) {
            return;
        }

        [self setSelectionAnchorIndex:tokenIndex];
        [self setSelectionGestureSelectsTokens:![[self selectedTokenIndexes] containsIndex:tokenIndex]];
        [self setSelectionGestureOriginalIndexes:[[self selectedTokenIndexes] mutableCopy]];
        [self setHasCustomSelection:YES];
        [[self scrollView] setScrollEnabled:NO];
        return;
    }

    if ([gesture state] == UIGestureRecognizerStateChanged && tokenIndex != NSNotFound) {
        [self applySelectionGestureThroughIndex:tokenIndex];
    }

    if ([gesture state] == UIGestureRecognizerStateEnded || [gesture state] == UIGestureRecognizerStateCancelled ||
        [gesture state] == UIGestureRecognizerStateFailed) {
        [[self selectionGestureOriginalIndexes] removeAllIndexes];
        [self setSelectionAnchorIndex:NSNotFound];
        [[self scrollView] setScrollEnabled:YES];
    }
}

- (void)handleTokenizationGesture:(UILongPressGestureRecognizer *)gesture {
    if ([gesture state] != UIGestureRecognizerStateBegan) {
        return;
    }

    NSUInteger tokenIndex = [self tokenIndexAtPoint:[gesture locationInView:[self contentView]]];
    if (tokenIndex == NSNotFound || tokenIndex >= [[self tokens] count]) {
        return;
    }

    NSDictionary<NSString *, id> *token = [self tokens][tokenIndex];
    NSString *tokenText = token[@"text"];
    NSArray<NSDictionary<NSString *, id> *> *characterTokens =
        [MTWordSelectionTokenizer characterTokensForText:tokenText];
    if ([characterTokens count] <= 1) {
        return;
    }

    NSRange originalRange = [token[@"range"] rangeValue];
    NSMutableArray<NSDictionary<NSString *, id> *> *replacementTokens =
        [[NSMutableArray alloc] initWithCapacity:[characterTokens count]];
    for (NSUInteger index = 0; index < [characterTokens count]; index++) {
        NSDictionary<NSString *, id> *characterToken = characterTokens[index];
        NSMutableDictionary<NSString *, id> *replacementToken = [characterToken mutableCopy];
        NSRange characterRange = [characterToken[@"range"] rangeValue];
        replacementToken[@"range"] = [NSValue valueWithRange:NSMakeRange(originalRange.location + characterRange.location,
                                                                          characterRange.length)];
        if (index + 1 == [characterTokens count] && token[@"lineBreakAfter"]) {
            replacementToken[@"lineBreakAfter"] = @YES;
        }
        [replacementTokens addObject:replacementToken];
    }

    NSIndexSet *selectedIndexes = [[self selectedTokenIndexes] copy];
    NSMutableArray<NSDictionary<NSString *, id> *> *updatedTokens = [[NSMutableArray alloc] init];
    NSMutableIndexSet *updatedSelectedIndexes = [[NSMutableIndexSet alloc] init];
    NSUInteger updatedIndex = 0;
    for (NSUInteger index = 0; index < [[self tokens] count]; index++) {
        NSArray<NSDictionary<NSString *, id> *> *tokensToAdd = index == tokenIndex ? replacementTokens : @[ [self tokens][index] ];
        [updatedTokens addObjectsFromArray:tokensToAdd];
        if ([selectedIndexes containsIndex:index]) {
            [updatedSelectedIndexes addIndexesInRange:NSMakeRange(updatedIndex, [tokensToAdd count])];
        }
        updatedIndex += [tokensToAdd count];
    }

    [[self tokens] removeAllObjects];
    [[self tokens] addObjectsFromArray:updatedTokens];
    [[self selectedTokenIndexes] removeAllIndexes];
    [[self selectedTokenIndexes] addIndexes:updatedSelectedIndexes];
    [[self selectedTokenOrderValues] removeAllObjects];
    __block NSUInteger orderValue = 0;
    [[self selectedTokenIndexes] enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
      [self selectedTokenOrderValues][@(index)] = @(orderValue++);
    }];
    [self setHasCustomSelection:YES];
    [self rebuildTokenButtons];
    [self updateButtonStyles];
    [self notifySelectionChanged];
    [self setNeedsLayout];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    CGPoint location = [gestureRecognizer locationInView:[self contentView]];

    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        return [self tokenIndexAtPoint:location] != NSNotFound;
    }

    if ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return [self tokenIndexAtPoint:location] != NSNotFound;
    }

    if (![gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        return YES;
    }

    if ([self tokenIndexForSelectionLocation:location] == NSNotFound) {
        return NO;
    }

    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
    if (fabs(velocity.y) > fabs(velocity.x) * 1.5) {
        return NO;
    }

    return YES;
}

#pragma mark - Token Selection

- (NSUInteger)tokenIndexAtPoint:(CGPoint)point {
    for (MTWordTokenView *button in [self tokenButtons]) {
        if (CGRectContainsPoint([button frame], point)) {
            return [button tag];
        }
    }

    return NSNotFound;
}

- (NSUInteger)tokenIndexForSelectionLocation:(CGPoint)point {
    for (MTWordTokenView *button in [self tokenButtons]) {
        CGRect frame =
            CGRectInset([button frame], -kMTWordSelectionTokenSpacing / 2, -kMTWordSelectionLineSpacing / 2);
        if (CGRectContainsPoint(frame, point)) {
            return [button tag];
        }
    }

    return NSNotFound;
}

- (void)toggleTokenAtIndex:(NSUInteger)index {
    [self setHasCustomSelection:YES];

    NSMutableIndexSet *updatedIndexes = [[self selectedTokenIndexes] mutableCopy];
    if ([[self selectedTokenIndexes] containsIndex:index]) {
        [updatedIndexes removeIndex:index];
    } else {
        [updatedIndexes addIndex:index];
    }

    [self applySelectedTokenIndexes:updatedIndexes];
    [self updateButtonStyles];
    [self notifySelectionChanged];
}

- (BOOL)selectAllTokens {
    NSUInteger tokenCount = [[self tokens] count];
    if (tokenCount == 0) {
        return NO;
    }

    [self setHasCustomSelection:YES];
    NSIndexSet *allTokenIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, tokenCount)];
    if (![self applySelectedTokenIndexes:allTokenIndexes]) {
        return NO;
    }

    [self updateButtonStyles];
    [self notifySelectionChanged];
    return YES;
}

- (BOOL)clearSelectedTokens {
    if (![[self selectedTokenIndexes] count]) {
        return NO;
    }

    [self setHasCustomSelection:YES];
    if (![self applySelectedTokenIndexes:[NSIndexSet indexSet]]) {
        return NO;
    }

    [self updateButtonStyles];
    [self notifySelectionChanged];
    return YES;
}

- (void)applySelectionGestureThroughIndex:(NSUInteger)index {
    if ([self selectionAnchorIndex] == NSNotFound) {
        return;
    }

    NSMutableIndexSet *updatedIndexes = [[self selectionGestureOriginalIndexes] mutableCopy];

    NSUInteger lowerBound = MIN([self selectionAnchorIndex], index);
    NSUInteger upperBound = MAX([self selectionAnchorIndex], index);
    NSRange range = NSMakeRange(lowerBound, upperBound - lowerBound + 1);

    if ([self selectionGestureSelectsTokens]) {
        [updatedIndexes addIndexesInRange:range];
    } else {
        [updatedIndexes removeIndexesInRange:range];
    }

    if (![self applySelectedTokenIndexes:updatedIndexes]) {
        return;
    }

    [self updateButtonStyles];
    [self notifySelectionChanged];
}

- (BOOL)applySelectedTokenIndexes:(NSIndexSet *)updatedIndexes {
    if ([[self selectedTokenIndexes] isEqualToIndexSet:updatedIndexes]) {
        return NO;
    }

    NSMutableIndexSet *removedIndexes = [[self selectedTokenIndexes] mutableCopy];
    [removedIndexes removeIndexes:updatedIndexes];
    [removedIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
      [[self selectedTokenOrderValues] removeObjectForKey:@(index)];
    }];

    NSMutableIndexSet *addedIndexes = [updatedIndexes mutableCopy];
    [addedIndexes removeIndexes:[self selectedTokenIndexes]];
    [addedIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
      [self selectedTokenOrderValues][@(index)] = @([self nextSelectionOrderValue]);
      [self setNextSelectionOrderValue:[self nextSelectionOrderValue] + 1];
    }];

    [[self selectedTokenIndexes] removeAllIndexes];
    [[self selectedTokenIndexes] addIndexes:updatedIndexes];
    return YES;
}

#pragma mark - Styling

- (void)updateSelectionPreviewStyle {
    [[self selectionPreviewTextView] setBackgroundColor:[UIColor secondarySystemBackgroundColor]];
    [[[self selectionPreviewTextView] layer] setBorderColor:[[UIColor separatorColor] CGColor]];
}

- (void)updateSelectionPreview {
    BOOL hasSelectedText = [self hasSelectedText];
    NSString *text = hasSelectedText
                         ? [self selectedText]
                         : [[MTPasteboardManager localizationBundle] localizedStringForKey:@"Swipe to select text"
                                                                                          value:nil
                                                                                          table:@"Tweak"];
    [[self selectionPreviewTextView] setText:text ?: @""];
    [[self selectionPreviewTextView]
        setTextColor:hasSelectedText ? [UIColor labelColor] : [UIColor tertiaryLabelColor]];
    [[self selectionPreviewTextView] setContentOffset:CGPointZero animated:NO];
    [[self selectionPreviewTextView]
        setAccessibilityLabel:[[MTPasteboardManager localizationBundle] localizedStringForKey:@"Selected Text"
                                                                                             value:nil
                                                                                             table:@"Tweak"]];
    [[self selectionPreviewTextView] setAccessibilityValue:hasSelectedText ? text : nil];
}

- (void)notifySelectionChanged {
    [self updateSelectionPreview];
    if ([self selectionChangedHandler]) {
        [self selectionChangedHandler]();
    }
}

- (void)updateButtonStyles {
    UIColor *selectedTextColor = [MTWordSelectionView dynamicColorWithLightWhite:0
                                                                               alpha:0.88
                                                                           darkWhite:1
                                                                               alpha:0.92];
    UIColor *normalTextColor = [MTWordSelectionView dynamicColorWithLightWhite:0 alpha:0.58 darkWhite:1 alpha:0.62];
    UIColor *selectedBackgroundColor = [MTWordSelectionView dynamicColorWithLightWhite:0
                                                                                     alpha:0.08
                                                                                 darkWhite:1
                                                                                     alpha:0.12];
    UIColor *normalBackgroundColor = [MTWordSelectionView dynamicColorWithLightWhite:1
                                                                                   alpha:0.08
                                                                               darkWhite:1
                                                                                   alpha:0.035];
    UIColor *selectedBorderColor = [MTWordSelectionView dynamicColorWithLightWhite:0
                                                                                 alpha:0.20
                                                                             darkWhite:1
                                                                                 alpha:0.24];
    UIColor *normalBorderColor = [MTWordSelectionView dynamicColorWithLightWhite:0
                                                                               alpha:0.08
                                                                           darkWhite:1
                                                                               alpha:0.10];

    for (NSUInteger index = 0; index < [[self tokenButtons] count]; index++) {
        MTWordTokenView *button = [self tokenButtons][index];
        BOOL selected = [[self selectedTokenIndexes] containsIndex:index];
        [[button layer] setBorderWidth:kMTWordSelectionTokenBorderWidth];
        UIColor *textColor = selected ? selectedTextColor : normalTextColor;
        UIColor *backgroundColor = selected ? selectedBackgroundColor : normalBackgroundColor;
        [button setTitleColor:textColor forState:UIControlStateNormal];
        [button setBackgroundColor:backgroundColor];
        [[button layer] setBorderColor:(selected ? selectedBorderColor : normalBorderColor).CGColor];
    }
}

+ (UIColor *)dynamicColorWithLightWhite:(CGFloat)lightWhite
                                  alpha:(CGFloat)lightAlpha
                              darkWhite:(CGFloat)darkWhite
                                  alpha:(CGFloat)darkAlpha {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
      BOOL dark = [traitCollection userInterfaceStyle] == UIUserInterfaceStyleDark;
      return [UIColor colorWithWhite:(dark ? darkWhite : lightWhite) alpha:(dark ? darkAlpha : lightAlpha)];
    }];
}

- (BOOL)hasSelectedText {
    return [[self selectedTokenIndexes] count] > 0;
}

- (BOOL)hasTokens {
    return [[self tokens] count] > 0;
}

- (BOOL)hasAllTokensSelected {
    return [self hasTokens] && [[self selectedTokenIndexes] count] == [[self tokens] count];
}


- (NSRange)selectedTextRangeInOriginalText {
    if (![self hasSelectedText] || ![self originalText]) {
        return NSMakeRange(0, [[self originalText] length]);
    }

    __block NSUInteger location = NSNotFound;
    __block NSUInteger end = 0;
    [[self selectedTokenIndexes] enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
      if (index >= [[self tokens] count]) {
          return;
      }
      NSDictionary<NSString *, id> *token = [self tokens][index];
      NSRange range = [token[@"range"] rangeValue];
      if (location == NSNotFound || range.location < location) {
          location = range.location;
      }
      NSUInteger tokenEnd = NSMaxRange(range);
      if (tokenEnd > end) {
          end = tokenEnd;
      }
    }];
    if (location == NSNotFound) {
        return NSMakeRange(0, [[self originalText] length]);
    }
    return NSMakeRange(location, end - location);
}
- (NSString *)selectedText {
    NSMutableString *selectedText = [[NSMutableString alloc] init];
    if (![self usesSelectionOrderForSelectedText]) {
        __block NSUInteger previousTokenIndex = NSNotFound;
        __block NSRange previousRange = NSMakeRange(NSNotFound, 0);

        [[self selectedTokenIndexes] enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
          NSDictionary<NSString *, id> *token = [self tokens][index];
          NSRange range = [token[@"range"] rangeValue];
          if ([selectedText length] > 0) {
              if (previousTokenIndex != NSNotFound && index == previousTokenIndex + 1 &&
                  NSMaxRange(previousRange) <= range.location) {
                  NSRange separatorRange =
                      NSMakeRange(NSMaxRange(previousRange), range.location - NSMaxRange(previousRange));
                  [selectedText appendString:[[self originalText] substringWithRange:separatorRange]];
              } else {
                  [selectedText appendString:@" "];
              }
          }

          [selectedText appendString:token[@"text"]];
          previousTokenIndex = index;
          previousRange = range;
        }];

        return [selectedText copy];
    }

    NSMutableArray<NSNumber *> *orderedIndexes = [[NSMutableArray alloc] init];
    [[self selectedTokenIndexes] enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
      [orderedIndexes addObject:@(index)];
    }];
    [orderedIndexes sortUsingComparator:^NSComparisonResult(NSNumber *left, NSNumber *right) {
      NSUInteger leftIndex = [left unsignedIntegerValue];
      NSUInteger rightIndex = [right unsignedIntegerValue];
      NSNumber *leftStoredOrder = [self selectedTokenOrderValues][left];
      NSNumber *rightStoredOrder = [self selectedTokenOrderValues][right];
      NSUInteger leftOrder = leftStoredOrder ? [leftStoredOrder unsignedIntegerValue] : NSUIntegerMax;
      NSUInteger rightOrder = rightStoredOrder ? [rightStoredOrder unsignedIntegerValue] : NSUIntegerMax;
      if (leftOrder != rightOrder) {
          return leftOrder < rightOrder ? NSOrderedAscending : NSOrderedDescending;
      }
      if (leftIndex == rightIndex) {
          return NSOrderedSame;
      }
      return leftIndex < rightIndex ? NSOrderedAscending : NSOrderedDescending;
    }];

    for (NSNumber *indexValue in orderedIndexes) {
        NSUInteger index = [indexValue unsignedIntegerValue];
        NSDictionary<NSString *, id> *token = [self tokens][index];
        // Selection-order mode returns exactly the selected token text in tap order.
        // Do not reinsert separators from the original text, including spaces.
        [selectedText appendString:token[@"text"]];
    }

    return [selectedText copy];
}

@end
