//
//  MTSearchController.h
//  Mt
//

#import <UIKit/UIKit.h>

#import "MTPanelPresentationMode.h"

@class MTSearchController;
@class MTHeaderView;
@class MTHistoryListViewController;
@class MTHistoryListView;

NS_ASSUME_NONNULL_BEGIN

@protocol MTSearchControllerDelegate <NSObject>

- (MTHistoryListViewController *)activeListViewControllerForSearchController:
    (MTSearchController *)searchController;
- (void)searchControllerWillBeginSearchInputTransition:(MTSearchController *)searchController;
- (void)searchControllerWillAnimateSearchState:(MTSearchController *)searchController;
- (void)searchControllerDidFinishAnimatingSearchState:(MTSearchController *)searchController;
- (void)searchController:(MTSearchController *)searchController
    didUpdateKeyboardBottomInset:(CGFloat)keyboardBottomInset;
- (void)searchController:(MTSearchController *)searchController didFailLoadingSearchWithError:(NSError *)error;

@end

@interface MTSearchController : NSObject

@property(nonatomic, weak, nullable) id<MTSearchControllerDelegate> delegate;
@property(nonatomic, assign) MTPanelPresentationMode presentationMode;
@property(nonatomic, assign, readonly, getter=isSearchActive) BOOL searchActive;
@property(nonatomic, assign, readonly) CGFloat keyboardBottomInset;
@property(nonatomic, assign, readonly, getter=isFavoritesFilterPanelVisible) BOOL favoritesFilterPanelVisible;

- (instancetype)initWithContainerView:(UIView *)containerView
                           headerView:(MTHeaderView *)headerView
            historyListViewController:(MTHistoryListViewController *)historyListViewController
          favoritesListViewController:(MTHistoryListViewController *)favoritesListViewController
                 panGestureRecognizer:(UIPanGestureRecognizer *)panGestureRecognizer;

- (void)layout;
- (void)setFavoritesFilterPanelVisible:(BOOL)favoritesFilterPanelVisible;
- (void)toggleFavoritesFilterPanelVisible;
- (void)setFavoritesFilterShowsCategories:(BOOL)showsCategories;
- (void)setFavoritesFilterShowsApps:(BOOL)showsApps;
- (BOOL)favoritesFilterShowsCategories;
- (BOOL)favoritesFilterShowsApps;
- (void)attachToListViewController:(MTHistoryListViewController *)listViewController
                    hidesSearchBar:(BOOL)hidesSearchBar;
- (void)refreshForListViewController:(MTHistoryListViewController *)listViewController;
- (void)refreshAfterTransientContentForListViewController:(MTHistoryListViewController *)listViewController
                                   restoresFirstResponder:(BOOL)restoresFirstResponder
                                      targetContentOffset:(CGPoint)targetContentOffset;
- (void)cancelSearchWithCompletion:(nullable void (^)(void))completion;
- (void)cancelSearchWithAnimations:(nullable void (^)(void))animations completion:(nullable void (^)(void))completion;
- (BOOL)isActiveSearchFirstResponder;
- (void)resignSearchFirstResponder;
- (void)handleApplicationMetadataChanged;
- (void)handleHistoryContentChanged;
- (void)handleFullscreenPanGestureRecognizer:(UIPanGestureRecognizer *)recognizer
                                  headerView:(nullable MTHeaderView *)headerView;
- (void)resetSearchState;
- (CGRect)resetSearchStatePreservingContainerFrame;

@end

NS_ASSUME_NONNULL_END
