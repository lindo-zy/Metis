//
//  MTHistoryListView.m
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import "MTHistoryListView.h"

#import "MTPasteboardManager.h"

static CGFloat const kMTHistoryListViewBaseRowHeight = 65;
static CGFloat const kMTHistoryListViewAdditionalPreviewLineHeight = 18;
static CGFloat const kMTHistoryListViewDetailLineHeight = 15;
static NSUInteger const kMTHistoryListViewMaximumPreviewLineCount = 3;
static CGFloat const kMTHistoryListViewHiddenHeaderInsetPadding = 1;
static CGFloat const kMTHistoryListViewVerticalFadeHeight = 20;
static CGFloat const kMTNoSearchResultsPlaceholderMinimumHeight = 96;
static NSTimeInterval const kMTHistoryListViewTransientContentOffsetPreservationDuration = 1.0;

NS_ASSUME_NONNULL_BEGIN

@interface MTNoSearchResultsFooterView : UIView
@property(nonatomic, strong) UILabel *label;
@end

@interface MTHistoryListView ()
@property(nonatomic, assign, getter=isUpdatingNoSearchResultsPlaceholderLayout)
    BOOL updatingNoSearchResultsPlaceholderLayout;
@property(nonatomic, assign) BOOL preservesTransientContentOffset;
@property(nonatomic, assign) CGPoint transientPreservedContentOffset;
@property(nonatomic, assign) NSUInteger transientContentOffsetPreservationIdentifier;
- (void)updateRowHeightForCurrentDisplayOptions;
@end

NS_ASSUME_NONNULL_END

@implementation MTNoSearchResultsFooterView

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setLabel:[[UILabel alloc] init]];
        [[self label] setFont:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium]];
        [[self label] setTextColor:[UIColor secondaryLabelColor]];
        [[self label] setTextAlignment:NSTextAlignmentCenter];
        [[self label] setNumberOfLines:0];
        [[self label] setText:[[MTPasteboardManager localizationBundle] localizedStringForKey:@"No Search Results"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
        [self addSubview:[self label]];

        [[self label] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[[self label] centerXAnchor] constraintEqualToAnchor:[self centerXAnchor]],
            [[[self label] centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
            [[[self label] leadingAnchor] constraintGreaterThanOrEqualToAnchor:[self leadingAnchor] constant:24],
            [[[self label] trailingAnchor] constraintLessThanOrEqualToAnchor:[self trailingAnchor] constant:-24]
        ]];
    }
    return self;
}

@end

@implementation MTHistoryListView

#pragma mark - Search Placeholder

- (void)setShowsNoSearchResultsPlaceholder:(BOOL)showsNoSearchResultsPlaceholder {
    UIView *footerView = [self tableFooterView];
    BOOL isShowingPlaceholder = [footerView isKindOfClass:[MTNoSearchResultsFooterView class]];
    if (!showsNoSearchResultsPlaceholder) {
        if (isShowingPlaceholder) {
            [self setTableFooterView:nil];
        }
        return;
    }

    if (!isShowingPlaceholder) {
        [self setTableFooterView:[[MTNoSearchResultsFooterView alloc] init]];
    }
    [self updateNoSearchResultsPlaceholderLayout];
}

- (CGFloat)noSearchResultsPlaceholderHeight {
    CGFloat headerHeight = [self hiddenHeaderOffsetY];
    CGFloat availableHeight = CGRectGetHeight([self bounds]) - headerHeight - [self keyboardBottomInset];
    return ceil(MAX(availableHeight, kMTNoSearchResultsPlaceholderMinimumHeight));
}

- (void)updateNoSearchResultsPlaceholderLayout {
    if ([self isUpdatingNoSearchResultsPlaceholderLayout]) {
        return;
    }

    UIView *footerView = [self tableFooterView];
    if (![footerView isKindOfClass:[MTNoSearchResultsFooterView class]]) {
        return;
    }

    CGRect targetFrame = CGRectMake(0, 0, CGRectGetWidth([self bounds]), [self noSearchResultsPlaceholderHeight]);
    if (CGRectEqualToRect([footerView frame], targetFrame)) {
        return;
    }

    [self setUpdatingNoSearchResultsPlaceholderLayout:YES];
    [footerView setFrame:targetFrame];
    [self setTableFooterView:footerView];
    [self setUpdatingNoSearchResultsPlaceholderLayout:NO];
}

