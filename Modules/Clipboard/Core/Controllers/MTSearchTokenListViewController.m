//
//  MTSearchTokenListViewController.m
//  Mt
//

#import "MTSearchTokenListViewController.h"

#import "MTApplicationMetadataProvider.h"
#import "MTPasteboardManager.h"
#import "MTSearchCriteria.h"
#import "MTSearchTokenCollectionView.h"
#import "MTSearchTokenCollectionViewCell.h"
#import "MTSearchTokenSectionView.h"
#import "MTTagColorFormatter.h"

static CGFloat const kMTSearchTokenTopInset = 12;
static CGFloat const kMTSearchTokenBottomInset = 20;
static CGFloat const kMTSearchTokenSectionSpacing = 16;

NS_ASSUME_NONNULL_BEGIN

@interface MTSearchTokenListViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
#pragma mark - Views

@property(nonatomic, strong) MTSearchTokenSectionView *categorySectionView;
@property(nonatomic, strong) MTSearchTokenSectionView *tagSectionView;
@property(nonatomic, strong) MTSearchTokenSectionView *appSectionView;

#pragma mark - Data

@property(nonatomic, strong) NSArray<MTSearchToken *> *categoryTokens;
@property(nonatomic, strong) NSArray<MTSearchToken *> *tagTokens;
@property(nonatomic, strong) NSArray<MTSearchToken *> *appTokens;
@property(nonatomic, strong) MTSearchCriteria *searchCriteria;
@property(nonatomic, strong) MTApplicationMetadataProvider *metadataProvider;

#pragma mark - Layout State

@property(nonatomic, assign) CGFloat lastPreferredHeight;
@property(nonatomic, assign) BOOL needsCategoryContentOffsetReset;
@property(nonatomic, assign) BOOL needsTagContentOffsetReset;
@property(nonatomic, assign) BOOL needsAppContentOffsetReset;
@end

NS_ASSUME_NONNULL_END

@implementation MTSearchTokenListViewController

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _searchCriteria = [MTSearchCriteria emptyCriteria];
        _categoryTokens = [self newCategoryTokens];
        _tagTokens = @[];
        _appTokens = @[];
        _metadataProvider = [[MTApplicationMetadataProvider alloc] init];
        _showsCategorySectionEnabled = YES;
        _showsTagSectionEnabled = YES;
        _showsAppSectionEnabled = YES;
        _needsCategoryContentOffsetReset = YES;
        _needsTagContentOffsetReset = YES;
        _needsAppContentOffsetReset = YES;
    }
    return self;
}

#pragma mark - View Setup

- (void)loadView {
    UIView *view = [[UIView alloc] init];
    [view setBackgroundColor:[UIColor clearColor]];
    [self setView:view];

    NSBundle *bundle = [MTPasteboardManager localizationBundle];
    _categorySectionView = [[MTSearchTokenSectionView alloc]
        initWithTitle:[bundle localizedStringForKey:@"Categories" value:nil table:@"Tweak"]];
    _tagSectionView = [[MTSearchTokenSectionView alloc] initWithTitle:[bundle localizedStringForKey:@"Tags"
                                                                                                  value:nil
                                                                                                  table:@"Tweak"]];
    _appSectionView = [[MTSearchTokenSectionView alloc] initWithTitle:[bundle localizedStringForKey:@"Applications"
                                                                                                  value:nil
                                                                                                  table:@"Tweak"]];
    [view addSubview:_categorySectionView];
    [view addSubview:_tagSectionView];
    [view addSubview:_appSectionView];

    [self configureCollectionView:[_categorySectionView collectionView]];
    [self configureCollectionView:[_tagSectionView collectionView]];
    [self configureCollectionView:[_appSectionView collectionView]];
}

- (void)configureCollectionView:(UICollectionView *)collectionView {
    [collectionView setDataSource:self];
    [collectionView setDelegate:self];
    [collectionView registerClass:[MTSearchTokenCollectionViewCell class]
        forCellWithReuseIdentifier:[MTSearchTokenCollectionViewCell reuseIdentifier]];
}

#pragma mark - Token Sources

