//
//  MTTableDataStore.m
//  Mt
//

#import "MTTableDataStore.h"

#import "MTPasteboardItem.h"
#import "MTSearchCriteria.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTTableDataStore ()
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *displayedItems;
@property(nonatomic, copy) NSString *searchText;
@property(nonatomic, strong) MTSearchCriteria *searchCriteria;
@property(nonatomic, assign, getter=isBrowsingSearchTokens) BOOL browsingSearchTokens;
@end

NS_ASSUME_NONNULL_END

@implementation MTTableDataStore

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = @[];
        _displayedItems = @[];
        _searchText = @"";
        _searchCriteria = [MTSearchCriteria emptyCriteria];
    }
    return self;
}

- (BOOL)hasActiveSearch {
    return [[self searchCriteria] hasActiveFilters] || [self isBrowsingSearchTokens];
}

- (void)refreshDisplayedItems {
    NSArray<NSDictionary<NSString *, id> *> *items = [self items] ?: @[];
    NSString *searchText =
        [[self searchText] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([searchText length] == 0) {
        [self setDisplayedItems:items];
        return;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *displayedItems = [[NSMutableArray alloc] init];
    for (NSDictionary<NSString *, id> *item in items) {
        NSString *imageName = item[kMTItemKeyImageName] ?: @"";
        NSString *content = item[kMTItemKeyContent] ?: @"";
        NSString *note = item[kMTItemKeyNote] ?: @"";
        BOOL contentMatches =
            [imageName length] == 0 && [content rangeOfString:searchText
                                                      options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch]
                                               .location != NSNotFound;
        BOOL noteMatches =
            [note rangeOfString:searchText options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location !=
            NSNotFound;
        if (!contentMatches && !noteMatches) {
            continue;
        }

        [displayedItems addObject:item];
    }
    [self setDisplayedItems:displayedItems];
}

- (void)setItems:(NSArray<NSDictionary<NSString *, id> *> *)items {
    _items = [items copy] ?: @[];
    if ([self isBrowsingSearchTokens]) {
        [self setDisplayedItems:[self items]];
    } else if (![self hasActiveSearch]) {
        [self refreshDisplayedItems];
    }
}

- (void)applySearchText:(NSString *)searchText {
    _searchCriteria = [[self searchCriteria] criteriaByReplacingSearchText:searchText];
    _searchText = [[self searchCriteria] searchText];
    [self setBrowsingSearchTokens:NO];
    [self refreshDisplayedItems];
}

- (void)beginApplyingSearchCriteria:(MTSearchCriteria *)searchCriteria {
    _searchCriteria = [searchCriteria copy] ?: [MTSearchCriteria emptyCriteria];
    _searchText = [[self searchCriteria] searchText];
    [self setBrowsingSearchTokens:NO];
}

- (void)applySearchCriteria:(MTSearchCriteria *)searchCriteria
              filteredItems:(NSArray<NSDictionary<NSString *, id> *> *)filteredItems {
    _searchCriteria = [searchCriteria copy] ?: [MTSearchCriteria emptyCriteria];
    _searchText = [[self searchCriteria] searchText];
    [self setBrowsingSearchTokens:NO];
    if ([[self searchCriteria] hasActiveFilters]) {
        [self setDisplayedItems:filteredItems ?: @[]];
        return;
    }
    [self refreshDisplayedItems];
}

- (void)showSearchTokensWithFullListForCriteria:(MTSearchCriteria *)searchCriteria {
    _searchCriteria = [searchCriteria copy] ?: [MTSearchCriteria emptyCriteria];
    _searchText = [[self searchCriteria] searchText];
    [self setBrowsingSearchTokens:YES];
    [self setDisplayedItems:[self items] ?: @[]];
}

- (void)clearSearch {
    _searchCriteria = [MTSearchCriteria emptyCriteria];
    _searchText = @"";
    [self setBrowsingSearchTokens:NO];
    [self refreshDisplayedItems];
}

- (NSUInteger)indexOfItemMatchingDictionary:(NSDictionary<NSString *, id> *)dictionary
                                    inItems:(NSArray<NSDictionary<NSString *, id> *> *)items {
    NSString *content = dictionary[kMTItemKeyContent];
    if ([content length] == 0) {
        return NSNotFound;
    }

    for (NSUInteger index = 0; index < [items count]; index++) {
        NSDictionary<NSString *, id> *item = items[index];
        if ([item[kMTItemKeyContent] isEqualToString:content]) {
            return index;
        }
    }
    return NSNotFound;
}

- (BOOL)removeDisplayedItemAtIndex:(NSUInteger)displayedIndex {
    if (displayedIndex >= [[self displayedItems] count]) {
        return NO;
    }

    NSDictionary<NSString *, id> *dictionary = [self displayedItems][displayedIndex];
    NSMutableArray<NSDictionary<NSString *, id> *> *displayedItems = [[self displayedItems] mutableCopy];
    [displayedItems removeObjectAtIndex:displayedIndex];
    [self setDisplayedItems:displayedItems];

    NSUInteger itemIndex = [self indexOfItemMatchingDictionary:dictionary inItems:[self items]];
    if (itemIndex != NSNotFound) {
        NSMutableArray<NSDictionary<NSString *, id> *> *items = [[self items] mutableCopy];
        [items removeObjectAtIndex:itemIndex];
        _items = [items copy];
    }
    return YES;
}

- (NSDictionary<NSString *, id> *)dictionaryBySettingNote:(NSString *)note
                                              inDictionary:(NSDictionary<NSString *, id> *)dictionary {
    NSMutableDictionary<NSString *, id> *updatedDictionary = [dictionary mutableCopy];
    if ([note length] > 0) {
        updatedDictionary[kMTItemKeyNote] = note;
    } else {
        [updatedDictionary removeObjectForKey:kMTItemKeyNote];
    }
    return updatedDictionary;
}

- (BOOL)dictionaryMatchesSearchText:(NSDictionary<NSString *, id> *)dictionary {
    NSString *searchText = [[[self searchCriteria] searchText]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([searchText length] == 0) {
        return YES;
    }

    NSString *imageName = dictionary[kMTItemKeyImageName] ?: @"";
    NSString *content = dictionary[kMTItemKeyContent] ?: @"";
    NSString *note = dictionary[kMTItemKeyNote] ?: @"";
    BOOL contentMatches =
        [imageName length] == 0 &&
        [content rangeOfString:searchText options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location !=
            NSNotFound;
    BOOL noteMatches =
        [note rangeOfString:searchText options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location !=
        NSNotFound;
    return contentMatches || noteMatches;
}

- (MTTableDataStoreDisplayedItemUpdate)updateNote:(NSString *)note
                             forItemMatchingDictionary:(NSDictionary<NSString *, id> *)dictionary
                                    displayedItemIndex:(NSUInteger *)displayedItemIndex {
    if (displayedItemIndex) {
        *displayedItemIndex = NSNotFound;
    }
    if (!dictionary) {
        return MTTableDataStoreDisplayedItemUpdateNotFound;
    }

    NSUInteger itemIndex = [self indexOfItemMatchingDictionary:dictionary inItems:[self items]];
    if (itemIndex == NSNotFound) {
        return MTTableDataStoreDisplayedItemUpdateNotFound;
    }

    NSDictionary<NSString *, id> *updatedDictionary =
        [self dictionaryBySettingNote:note inDictionary:[self items][itemIndex]];
    NSMutableArray<NSDictionary<NSString *, id> *> *items = [[self items] mutableCopy];
    items[itemIndex] = updatedDictionary;
    [self setItems:items];

    NSUInteger displayedIndex = [self indexOfItemMatchingDictionary:dictionary inItems:[self displayedItems]];
    if (displayedIndex == NSNotFound) {
        return MTTableDataStoreDisplayedItemUpdateNotFound;
    }
    if (displayedItemIndex) {
        *displayedItemIndex = displayedIndex;
    }

    BOOL matchesSearch = [self dictionaryMatchesSearchText:updatedDictionary];
    if (!matchesSearch) {
        NSMutableArray<NSDictionary<NSString *, id> *> *displayedItems = [[self displayedItems] mutableCopy];
        [displayedItems removeObjectAtIndex:displayedIndex];
        [self setDisplayedItems:displayedItems];
        return MTTableDataStoreDisplayedItemUpdateRemove;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *displayedItems = [[self displayedItems] mutableCopy];
    displayedItems[displayedIndex] = updatedDictionary;
    [self setDisplayedItems:displayedItems];
    return MTTableDataStoreDisplayedItemUpdateReload;
}

- (MTTableDataStoreDisplayedItemUpdate)replaceContent:(NSString *)content
                                 forItemMatchingDictionary:(NSDictionary<NSString *, id> *)dictionary
                                        displayedItemIndex:(NSUInteger *)displayedItemIndex {
    if (displayedItemIndex) {
        *displayedItemIndex = NSNotFound;
    }
    if (!dictionary || [content length] == 0) {
        return MTTableDataStoreDisplayedItemUpdateNotFound;
    }

    NSUInteger itemIndex = [self indexOfItemMatchingDictionary:dictionary inItems:[self items]];
    if (itemIndex == NSNotFound) {
        return MTTableDataStoreDisplayedItemUpdateNotFound;
    }

    NSMutableDictionary<NSString *, id> *updatedDictionary = [[self items][itemIndex] mutableCopy];
    updatedDictionary[kMTItemKeyContent] = content;
    BOOL hasLink = [content hasPrefix:@"http://"] || [content hasPrefix:@"https://"];
    updatedDictionary[kMTItemKeyHasLink] = @(hasLink);

    NSMutableArray<NSDictionary<NSString *, id> *> *items = [[self items] mutableCopy];
    items[itemIndex] = updatedDictionary;
    [self setItems:items];

    NSUInteger displayedIndex = [self indexOfItemMatchingDictionary:dictionary inItems:[self displayedItems]];
    if (displayedIndex == NSNotFound) {
        return MTTableDataStoreDisplayedItemUpdateNotFound;
    }
    if (displayedItemIndex) {
        *displayedItemIndex = displayedIndex;
    }

    BOOL matchesSearch = [self dictionaryMatchesSearchText:updatedDictionary];
    if (!matchesSearch) {
        NSMutableArray<NSDictionary<NSString *, id> *> *displayedItems = [[self displayedItems] mutableCopy];
        [displayedItems removeObjectAtIndex:displayedIndex];
        [self setDisplayedItems:displayedItems];
        return MTTableDataStoreDisplayedItemUpdateRemove;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *displayedItems = [[self displayedItems] mutableCopy];
    displayedItems[displayedIndex] = updatedDictionary;
    [self setDisplayedItems:displayedItems];
    return MTTableDataStoreDisplayedItemUpdateReload;
}

@end