- (void)setKeyboardBottomInset:(CGFloat)keyboardBottomInset {
    keyboardBottomInset = MAX(keyboardBottomInset, 0);
    if (_keyboardBottomInset == keyboardBottomInset) {
        return;
    }

    _keyboardBottomInset = keyboardBottomInset;
    [self updateNoSearchResultsPlaceholderLayout];
}

#pragma mark - Search Header Geometry

- (CGFloat)hiddenHeaderOffsetY {
    UIView *headerView = [self tableHeaderView];
    return headerView ? CGRectGetHeight([headerView frame]) : 0;
}

- (CGFloat)effectiveRowHeight {
    CGFloat height = [self rowHeight];
    return height > 0 ? height : kMTHistoryListViewBaseRowHeight;
}

- (BOOL)isSearchHeaderExposedAtContentOffset:(CGPoint)contentOffset {
    CGFloat headerHeight = [self hiddenHeaderOffsetY];
    return headerHeight > 0 && contentOffset.y < headerHeight - 1;
}

- (BOOL)isContentOffsetAtHiddenSearchHeaderBoundary:(CGPoint)contentOffset {
    CGFloat headerHeight = [self hiddenHeaderOffsetY];
    if (headerHeight <= 0) {
        return NO;
    }

    CGFloat rowHeight = [self effectiveRowHeight];
    return contentOffset.y >= headerHeight - 1 && contentOffset.y <= headerHeight + rowHeight + 1;
}

- (void)adjustTargetContentOffsetForSearchBarSnap:(CGPoint *)targetContentOffset {
    CGFloat searchBarHeight = [self searchBarSnapHeight];
    if (!targetContentOffset || searchBarHeight <= 0) {
        return;
    }

    CGFloat targetOffsetY = targetContentOffset->y;
    if (targetOffsetY <= 0 || targetOffsetY >= searchBarHeight) {
        return;
    }

    CGFloat snapThresholdY = searchBarHeight / 3.0;
    targetContentOffset->y = targetOffsetY < snapThresholdY ? 0 : searchBarHeight;
}

- (CGFloat)heightForRowRemovalAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat height = CGRectGetHeight([self rectForRowAtIndexPath:indexPath]);
    if (height > 0) {
        return height;
    }

    return [self effectiveRowHeight];
}

- (CGFloat)minimumBottomInsetForMaintainingHiddenHeaderWithAdditionalContentHeightReduction:(CGFloat)heightReduction {
    CGFloat hiddenHeaderOffsetY = [self hiddenHeaderOffsetY];
    if (hiddenHeaderOffsetY <= 0) {
        return 0;
    }

    [self layoutIfNeeded];

    CGFloat projectedContentHeight = MAX([self contentSize].height - heightReduction, 0);
    CGFloat requiredContentHeight =
        CGRectGetHeight([self bounds]) + hiddenHeaderOffsetY + kMTHistoryListViewHiddenHeaderInsetPadding;
    return ceil(MAX(requiredContentHeight - projectedContentHeight, 0));
}

#pragma mark - Row Removal

- (void)prepareHiddenHeaderInsetsForRemovingRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat hiddenHeaderOffsetY = [self hiddenHeaderOffsetY];
    if (hiddenHeaderOffsetY <= 0 || [self isSearchHeaderExposedAtContentOffset:[self contentOffset]]) {
        return;
    }

    UIEdgeInsets contentInset = [self contentInset];
    CGFloat requiredBottomInset =
        [self minimumBottomInsetForMaintainingHiddenHeaderWithAdditionalContentHeightReduction:
                  [self heightForRowRemovalAtIndexPath:indexPath]];
    if (contentInset.bottom >= requiredBottomInset) {
        return;
    }

    contentInset.bottom = requiredBottomInset;
    [self setContentInset:contentInset];
}

#pragma mark - Transient Content Offset

- (BOOL)shouldPreserveTransientContentOffsetForRequestedContentOffset:(CGPoint)contentOffset {
    if (![self preservesTransientContentOffset]) {
        return NO;
    }
    if ([self isTracking] || [self isDragging] || [self isDecelerating]) {
        return NO;
    }

    CGPoint restoredContentOffset = [self transientContentOffsetForCurrentInsets];
    return fabs(contentOffset.y - restoredContentOffset.y) > 0.5 ||
           fabs(contentOffset.x - restoredContentOffset.x) > 0.5;
}