- (NSArray<MTSearchToken *> *)newCategoryTokens {
    NSBundle *bundle = [MTPasteboardManager localizationBundle];
    return @[
        [MTSearchToken tokenWithType:kMTSearchTokenTypeCategory
                                   value:kMTSearchCategoryText
                                   title:[bundle localizedStringForKey:@"Text" value:nil table:@"Tweak"]
                               imageName:@"text.alignleft"],
        [MTSearchToken tokenWithType:kMTSearchTokenTypeCategory
                                   value:kMTSearchCategoryLink
                                   title:[bundle localizedStringForKey:@"Links" value:nil table:@"Tweak"]
                               imageName:@"link"],
        [MTSearchToken tokenWithType:kMTSearchTokenTypeCategory
                                   value:kMTSearchCategoryImage
                                   title:[bundle localizedStringForKey:@"Images" value:nil table:@"Tweak"]
                               imageName:@"photo.fill"],
        [MTSearchToken tokenWithType:kMTSearchTokenTypeCategory
                                   value:kMTSearchCategoryPhone
                                   title:[bundle localizedStringForKey:@"Phone Numbers" value:nil table:@"Tweak"]
                               imageName:@"phone.fill"],
        [MTSearchToken tokenWithType:kMTSearchTokenTypeCategory
                                   value:kMTSearchCategoryDate
                                   title:[bundle localizedStringForKey:@"Dates" value:nil table:@"Tweak"]
                               imageName:@"calendar"],
        [MTSearchToken tokenWithType:kMTSearchTokenTypeCategory
                                   value:kMTSearchCategoryFlight
                                   title:[bundle localizedStringForKey:@"Flights" value:nil table:@"Tweak"]
                               imageName:@"airplane"],
        [MTSearchToken tokenWithType:kMTSearchTokenTypeCategory
                                   value:kMTSearchCategoryAddress
                                   title:[bundle localizedStringForKey:@"Addresses" value:nil table:@"Tweak"]
                               imageName:@"mappin.and.ellipse"]
    ];
}

#pragma mark - State

- (BOOL)showsCategorySection {
    return [self showsCategorySectionEnabled] &&
           ([self keepsSelectedSectionsVisible] || ![[self searchCriteria] hasCategoryToken]);
}

- (BOOL)showsAppSection {
    return [self showsAppSectionEnabled] &&
           ([self keepsSelectedSectionsVisible] || ![[self searchCriteria] hasAppToken]) &&
           [[self appTokens] count] > 0;
}

- (BOOL)showsTagSection {
    return [self showsTagSectionEnabled] &&
           ([self keepsSelectedSectionsVisible] || ![[self searchCriteria] hasTagToken]) &&
           [[self tagTokens] count] > 0;
}

- (void)setShowsCategorySectionEnabled:(BOOL)showsCategorySectionEnabled {
    if (_showsCategorySectionEnabled == showsCategorySectionEnabled) {
        return;
    }
    _showsCategorySectionEnabled = showsCategorySectionEnabled;
    [self updateSectionVisibility];
    [[self view] setNeedsLayout];
    [self notifyContentHeightIfNeeded];
}

- (void)setShowsTagSectionEnabled:(BOOL)showsTagSectionEnabled {
    if (_showsTagSectionEnabled == showsTagSectionEnabled) {
        return;
    }
    _showsTagSectionEnabled = showsTagSectionEnabled;
    [self updateSectionVisibility];
    [[self view] setNeedsLayout];
    [self notifyContentHeightIfNeeded];
}

- (void)setShowsAppSectionEnabled:(BOOL)showsAppSectionEnabled {
    if (_showsAppSectionEnabled == showsAppSectionEnabled) {
        return;
    }
    _showsAppSectionEnabled = showsAppSectionEnabled;
    [self updateSectionVisibility];
    [[self view] setNeedsLayout];
    [self notifyContentHeightIfNeeded];
}

