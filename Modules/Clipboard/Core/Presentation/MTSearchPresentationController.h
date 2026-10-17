//
//  MTSearchPresentationController.h
//  Mt
//

#import <UIKit/UIKit.h>

#import "MTPanelPresentationMode.h"

@class MTHistoryListView;
@class MTHeaderView;
@class MTSearchPresentationController;

NS_ASSUME_NONNULL_BEGIN

@protocol MTSearchPresentationControllerDelegate <NSObject>

- (void)searchPresentationController:(MTSearchPresentationController *)controller
        didUpdateKeyboardBottomInset:(CGFloat)keyboardBottomInset;
- (void)searchPresentationController:(MTSearchPresentationController *)controller
    didRequestCollapseFromFullscreenPanWithVelocity:(CGFloat)velocityY;

@end

@interface MTSearchPresentationController : NSObject

@property(nonatomic, weak, nullable) id<MTSearchPresentationControllerDelegate> delegate;
@property(nonatomic, assign) MTPanelPresentationMode presentationMode;
@property(nonatomic, assign, readonly, getter=isSearchActive) BOOL searchActive;
@property(nonatomic, assign, readonly) CGFloat keyboardBottomInset;

- (instancetype)initWithContainerView:(UIView *)containerView
                           headerView:(MTHeaderView *)headerView
                     historySearchBar:(UISearchBar *)historySearchBar
                   favoritesSearchBar:(UISearchBar *)favoritesSearchBar
               historySearchTokenView:(UIView *)historySearchTokenView
             favoritesSearchTokenView:(UIView *)favoritesSearchTokenView
                     historyTableView:(MTHistoryListView *)historyTableView
                   favoritesTableView:(MTHistoryListView *)favoritesTableView
                 panGestureRecognizer:(UIPanGestureRecognizer *)panGestureRecognizer;

- (CGFloat)searchHeaderHeight;
- (void)layout;
- (void)updateSearchTokenViews;
- (void)attachToTableView:(MTHistoryListView *)tableView hidesSearchBar:(BOOL)hidesSearchBar;
- (void)hideSearchBarInTableView:(nullable MTHistoryListView *)tableView animated:(BOOL)animated;
- (void)revealSearchBarInTableView:(nullable MTHistoryListView *)tableView animated:(BOOL)animated;
- (void)beginSearchWithActiveTableView:(MTHistoryListView *)activeTableView
                            completion:(nullable void (^)(void))completion;
- (void)endSearchRestoringFrame:(BOOL)restoresFrame
                activeTableView:(MTHistoryListView *)activeTableView
                     completion:(nullable void (^)(void))completion;
- (void)endSearchRestoringFrame:(BOOL)restoresFrame
                activeTableView:(MTHistoryListView *)activeTableView
                     animations:(nullable void (^)(void))animations
                     completion:(nullable void (^)(void))completion;
- (void)endSearchRestoringFrame:(BOOL)restoresFrame
                activeTableView:(MTHistoryListView *)activeTableView
                     animations:(nullable void (^)(void))animations
                   panVelocityY:(CGFloat)panVelocityY
                     completion:(nullable void (^)(void))completion;
- (void)handleFullscreenPanGestureRecognizer:(UIPanGestureRecognizer *)recognizer
                             activeTableView:(MTHistoryListView *)activeTableView
                                  headerView:(nullable MTHeaderView *)headerView;
- (void)resetKeyboardInsets;
- (void)resetAfterSearchStateClearedWithActiveTableView:(nullable MTHistoryListView *)activeTableView;
- (CGRect)resetAfterSearchStateClearedWithActiveTableView:(nullable MTHistoryListView *)activeTableView
                                   restoresContainerFrame:(BOOL)restoresContainerFrame;

@end

NS_ASSUME_NONNULL_END
