//
//  MTHistoryListView.h
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import "MTEdgeFadingTableView.h"
#import "MTPreferenceKeys.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTHistoryListView : MTEdgeFadingTableView

@property(nonatomic, copy) NSString *name;
@property(nonatomic, assign) NSUInteger previewLineCount;
@property(nonatomic, assign) MTItemDetailsMode itemDetailsMode;
@property(nonatomic, assign) CGFloat keyboardBottomInset;
@property(nonatomic, assign) CGFloat searchBarSnapHeight;

- (instancetype)initWithName:(NSString *)name;
- (void)setShowsNoSearchResultsPlaceholder:(BOOL)showsNoSearchResultsPlaceholder;
- (void)updateNoSearchResultsPlaceholderLayout;
- (BOOL)isSearchHeaderExposedAtContentOffset:(CGPoint)contentOffset;
- (BOOL)isContentOffsetAtHiddenSearchHeaderBoundary:(CGPoint)contentOffset;
- (void)adjustTargetContentOffsetForSearchBarSnap:(CGPoint *)targetContentOffset;
- (CGFloat)minimumBottomInsetForMaintainingHiddenHeaderWithAdditionalContentHeightReduction:(CGFloat)heightReduction;
- (void)prepareHiddenHeaderInsetsForRemovingRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)beginTransientContentOffsetPreservationAtContentOffset:(CGPoint)contentOffset;
- (void)restoreHiddenSearchHeaderOffsetWithoutAnimation;- (BOOL)isSearchBarHiddenAtCurrentContentOffset;
- (void)keepSearchBarHiddenAfterReload;
- (void)scrollToFirstItemKeepingSearchHeaderHiddenWithoutAnimation;
- (void)scrollToTopAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