- (BOOL)tokenArray:(NSArray<MTSearchToken *> *)left
    isDisplayEqualToTokenArray:(NSArray<MTSearchToken *> *)right {
    if ([left count] != [right count]) {
        return NO;
    }

    for (NSUInteger index = 0; index < [left count]; index++) {
        if (![left[index] isDisplayEqualToToken:right[index]]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)searchCriteria:(MTSearchCriteria *)left
    hasSameSelectedTokensAsSearchCriteria:(MTSearchCriteria *)right {
    return [([left categoryValue] ?: @"") isEqualToString:([right categoryValue] ?: @"")] &&
           [([left tagUUID] ?: @"") isEqualToString:([right tagUUID] ?: @"")] &&
           [([left appBundleIdentifier] ?: @"") isEqualToString:([right appBundleIdentifier] ?: @"")];
}

- (void)updateWithSearchCriteria:(MTSearchCriteria *)searchCriteria
                       tagTokens:(NSArray<MTSearchToken *> *)tagTokens
                       appTokens:(NSArray<MTSearchToken *> *)appTokens {
    MTSearchCriteria *newSearchCriteria = searchCriteria ?: [MTSearchCriteria emptyCriteria];
    NSArray<MTSearchToken *> *newTagTokens = tagTokens ?: @[];
    NSArray<MTSearchToken *> *newAppTokens = appTokens ?: @[];

    BOOL oldShowsCategory = [self showsCategorySection];
    BOOL oldShowsTag = [self showsTagSection];
    BOOL oldShowsApp = [self showsAppSection];
    BOOL oldTagUsesHorizontalLayout = [self usesHorizontalScrollingLayoutForTagSection];
    BOOL oldAppUsesHorizontalLayout = [self usesHorizontalScrollingLayoutForAppSection];

    BOOL selectedTokensChanged = ![self searchCriteria:[self searchCriteria]
                 hasSameSelectedTokensAsSearchCriteria:newSearchCriteria];
    BOOL tagTokensChanged = ![self tokenArray:[self tagTokens] isDisplayEqualToTokenArray:newTagTokens];
    BOOL appTokensChanged = ![self tokenArray:[self appTokens] isDisplayEqualToTokenArray:newAppTokens];

    [self setSearchCriteria:newSearchCriteria];
    if (tagTokensChanged) {
        [self setTagTokens:newTagTokens];
    }
    if (appTokensChanged) {
        [self setAppTokens:newAppTokens];
    }

    CGFloat width = CGRectGetWidth([[self view] bounds]);
    BOOL tagLayoutChanged = oldTagUsesHorizontalLayout != [self usesHorizontalScrollingLayoutForTagSection];
    BOOL appLayoutChanged = oldAppUsesHorizontalLayout != [self usesHorizontalScrollingLayoutForAppSection];
    if (tagTokensChanged || tagLayoutChanged) {
        [self setNeedsTagContentOffsetReset:YES];
        [self configureTagSectionForWidth:width];
        [[[self tagSectionView] collectionView] reloadData];
    }
    if (appTokensChanged || appLayoutChanged) {
        [self setNeedsAppContentOffsetReset:YES];
        [self configureAppSectionForWidth:width];
        [[[self appSectionView] collectionView] reloadData];
    }

    if (selectedTokensChanged) {
        if (!tagTokensChanged && !tagLayoutChanged) {
            [[[self tagSectionView] collectionView] reloadData];
        }
        if (!appTokensChanged && !appLayoutChanged) {
            [[[self appSectionView] collectionView] reloadData];
        }
        [[[self categorySectionView] collectionView] reloadData];
    }

    [self updateSectionVisibility];

    BOOL visibilityChanged = oldShowsCategory != [self showsCategorySection] || oldShowsTag != [self showsTagSection] ||
                             oldShowsApp != [self showsAppSection];
    if (selectedTokensChanged || tagTokensChanged || appTokensChanged || tagLayoutChanged || appLayoutChanged ||
        visibilityChanged) {
        [[self view] setNeedsLayout];
        [self notifyContentHeightIfNeeded];
    }
}

- (void)resetCollectionViewSessionState:(MTSearchTokenCollectionView *)collectionView {
    for (NSIndexPath *indexPath in [collectionView indexPathsForSelectedItems]) {
        [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    }
    [collectionView resetContentOffsetToLeadingEdge];
}

- (void)resetSearchSessionState {
    [self setSearchCriteria:[MTSearchCriteria emptyCriteria]];
    [self setLastPreferredHeight:0];
    [self setNeedsCategoryContentOffsetReset:YES];
    [self setNeedsTagContentOffsetReset:YES];
    [self setNeedsAppContentOffsetReset:YES];
    if (![self isViewLoaded]) {
        return;
    }

    [self updateSectionVisibility];
    [self resetCollectionViewSessionState:[[self categorySectionView] collectionView]];
    [self resetCollectionViewSessionState:[[self tagSectionView] collectionView]];
    [self resetCollectionViewSessionState:[[self appSectionView] collectionView]];
    [[self view] setNeedsLayout];
}

#pragma mark - Layout

- (void)updateSectionVisibility {
    BOOL showsCategory = [self showsCategorySection];
    BOOL showsTag = [self showsTagSection];
    BOOL showsApp = [self showsAppSection];
    [[self categorySectionView] setHidden:!showsCategory];
    [[self tagSectionView] setHidden:!showsTag];
    [[self appSectionView] setHidden:!showsApp];
}

- (BOOL)usesHorizontalScrollingLayoutForAppSection {
    return YES;
}

- (BOOL)usesHorizontalScrollingLayoutForTagSection {
    return YES;
}

- (void)configureTagSectionForWidth:(CGFloat)width {
    BOOL usesHorizontalScrollingLayout = [self usesHorizontalScrollingLayoutForTagSection];
    NSUInteger numberOfRows = [MTSearchTokenSectionView numberOfRowsForItemCount:[[self tagTokens] count]
                                                                               width:width
                                                           horizontalScrollingLayout:usesHorizontalScrollingLayout];
    [[self tagSectionView] setHorizontalScrollingLayout:usesHorizontalScrollingLayout];
    if (numberOfRows > 0) {
        [[self tagSectionView] setNumberOfRows:numberOfRows];
    }
}

- (void)configureAppSectionForWidth:(CGFloat)width {
    BOOL usesHorizontalScrollingLayout = [self usesHorizontalScrollingLayoutForAppSection];
    NSUInteger numberOfRows = [MTSearchTokenSectionView numberOfRowsForItemCount:[[self appTokens] count]
                                                                               width:width
                                                           horizontalScrollingLayout:usesHorizontalScrollingLayout];
    [[self appSectionView] setHorizontalScrollingLayout:usesHorizontalScrollingLayout];
    if (numberOfRows > 0) {
        [[self appSectionView] setNumberOfRows:numberOfRows];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutSectionsForWidth:CGRectGetWidth([[self view] bounds])];
    [self resetPendingCollectionViewContentOffsetsIfNeeded];
    [self updateVisibleEdgeFadeMasks];
    [self notifyContentHeightIfNeeded];
}

- (CGFloat)preferredContentHeightForWidth:(CGFloat)width {
    (void)width;
    BOOL showsCategory = [self showsCategorySection];
    BOOL showsTag = [self showsTagSection];
    BOOL showsApp = [self showsAppSection];
    if (!showsCategory && !showsTag && !showsApp) {
        return 0;
    }

    CGFloat height = kMTSearchTokenTopInset + kMTSearchTokenBottomInset;
    BOOL didAddSection = NO;
    if (showsCategory) {
        height += [MTSearchTokenSectionView preferredHeight];
        didAddSection = YES;
    }
    if (showsTag) {
        if (didAddSection) {
            height += kMTSearchTokenSectionSpacing;
        }
        height += [MTSearchTokenSectionView
            preferredHeightForItemCount:[[self tagTokens] count]
                                  width:width
              horizontalScrollingLayout:[self usesHorizontalScrollingLayoutForTagSection]];
        didAddSection = YES;
    }
    if (showsApp) {
        if (didAddSection) {
            height += kMTSearchTokenSectionSpacing;
        }
        height += [MTSearchTokenSectionView
            preferredHeightForItemCount:[[self appTokens] count]
                                  width:width
              horizontalScrollingLayout:[self usesHorizontalScrollingLayoutForAppSection]];
    }
    return height;
}

- (void)layoutSectionsForWidth:(CGFloat)width {
    CGFloat y = 0;
    BOOL didLayoutSection = NO;
    if ([self showsCategorySection]) {
        y += kMTSearchTokenTopInset;
        CGFloat sectionHeight = [MTSearchTokenSectionView preferredHeight];
        [[self categorySectionView] setFrame:CGRectMake(0, y, width, sectionHeight)];
        [[self categorySectionView] layoutIfNeeded];
        y += sectionHeight;
        didLayoutSection = YES;
    }
    if ([self showsTagSection]) {
        [self configureTagSectionForWidth:width];
        y += didLayoutSection ? kMTSearchTokenSectionSpacing : kMTSearchTokenTopInset;
        CGFloat sectionHeight = [[self tagSectionView] preferredHeight];
        [[self tagSectionView] setFrame:CGRectMake(0, y, width, sectionHeight)];
        [[self tagSectionView] layoutIfNeeded];
        y += sectionHeight;
        didLayoutSection = YES;
    }
    if ([self showsAppSection]) {
        [self configureAppSectionForWidth:width];
        y += didLayoutSection ? kMTSearchTokenSectionSpacing : kMTSearchTokenTopInset;
        CGFloat sectionHeight = [[self appSectionView] preferredHeight];
        [[self appSectionView] setFrame:CGRectMake(0, y, width, sectionHeight)];
        [[self appSectionView] layoutIfNeeded];
    }
}

- (void)updateVisibleEdgeFadeMasks {
    if (![[self categorySectionView] isHidden]) {
        [[[self categorySectionView] collectionView] updateEdgeFadeMask];
    }
    if (![[self tagSectionView] isHidden]) {
        [[[self tagSectionView] collectionView] updateEdgeFadeMask];
    }
    if (![[self appSectionView] isHidden]) {
        [[[self appSectionView] collectionView] updateEdgeFadeMask];
    }
}

- (void)resetPendingCollectionViewContentOffsetsIfNeeded {
    if ([self needsCategoryContentOffsetReset] && ![[self categorySectionView] isHidden]) {
        [[[self categorySectionView] collectionView] resetContentOffsetToLeadingEdge];
        [self setNeedsCategoryContentOffsetReset:NO];
    }
    if ([self needsTagContentOffsetReset] && ![[self tagSectionView] isHidden]) {
        [[[self tagSectionView] collectionView] resetContentOffsetToLeadingEdge];
        [self setNeedsTagContentOffsetReset:NO];
    }
    if ([self needsAppContentOffsetReset] && ![[self appSectionView] isHidden]) {
        [[[self appSectionView] collectionView] resetContentOffsetToLeadingEdge];
        [self setNeedsAppContentOffsetReset:NO];
    }
}

- (void)notifyContentHeightIfNeeded {
    CGFloat preferredHeight = [self preferredContentHeightForWidth:CGRectGetWidth([[self view] bounds])];
    if (fabs(preferredHeight - [self lastPreferredHeight]) < 0.5) {
        return;
    }
    [self setLastPreferredHeight:preferredHeight];
    if ([self contentHeightDidChange]) {
        [self contentHeightDidChange]();
    }
}

#pragma mark - UICollectionViewDataSource

- (NSArray<MTSearchToken *> *)tokensForCollectionView:(UICollectionView *)collectionView {
    if (collectionView == [[self appSectionView] collectionView]) {
        return [self appTokens];
    }
    if (collectionView == [[self tagSectionView] collectionView]) {
        return [self tagTokens];
    }
    return [self categoryTokens];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    (void)section;
    return (NSInteger)[[self tokensForCollectionView:collectionView] count];
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                           cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    MTSearchTokenCollectionViewCell *cell =
        [collectionView dequeueReusableCellWithReuseIdentifier:[MTSearchTokenCollectionViewCell reuseIdentifier]
                                                  forIndexPath:indexPath];
    MTSearchToken *token = [self tokensForCollectionView:collectionView][(NSUInteger)[indexPath item]];
    UIImage *icon = nil;
    UIColor *dotColor = nil;
    UIColor *dotBorderColor = nil;
    if ([[token type] isEqualToString:kMTSearchTokenTypeApp]) {
        icon = [[self metadataProvider] smallIconForBundleIdentifier:[token value]];
    } else if ([[token type] isEqualToString:kMTSearchTokenTypeTag]) {
        dotColor = [MTTagColorFormatter visibleColorFromHexColor:[token displaySignature]];
        dotBorderColor = [MTTagColorFormatter borderColorFromHexColor:[token displaySignature]];
    } else if ([[token imageName] length] > 0) {
        icon = [UIImage systemImageNamed:[token imageName]];
    }
    [cell configureWithTitle:[token title] icon:icon dotColor:dotColor dotBorderColor:dotBorderColor];
    [cell setActiveFilterHighlighted:[self tokenIsActiveInCriteria:token]];
    return cell;
}

- (BOOL)tokenIsActiveInCriteria:(MTSearchToken *)token {
    NSString *type = [token type];
    if ([type isEqualToString:kMTSearchTokenTypeCategory]) {
        return [[token value] isEqualToString:([[self searchCriteria] categoryValue] ?: @"")];
    }
    if ([type isEqualToString:kMTSearchTokenTypeTag]) {
        return [[token value] isEqualToString:([[self searchCriteria] tagUUID] ?: @"")];
    }
    if ([type isEqualToString:kMTSearchTokenTypeApp]) {
        return [[token value] isEqualToString:([[self searchCriteria] appBundleIdentifier] ?: @"")];
    }
    return NO;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<MTSearchToken *> *tokens = [self tokensForCollectionView:collectionView];
    if ((NSUInteger)[indexPath item] >= [tokens count]) {
        return;
    }
    [[self delegate] searchTokenListViewController:self didSelectToken:tokens[(NSUInteger)[indexPath item]]];
}

@end