- (CGPoint)transientContentOffsetForCurrentInsets {
    UIEdgeInsets adjustedContentInset = [self adjustedContentInset];
    CGSize boundsSize = [self bounds].size;
    CGSize contentSize = [self contentSize];
    CGPoint contentOffset = [self transientPreservedContentOffset];

    CGFloat minimumX = -adjustedContentInset.left;
    CGFloat maximumX = MAX(minimumX, contentSize.width - boundsSize.width + adjustedContentInset.right);
    CGFloat minimumY = -adjustedContentInset.top;
    CGFloat maximumY = MAX(minimumY, contentSize.height - boundsSize.height + adjustedContentInset.bottom);
    contentOffset.x = MIN(MAX(contentOffset.x, minimumX), maximumX);
    contentOffset.y = MIN(MAX(contentOffset.y, minimumY), maximumY);
    return contentOffset;
}

- (void)restoreTransientContentOffsetForCurrentInsetsIfNeeded {
    if (![self preservesTransientContentOffset]) {
        return;
    }
    if ([self isTracking] || [self isDragging] || [self isDecelerating]) {
        return;
    }

    CGPoint restoredContentOffset = [self transientContentOffsetForCurrentInsets];
    CGPoint currentContentOffset = [self contentOffset];
    if (fabs(currentContentOffset.x - restoredContentOffset.x) <= 0.5 &&
        fabs(currentContentOffset.y - restoredContentOffset.y) <= 0.5) {
        return;
    }

    [super setContentOffset:restoredContentOffset];
}

- (void)endTransientContentOffsetPreservationIfNeeded {
    if (![self preservesTransientContentOffset]) {
        return;
    }

    [self setPreservesTransientContentOffset:NO];
}

- (void)beginTransientContentOffsetPreservationAtContentOffset:(CGPoint)contentOffset {
    [self setTransientPreservedContentOffset:contentOffset];
    [self setPreservesTransientContentOffset:YES];
    NSUInteger preservationIdentifier = [self transientContentOffsetPreservationIdentifier] + 1;
    [self setTransientContentOffsetPreservationIdentifier:preservationIdentifier];
    [self restoreTransientContentOffsetForCurrentInsetsIfNeeded];

    __weak typeof(self) weakSelf = self;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(kMTHistoryListViewTransientContentOffsetPreservationDuration * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          __strong typeof(weakSelf) strongSelf = weakSelf;
          if (!strongSelf || [strongSelf transientContentOffsetPreservationIdentifier] != preservationIdentifier) {
              return;
          }
          [strongSelf endTransientContentOffsetPreservationIfNeeded];
        });
}

- (void)restoreHiddenSearchHeaderOffsetWithoutAnimation {
    CGFloat hiddenHeaderOffsetY = [self hiddenHeaderOffsetY];
    if (hiddenHeaderOffsetY <= 0) {
        return;
    }

    [UIView performWithoutAnimation:^{
      UIEdgeInsets contentInset = [self contentInset];
      contentInset.bottom =
          MAX(contentInset.bottom,
              [self minimumBottomInsetForMaintainingHiddenHeaderWithAdditionalContentHeightReduction:0]);
      [self setContentInset:contentInset];
      [self layoutIfNeeded];
      CGPoint contentOffset = [self contentOffset];
      contentOffset.y = MAX(contentOffset.y, hiddenHeaderOffsetY);
      [self setContentOffset:contentOffset animated:NO];
    }];
}

- (BOOL)isSearchBarHiddenAtCurrentContentOffset {
    CGFloat snapHeight = [self searchBarSnapHeight];
    return snapHeight > 0 && [self contentOffset].y >= snapHeight - 1;
}

- (void)keepSearchBarHiddenAfterReload {
    CGFloat snapHeight = [self searchBarSnapHeight];
    if (snapHeight <= 0) {
        return;
    }
    if ([self isTracking] || [self isDragging] || [self isDecelerating]) {
        return;
    }
    [UIView performWithoutAnimation:^{
      UIEdgeInsets contentInset = [self contentInset];
      CGFloat requiredBottomInset =
          [self minimumBottomInsetForMaintainingHiddenHeaderWithAdditionalContentHeightReduction:0];
      if (contentInset.bottom < requiredBottomInset) {
          contentInset.bottom = requiredBottomInset;
          [self setContentInset:contentInset];
      }
      [self layoutIfNeeded];
      CGPoint contentOffset = [self contentOffset];
      if (contentOffset.y < snapHeight) {
          contentOffset.y = snapHeight;
          [self setContentOffset:contentOffset animated:NO];
      }
    }];
}

