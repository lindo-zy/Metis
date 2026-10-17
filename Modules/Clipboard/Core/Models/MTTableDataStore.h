//
//  MTTableDataStore.h
//  Mt
//

#import <Foundation/Foundation.h>

@class MTSearchCriteria;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MTTableDataStoreDisplayedItemUpdate) {
    MTTableDataStoreDisplayedItemUpdateNotFound = 0,
    MTTableDataStoreDisplayedItemUpdateReload,
    MTTableDataStoreDisplayedItemUpdateRemove,
};

@interface MTTableDataStore : NSObject

@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *items;
@property(nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *displayedItems;
@property(nonatomic, copy, readonly) NSString *searchText;
@property(nonatomic, strong, readonly) MTSearchCriteria *searchCriteria;
@property(nonatomic, assign, readonly, getter=isBrowsingSearchTokens) BOOL browsingSearchTokens;
@property(nonatomic, assign, readonly) BOOL hasActiveSearch;

- (void)applySearchText:(NSString *)searchText;
- (void)beginApplyingSearchCriteria:(MTSearchCriteria *)searchCriteria;
- (void)applySearchCriteria:(MTSearchCriteria *)searchCriteria
              filteredItems:(NSArray<NSDictionary<NSString *, id> *> *)filteredItems;
- (void)showSearchTokensWithFullListForCriteria:(MTSearchCriteria *)searchCriteria;
- (void)clearSearch;
- (NSUInteger)indexOfItemMatchingDictionary:(NSDictionary<NSString *, id> *)dictionary
                                    inItems:(NSArray<NSDictionary<NSString *, id> *> *)items;
- (BOOL)removeDisplayedItemAtIndex:(NSUInteger)displayedIndex;
- (MTTableDataStoreDisplayedItemUpdate)updateNote:(nullable NSString *)note
                                               tagUUID:(nullable NSString *)tagUUID
                                forItemMatchingDictionary:(NSDictionary<NSString *, id> *)dictionary
                                       displayedItemIndex:(NSUInteger *)displayedItemIndex;
- (MTTableDataStoreDisplayedItemUpdate)replaceContent:(NSString *)content
                                 forItemMatchingDictionary:(NSDictionary<NSString *, id> *)dictionary
                                        displayedItemIndex:(NSUInteger *)displayedItemIndex;

@end

NS_ASSUME_NONNULL_END
