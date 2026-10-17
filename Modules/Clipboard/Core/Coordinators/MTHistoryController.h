//
//  MTHistoryController.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTHistoryController;
@class MTHistoryListViewController;
@class MTHistoryListView;

NS_ASSUME_NONNULL_BEGIN

@protocol MTHistoryControllerDelegate <NSObject>

- (BOOL)historyControllerIsPanelVisible:(MTHistoryController *)controller;
- (BOOL)historyControllerShouldSuppressVisibleUpdates:(MTHistoryController *)controller;
- (void)historyControllerNeedsVisibleReload:(MTHistoryController *)controller;
- (void)historyController:(MTHistoryController *)controller
    didUpdateActiveTableView:(MTHistoryListView *)tableView;
- (void)historyController:(MTHistoryController *)controller didFailLoadingHistoryWithError:(NSError *)error;

@end

@interface MTHistoryController : NSObject

@property(nonatomic, weak, nullable) id<MTHistoryControllerDelegate> delegate;
@property(nonatomic, copy) NSString *activeHistoryKey;

- (instancetype)initWithHistoryListViewController:(MTHistoryListViewController *)historyListViewController
                      favoritesListViewController:(MTHistoryListViewController *)favoritesListViewController;

- (NSString *)effectiveActiveHistoryKeyWithClearConfirmationHistoryKey:(nullable NSString *)clearConfirmationHistoryKey;
- (MTHistoryListViewController *)listViewControllerForHistoryKey:(NSString *)historyKey;
- (MTHistoryListView *)tableViewForHistoryKey:(NSString *)historyKey;
- (MTHistoryListView *)activeTableViewWithClearConfirmationHistoryKey:
    (nullable NSString *)clearConfirmationHistoryKey;

- (void)markHistoryKeyLoaded:(NSString *)historyKey;
- (void)markHistoryKeyDirty:(NSString *)historyKey;
- (void)markAllHistoryKeysForScrollToTopBeforeNextDisplay;
- (BOOL)consumeScrollToTopBeforeNextDisplayForHistoryKey:(NSString *)historyKey;
- (void)handleHistoryChanged;
- (void)preloadHistoryWithCompletion:(nullable void (^)(void))completion;
- (void)reloadTableViewForHistoryKey:(NSString *)historyKey
              animatingTopInsertions:(BOOL)animatingTopInsertions
                          completion:(nullable void (^)(MTHistoryListView *tableView))completion;
- (void)reloadTableViewForHistoryKey:(NSString *)historyKey
                          completion:(nullable void (^)(MTHistoryListView *tableView))completion;
- (void)handlePasteboardItemDictionary:(NSDictionary<NSString *, id> *)dictionary
                   movedFromHistoryKey:(NSString *)sourceHistoryKey
                          toHistoryKey:(NSString *)destinationHistoryKey;

@end

NS_ASSUME_NONNULL_END
