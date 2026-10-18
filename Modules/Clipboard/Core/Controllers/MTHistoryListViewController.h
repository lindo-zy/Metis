//
//  MTHistoryListViewController.h
//  Mt
//

#import <UIKit/UIKit.h>

#import "MTPreferenceKeys.h"

@class MTHistoryListViewController;
@class MTHistoryListView;
@class MTPasteboardItem;
@class MTSearchCriteria;
@class MTTableViewCell;

NS_ASSUME_NONNULL_BEGIN

@protocol MTHistoryListViewControllerDelegate <NSObject>

- (void)historyListViewControllerDidRequestHide:(MTHistoryListViewController *)controller;
- (void)historyListViewControllerDidRequestHideAfterDirectPaste:(MTHistoryListViewController *)controller;
- (void)historyListViewController:(MTHistoryListViewController *)controller
         didRequestPreviewForItem:(MTPasteboardItem *)item;
- (void)historyListViewController:(MTHistoryListViewController *)controller
        didRequestEditNoteForItem:(MTPasteboardItem *)item
                 presentationCell:(MTTableViewCell *)presentationCell
                       sourceCell:(nullable MTTableViewCell *)sourceCell;
- (void)historyListViewControllerDidChangeContentState:(MTHistoryListViewController *)controller;
- (void)historyListViewController:(MTHistoryListViewController *)controller
            didMoveItemDictionary:(NSDictionary<NSString *, id> *)dictionary
               fromHistoryWithKey:(NSString *)sourceHistoryKey
                 toHistoryWithKey:(NSString *)destinationHistoryKey;

@end

@interface MTHistoryListViewController : UIViewController

@property(nonatomic, weak, nullable) id<MTHistoryListViewControllerDelegate> delegate;
@property(nonatomic, strong, readonly) MTHistoryListView *tableView;
@property(nonatomic, copy, readonly) NSString *historyKey;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *items;
@property(nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *displayedItems;
@property(nonatomic, copy, readonly) NSString *searchText;
@property(nonatomic, strong, readonly) MTSearchCriteria *searchCriteria;
@property(nonatomic, assign, readonly, getter=isBrowsingSearchTokens) BOOL browsingSearchTokens;
@property(nonatomic, assign, readonly) BOOL hasActiveSearch;
@property(nonatomic, assign) BOOL automaticallyPaste;
@property(nonatomic, assign) BOOL privacyMode;
@property(nonatomic, assign) NSUInteger previewLineCount;
@property(nonatomic, assign) MTItemDetailsMode itemDetailsMode;
@property(nonatomic, assign, getter=isGalleryModeEnabled) BOOL galleryModeEnabled;

- (instancetype)initWithName:(NSString *)name historyKey:(NSString *)historyKey NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (nullable NSDictionary<NSString *, id> *)itemDictionaryAtIndexPath:(NSIndexPath *)indexPath;
- (void)reloadDataWithItems:(NSArray<NSDictionary<NSString *, id> *> *)items;
- (void)updateDataWithItems:(NSArray<NSDictionary<NSString *, id> *> *)items
     animatingTopInsertions:(BOOL)animatingTopInsertions;
- (void)applySearchText:(NSString *)searchText;
- (void)beginApplyingSearchCriteria:(MTSearchCriteria *)searchCriteria;
- (void)applySearchCriteria:(MTSearchCriteria *)searchCriteria
              filteredItems:(NSArray<NSDictionary<NSString *, id> *> *)filteredItems;
- (void)showSearchTokensWithFullListForCriteria:(MTSearchCriteria *)searchCriteria;
- (void)clearSearch;
- (void)clearItems;
- (void)upsertItemDictionaryAtTop:(NSDictionary<NSString *, id> *)dictionary limit:(NSUInteger)limit;
- (void)upsertItemDictionaryAtTop:(NSDictionary<NSString *, id> *)dictionary
                            limit:(NSUInteger)limit
                        animating:(BOOL)animating;
- (void)removeItemDictionary:(NSDictionary<NSString *, id> *)dictionary;
- (void)removeItemAtIndexPath:(NSIndexPath *)indexPath completion:(nullable void (^)(BOOL success))completion;
- (void)updateNote:(nullable NSString *)note
            forItem:(MTPasteboardItem *)item
         completion:(nullable void (^)(void))completion;
- (void)replaceContent:(NSString *)content
               forItem:(MTPasteboardItem *)item
            completion:(nullable void (^)(void))completion;
- (void)replaceContent:(NSString *)content
forItemMatchingDictionary:(NSDictionary<NSString *, id> *)dictionary
            completion:(nullable void (^)(void))completion;
- (MTTableViewCell *)presentationCellForItem:(MTPasteboardItem *)item;
- (void)setCellPresentationHidden:(BOOL)hidden forItem:(MTPasteboardItem *)item;
- (nullable MTTableViewCell *)visibleCellForItem:(MTPasteboardItem *)item;
- (nullable MTTableViewCell *)scrollItemToVisible:(MTPasteboardItem *)item;
- (void)scrollToTopAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