- (void)scrollToFirstItemKeepingSearchHeaderHiddenWithoutAnimation {
    [self endTransientContentOffsetPreservationIfNeeded];

    [UIView performWithoutAnimation:^{
      CGFloat hiddenHeaderOffsetY = [self hiddenHeaderOffsetY];
      if (hiddenHeaderOffsetY <= 0) {
          return;
      }

      UIEdgeInsets contentInset = [self contentInset];
      contentInset.bottom =
          MAX(contentInset.bottom,
              [self minimumBottomInsetForMaintainingHiddenHeaderWithAdditionalContentHeightReduction:0]);
      [self setContentInset:contentInset];
      [self layoutIfNeeded];

      CGPoint contentOffset = [self contentOffset];
      contentOffset.y = hiddenHeaderOffsetY;
      [self setContentOffset:contentOffset animated:NO];
    }];
}

#pragma mark - Content Offset

- (void)setContentOffset:(CGPoint)contentOffset {
    if ([self shouldPreserveTransientContentOffsetForRequestedContentOffset:contentOffset]) {
        [super setContentOffset:[self transientContentOffsetForCurrentInsets]];
        return;
    }

    [super setContentOffset:contentOffset];
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated {
    if ([self shouldPreserveTransientContentOffsetForRequestedContentOffset:contentOffset]) {
        [super setContentOffset:[self transientContentOffsetForCurrentInsets] animated:NO];
        [self updateEdgeFadeMask];
        return;
    }

    [super setContentOffset:contentOffset animated:animated];
    [self updateEdgeFadeMask];
}

- (void)setContentInset:(UIEdgeInsets)contentInset {
    [super setContentInset:contentInset];
    [self restoreTransientContentOffsetForCurrentInsetsIfNeeded];
}

- (void)scrollToTopAnimated:(BOOL)animated {
    CGPoint contentOffset = [self contentOffset];
    contentOffset.y = -[self adjustedContentInset].top;
    [self setContentOffset:contentOffset animated:animated];
}

- (void)updateEdgeFadeMask {
    [self setEdgeFadeLeadingScrollOffset:[self hiddenHeaderOffsetY]];
    [super updateEdgeFadeMask];
}

#pragma mark - Lifecycle

- (instancetype)initWithName:(NSString *)name {
    self = [super init];

    if (self) {
        [self setName:name];
        [self setBackgroundColor:[UIColor clearColor]];
        [self setClipsToBounds:YES];
        [self setAlwaysBounceVertical:YES];
        if (@available(iOS 11.1, *)) {
            [self setVerticalScrollIndicatorInsets:UIEdgeInsetsMake(4, 0, 8, 2)];
        }
        [self setEdgeFadeAxis:MTEdgeFadeAxisVertical];
        [self setEdgeFadeWidth:kMTHistoryListViewVerticalFadeHeight];
        [self setEdgeFadeEnabled:YES];
        _itemDetailsMode = kMTItemDetailsModeImagesOnly;
        [self setPreviewLineCount:1];
    }

    return self;
}

#pragma mark - Configuration

- (void)setPreviewLineCount:(NSUInteger)previewLineCount {
    NSUInteger lineCount = MIN(MAX(previewLineCount, 1), kMTHistoryListViewMaximumPreviewLineCount);
    _previewLineCount = lineCount;
    [self updateRowHeightForCurrentDisplayOptions];
    [self reloadData];
}

- (void)setItemDetailsMode:(MTItemDetailsMode)itemDetailsMode {
    if (itemDetailsMode != kMTItemDetailsModeOff && itemDetailsMode != kMTItemDetailsModeImagesOnly &&
        itemDetailsMode != kMTItemDetailsModeAll) {
        itemDetailsMode = kMTItemDetailsModeImagesOnly;
    }
    _itemDetailsMode = itemDetailsMode;
    [self updateRowHeightForCurrentDisplayOptions];
    [self reloadData];
}

- (void)updateRowHeightForCurrentDisplayOptions {
    CGFloat detailHeight =
        [self itemDetailsMode] == kMTItemDetailsModeAll ? kMTHistoryListViewDetailLineHeight : 0;
    [self setRowHeight:kMTHistoryListViewBaseRowHeight +
                       ([self previewLineCount] - 1) * kMTHistoryListViewAdditionalPreviewLineHeight +
                       detailHeight];
}

@end
