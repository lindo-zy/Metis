//
//  MTSearchController.m
//  Mt
//

#import "MTSearchController.h"

#import "MTApplicationMetadataProvider.h"
#import "MTHistoryListView.h"
#import "MTHistoryListViewController.h"
#import "MTPasteboardManager.h"
#import "MTPreferenceKeys.h"
#import "MTSearchBar.h"
#import "MTSearchCriteria.h"
#import "MTSearchPresentationController.h"
#import "MTSearchTokenListViewController.h"

static NSTimeInterval const kMTSearchInputDebounceInterval = 0.15;

NS_ASSUME_NONNULL_BEGIN

@interface MTSearchController () <UISearchBarDelegate, MTSearchPresentationControllerDelegate,
                                      MTSearchTokenListViewControllerDelegate>
#pragma mark - Presentation

@property(nonatomic, strong) MTSearchPresentationController *presentationController;
@property(nonatomic, weak) MTHistoryListViewController *historyListViewController;
@property(nonatomic, weak) MTHistoryListViewController *favoritesListViewController;
@property(nonatomic, strong) UISearchBar *historySearchBar;
@property(nonatomic, strong) UISearchBar *favoritesSearchBar;
@property(nonatomic, strong) MTSearchTokenListViewController *historyTokenListViewController;
@property(nonatomic, strong) MTSearchTokenListViewController *favoritesTokenListViewController;

#pragma mark - Tokens

@property(nonatomic, copy) NSArray<MTSearchToken *> *historyAppTokens;
@property(nonatomic, copy) NSArray<MTSearchToken *> *favoritesAppTokens;
@property(nonatomic, strong) MTApplicationMetadataProvider *metadataProvider;

#pragma mark - State

@property(nonatomic, assign, getter=isSearchActive) BOOL searchActive;
@property(nonatomic, assign) BOOL isResettingSearch;
@property(nonatomic, assign) BOOL isEndingSearchTransition;
@property(nonatomic, assign) NSUInteger searchRequestIdentifier;
@property(nonatomic, copy, nullable) dispatch_block_t pendingTextSearchBlock;
@property(nonatomic, strong, nullable) MTSearchCriteria *pendingTextSearchCriteria;
@property(nonatomic, weak, nullable) UISearchBar *pendingTextSearchBar;
@property(nonatomic, assign) BOOL loadingAppTokens;
@property(nonatomic, assign) BOOL appTokensDirty;
@property(nonatomic, assign) BOOL needsAppTokenReloadAfterCurrentLoad;
@property(nonatomic, assign) NSUInteger appTokenLoadRequestIdentifier;
@property(nonatomic, assign) NSUInteger pendingAppTokenLoads;
@property(nonatomic, assign) BOOL appTokenLoadHadError;
@property(nonatomic, strong, nullable) NSError *appTokenLoadError;
@property(nonatomic, assign) BOOL deferredSearchTokenBootstrapPending;
@property(nonatomic, assign, readwrite, getter=isFavoritesFilterPanelVisible) BOOL favoritesFilterPanelVisible;
@property(nonatomic, assign) BOOL favoritesFilterShowsCategories;
@property(nonatomic, assign) BOOL favoritesFilterShowsApps;
@end

NS_ASSUME_NONNULL_END

@implementation MTSearchController

#pragma mark - Lifecycle

- (instancetype)initWithContainerView:(UIView *)containerView
                           headerView:(MTHeaderView *)headerView
            historyListViewController:(MTHistoryListViewController *)historyListViewController
          favoritesListViewController:(MTHistoryListViewController *)favoritesListViewController
                 panGestureRecognizer:(UIPanGestureRecognizer *)panGestureRecognizer {
    self = [super init];
    if (self) {
        _historyListViewController = historyListViewController;
        _favoritesListViewController = favoritesListViewController;
        _historySearchBar = [self newSearchBar];
        _favoritesSearchBar = [self newSearchBar];
        _historyTokenListViewController = [[MTSearchTokenListViewController alloc] init];
        _favoritesTokenListViewController = [[MTSearchTokenListViewController alloc] init];
        [_historyTokenListViewController setDelegate:self];
        [_favoritesTokenListViewController setDelegate:self];
        [_historyTokenListViewController setKeepsSelectedSectionsVisible:YES];
        [_favoritesTokenListViewController setKeepsSelectedSectionsVisible:YES];
        __weak typeof(self) weakSelf = self;
        [_historyTokenListViewController setContentHeightDidChange:^{
          [weakSelf updateSearchTokenHeaderHeights];
        }];
        [_favoritesTokenListViewController setContentHeightDidChange:^{
          [weakSelf updateSearchTokenHeaderHeights];
        }];
        _historyAppTokens = @[];
        _favoritesAppTokens = @[];
        _metadataProvider = [[MTApplicationMetadataProvider alloc] init];
        _appTokensDirty = YES;
        _favoritesFilterPanelVisible = kMTPreferenceKeyFavoritesFilterPanelVisibleDefaultValue;
        _favoritesFilterShowsCategories = kMTPreferenceKeyFavoritesFilterShowsCategoriesDefaultValue;
        _favoritesFilterShowsApps = kMTPreferenceKeyFavoritesFilterShowsAppsDefaultValue;
        [self loadFavoritesFilterPreferences];

        _presentationController =
            [[MTSearchPresentationController alloc] initWithContainerView:containerView
                                                                   headerView:headerView
                                                             historySearchBar:_historySearchBar
                                                           favoritesSearchBar:_favoritesSearchBar
                                                       historySearchTokenView:[_historyTokenListViewController view]
                                                     favoritesSearchTokenView:[_favoritesTokenListViewController view]
                                                             historyTableView:[historyListViewController tableView]
                                                           favoritesTableView:[favoritesListViewController tableView]
                                                         panGestureRecognizer:panGestureRecognizer];
        [_presentationController setDelegate:self];

        [self attachToListViewController:historyListViewController hidesSearchBar:YES];
        [self applyFavoritesFilterSectionVisibility];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleHistoryDidChangeNotification:)
                                                     name:kMTPasteboardManagerHistoryDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (UISearchBar *)newSearchBar {
    UISearchBar *searchBar = [[MTSearchBar alloc] initWithFrame:CGRectZero];
    [searchBar setPlaceholder:[[MTPasteboardManager localizationBundle] localizedStringForKey:@"Search"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
    [searchBar setSearchBarStyle:UISearchBarStyleMinimal];
    [searchBar setBackgroundImage:[[UIImage alloc] init]];
    [searchBar setTintColor:[UIColor labelColor]];
    [searchBar setDelegate:self];
    [[searchBar searchTextField] addTarget:self
                                    action:@selector(handleSearchTextFieldEditingChanged:)
                          forControlEvents:UIControlEventEditingChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSearchTextFieldTextDidChangeNotification:)
                                                 name:UITextFieldTextDidChangeNotification
                                               object:[searchBar searchTextField]];
    return searchBar;
}

- (void)dealloc {
    [self cancelPendingTextSearch];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)handleHistoryDidChangeNotification:(NSNotification *)notification {
    (void)notification;
    [self handleHistoryContentChanged];
}

- (void)handleApplicationMetadataChanged {
    [self invalidateAppTokensAndReloadIfActive];
}

- (void)handleHistoryContentChanged {
    [self setAppTokensDirty:YES];
    [self loadAppTokensIfNeeded];
}

#pragma mark - View Lookup

- (void)setPresentationMode:(MTPanelPresentationMode)presentationMode {
    _presentationMode = presentationMode;
    [[self presentationController] setPresentationMode:presentationMode];
}

- (MTHistoryListViewController *)activeListViewController {
    return [[self delegate] activeListViewControllerForSearchController:self];
}

- (MTHistoryListView *)activeTableView {
    return [[self activeListViewController] tableView];
}

- (CGFloat)searchHeaderHeight {
    return [[self presentationController] searchHeaderHeight];
}

- (CGFloat)keyboardBottomInset {
    return [[self presentationController] keyboardBottomInset];
}

- (UISearchBar *)searchBarForTableView:(MTHistoryListView *)tableView {
    return tableView == [[self favoritesListViewController] tableView] ? [self favoritesSearchBar]
                                                                       : [self historySearchBar];
}

- (MTHistoryListViewController *)listViewControllerForSearchBar:(UISearchBar *)searchBar {
    return searchBar == [self favoritesSearchBar] ? [self favoritesListViewController]
                                                  : [self historyListViewController];
}

- (UISearchBar *)activeSearchBar {
    return [self searchBarForTableView:[self activeTableView]];
}

- (MTSearchTokenListViewController *)tokenListViewControllerForSearchBar:(UISearchBar *)searchBar {
    return searchBar == [self favoritesSearchBar] ? [self favoritesTokenListViewController]
                                                  : [self historyTokenListViewController];
}

- (MTSearchTokenListViewController *)tokenListViewControllerForListViewController:
    (MTHistoryListViewController *)listViewController {
    return listViewController == [self favoritesListViewController] ? [self favoritesTokenListViewController]
                                                                    : [self historyTokenListViewController];
}

#pragma mark - Token Matching

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

- (MTSearchToken *)tokenWithType:(NSString *)type
                               value:(NSString *)value
                            inTokens:(NSArray<MTSearchToken *> *)tokens {
    if ([value length] == 0) {
        return nil;
    }

    for (MTSearchToken *token in tokens) {
        if ([[token type] isEqualToString:type] && [[token value] isEqualToString:value]) {
            return token;
        }
    }
    return nil;
}

- (NSString *)appDisplaySignatureForBundleIdentifier:(NSString *)bundleIdentifier title:(NSString *)title {
    BOOL installed = [[self metadataProvider] hasApplicationForBundleIdentifier:bundleIdentifier];
    return [NSString stringWithFormat:@"installed=%@;title=%@", installed ? @"1" : @"0", title ?: @""];
}

- (MTSearchToken *)selectedCategoryTokenForCriteria:(MTSearchCriteria *)criteria
                                    tokenListController:(MTSearchTokenListViewController *)tokenListController {
    (void)tokenListController;
    NSString *categoryValue = [criteria categoryValue];
    if ([categoryValue length] == 0) {
        return nil;
    }

    NSBundle *bundle = [MTPasteboardManager localizationBundle];
    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *metadata = @{
        kMTSearchCategoryText :
            @{@"title" : [bundle localizedStringForKey:@"Text" value:nil table:@"Tweak"], @"image" : @"text.alignleft"},
        kMTSearchCategoryLink :
            @{@"title" : [bundle localizedStringForKey:@"Links" value:nil table:@"Tweak"], @"image" : @"link"},
        kMTSearchCategoryPhone : @{
            @"title" : [bundle localizedStringForKey:@"Phone Numbers" value:nil table:@"Tweak"],
            @"image" : @"phone.fill"
        },
        kMTSearchCategoryDate :
            @{@"title" : [bundle localizedStringForKey:@"Dates" value:nil table:@"Tweak"], @"image" : @"calendar"},
        kMTSearchCategoryFlight :
            @{@"title" : [bundle localizedStringForKey:@"Flights" value:nil table:@"Tweak"], @"image" : @"airplane"},
        kMTSearchCategoryAddress : @{
            @"title" : [bundle localizedStringForKey:@"Addresses" value:nil table:@"Tweak"],
            @"image" : @"mappin.and.ellipse"
        },
        kMTSearchCategoryImage :
            @{@"title" : [bundle localizedStringForKey:@"Images" value:nil table:@"Tweak"], @"image" : @"photo.fill"}
    };
    NSDictionary<NSString *, NSString *> *tokenMetadata = metadata[categoryValue];
    if (!tokenMetadata) {
        return nil;
    }
    return [MTSearchToken tokenWithType:kMTSearchTokenTypeCategory
                                      value:categoryValue
                                      title:tokenMetadata[@"title"]
                                  imageName:tokenMetadata[@"image"]];
}

- (MTSearchToken *)selectedAppTokenForCriteria:(MTSearchCriteria *)criteria
                                         appTokens:(NSArray<MTSearchToken *> *)appTokens {
    NSString *bundleIdentifier = [criteria appBundleIdentifier];
    if ([bundleIdentifier length] == 0) {
        return nil;
    }
    return [self tokenWithType:kMTSearchTokenTypeApp value:bundleIdentifier inTokens:appTokens];
}

- (UIImage *)iconForSearchToken:(MTSearchToken *)token {
    if ([[token type] isEqualToString:kMTSearchTokenTypeApp]) {
        return [[self metadataProvider] smallIconForBundleIdentifier:[token value]];
    }
    if ([[token imageName] length] > 0) {
        return [UIImage systemImageNamed:[token imageName]];
    }
    return nil;
}

#pragma mark - Search Token Sync

- (NSArray<MTSearchToken *> *)searchTokensForCriteria:(MTSearchCriteria *)criteria
                                      tokenListController:(MTSearchTokenListViewController *)tokenListController {
    NSMutableArray<MTSearchToken *> *searchTokens = [[NSMutableArray alloc] init];
    NSArray<MTSearchToken *> *tokens = @[
        [self selectedCategoryTokenForCriteria:criteria tokenListController:tokenListController] ?: (id)[NSNull null],
        [self selectedAppTokenForCriteria:criteria
                                appTokens:(tokenListController == [self favoritesTokenListViewController]
                                               ? [self favoritesAppTokens]
                                               : [self historyAppTokens])] ?: (id)[NSNull null]
    ];
    for (id object in tokens) {
        if ([object isKindOfClass:[MTSearchToken class]]) {
            [searchTokens addObject:object];
        }
    }
    return searchTokens;
}

- (NSArray<UISearchToken *> *)searchFieldTokensForSearchTokens:(NSArray<MTSearchToken *> *)tokens {
    NSMutableArray<UISearchToken *> *searchTokens = [[NSMutableArray alloc] init];
    for (MTSearchToken *token in tokens) {
        UIImage *icon = [self iconForSearchToken:token];
        UISearchToken *searchToken = [UISearchToken tokenWithIcon:icon text:[token title]];
        [searchToken setRepresentedObject:token];
        [searchTokens addObject:searchToken];
    }
    return searchTokens;
}

- (BOOL)searchTextField:(UISearchTextField *)textField hasSearchTokens:(NSArray<MTSearchToken *> *)tokens {
    NSArray<UISearchToken *> *currentSearchTokens = [textField tokens];
    if ([currentSearchTokens count] != [tokens count]) {
        return NO;
    }

    for (NSUInteger index = 0; index < [currentSearchTokens count]; index++) {
        id representedObject = [currentSearchTokens[index] representedObject];
        if (![representedObject isKindOfClass:[MTSearchToken class]] ||
            ![(MTSearchToken *)representedObject isDisplayEqualToToken:tokens[index]]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)syncSearchTokensForSearchBar:(UISearchBar *)searchBar criteria:(MTSearchCriteria *)criteria {
    (void)criteria;
    UITextField *textField = [searchBar searchTextField];
    if (![textField respondsToSelector:@selector(setTokens:)]) {
        return NO;
    }
    UISearchTextField *searchTextField = (UISearchTextField *)textField;
    if ([[searchTextField tokens] count] == 0) {
        return NO;
    }
    // Category and application filters are represented by the token sections below
    // the search bar, so the search field remains text-only for both lists.
    [searchTextField setTokens:@[]];
    return YES;
}

- (MTSearchCriteria *)criteriaFromSearchBar:(UISearchBar *)searchBar
                             listViewController:(MTHistoryListViewController *)listViewController {
    MTSearchCriteria *criteria =
        [[listViewController searchCriteria] criteriaByReplacingSearchText:[searchBar text]];
    return criteria;
}

#pragma mark - Favorites Filter Panel

- (void)setFavoritesFilterPanelVisible:(BOOL)favoritesFilterPanelVisible {
    if (_favoritesFilterPanelVisible == favoritesFilterPanelVisible) {
        [self updateSearchTokenHeaderHeights];
        return;
    }
    _favoritesFilterPanelVisible = favoritesFilterPanelVisible;
    [self persistFavoritesFilterPreferences];
    if (favoritesFilterPanelVisible) {
        [self bootstrapSearchTokenSourcesIfNeeded];
    }
    [self applyFavoritesFilterSectionVisibility];
    [self updateAllTokenLists];
    [self pruneFavoritesFilterCriteriaForHiddenSections];
}

- (void)toggleFavoritesFilterPanelVisible {
    [self setFavoritesFilterPanelVisible:![self isFavoritesFilterPanelVisible]];
}

- (void)setFavoritesFilterShowsCategories:(BOOL)showsCategories {
    if (_favoritesFilterShowsCategories == showsCategories) {
        return;
    }
    _favoritesFilterShowsCategories = showsCategories;
    [self persistFavoritesFilterPreferences];
    [self applyFavoritesFilterSectionVisibility];
    [self updateAllTokenLists];
    [self pruneFavoritesFilterCriteriaForHiddenSections];
}

- (void)setFavoritesFilterShowsApps:(BOOL)showsApps {
    if (_favoritesFilterShowsApps == showsApps) {
        return;
    }
    _favoritesFilterShowsApps = showsApps;
    [self persistFavoritesFilterPreferences];
    if (showsApps) {
        [self bootstrapSearchTokenSourcesIfNeeded];
    }
    [self applyFavoritesFilterSectionVisibility];
    [self updateAllTokenLists];
    [self pruneFavoritesFilterCriteriaForHiddenSections];
}

#pragma mark - Layout

- (void)layout {
    [[self presentationController] layout];
}

- (void)attachToListViewController:(MTHistoryListViewController *)listViewController
                    hidesSearchBar:(BOOL)hidesSearchBar {
    UISearchBar *searchBar = [self searchBarForTableView:[listViewController tableView]];
    if ([self pendingTextSearchBar] && [self pendingTextSearchBar] != searchBar) {
        [self cancelPendingTextSearch];
    }
    [[self presentationController] attachToTableView:[listViewController tableView] hidesSearchBar:hidesSearchBar];
}

- (BOOL)listViewControllerIsFavorites:(MTHistoryListViewController *)listViewController {
    return listViewController == [self favoritesListViewController] ||
           [[listViewController historyKey] isEqualToString:kMTHistoryKeyFavorites];
}

- (void)loadFavoritesFilterPreferences {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
    id panelVisible = [defaults objectForKey:kMTPreferenceKeyFavoritesFilterPanelVisible];
    if (panelVisible != nil) {
        _favoritesFilterPanelVisible = [panelVisible boolValue];
    }
    id showsCategories = [defaults objectForKey:kMTPreferenceKeyFavoritesFilterShowsCategories];
    if (showsCategories != nil) {
        _favoritesFilterShowsCategories = [showsCategories boolValue];
    }
    id showsApps = [defaults objectForKey:kMTPreferenceKeyFavoritesFilterShowsApps];
    if (showsApps != nil) {
        _favoritesFilterShowsApps = [showsApps boolValue];
    }
}

- (void)persistFavoritesFilterPreferences {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
    [defaults setBool:[self isFavoritesFilterPanelVisible] forKey:kMTPreferenceKeyFavoritesFilterPanelVisible];
    [defaults setBool:[self favoritesFilterShowsCategories] forKey:kMTPreferenceKeyFavoritesFilterShowsCategories];
    [defaults setBool:[self favoritesFilterShowsApps] forKey:kMTPreferenceKeyFavoritesFilterShowsApps];
}

- (void)applyFavoritesFilterSectionVisibility {
    [[self historyTokenListViewController] setShowsCategorySectionEnabled:YES];
    [[self historyTokenListViewController] setShowsAppSectionEnabled:YES];
    [[self favoritesTokenListViewController] setShowsCategorySectionEnabled:[self favoritesFilterShowsCategories]];
    [[self favoritesTokenListViewController] setShowsAppSectionEnabled:[self favoritesFilterShowsApps]];
}

- (void)pruneFavoritesFilterCriteriaForHiddenSections {
    MTHistoryListViewController *favoritesListViewController = [self favoritesListViewController];
    if (!favoritesListViewController) {
        return;
    }
    MTSearchCriteria *criteria = [favoritesListViewController searchCriteria];
    BOOL panelVisible = [self isFavoritesFilterPanelVisible];
    NSString *categoryValue =
        (panelVisible && [self favoritesFilterShowsCategories]) ? [criteria categoryValue] : nil;
    NSString *appBundleIdentifier =
        (panelVisible && [self favoritesFilterShowsApps]) ? [criteria appBundleIdentifier] : nil;
    MTSearchCriteria *prunedCriteria = [MTSearchCriteria criteriaWithSearchText:[criteria searchText]
                                                                          categoryValue:categoryValue
                                                                    appBundleIdentifier:appBundleIdentifier];
    if ([prunedCriteria isEqualToCriteria:criteria]) {
        return;
    }
    [self applySearchCriteria:prunedCriteria toListViewController:favoritesListViewController];
}

- (BOOL)shouldShowTokenListForListViewController:(MTHistoryListViewController *)listViewController {
    if ([self isEndingSearchTransition]) {
        return NO;
    }
    if (![self listViewControllerIsFavorites:listViewController]) {
        return YES;
    }
    if (![self isFavoritesFilterPanelVisible]) {
        return NO;
    }
    return [self favoritesFilterShowsCategories] || [self favoritesFilterShowsApps];
}

- (void)updateSearchTokenHeaderHeights {
    [self updateSearchTokenHeaderHeightForListViewController:[self historyListViewController]];
    [self updateSearchTokenHeaderHeightForListViewController:[self favoritesListViewController]];
    [[self presentationController] updateSearchTokenViews];
}

- (void)updateSearchTokenHeaderHeightForListViewController:(MTHistoryListViewController *)listViewController {
    MTSearchTokenListViewController *tokenListController =
        [self tokenListViewControllerForListViewController:listViewController];
    UIView *tokenView = [tokenListController view];
    BOOL showsTokenList = [self shouldShowTokenListForListViewController:listViewController];
    CGFloat width = CGRectGetWidth([[listViewController tableView] bounds]);
    CGFloat height = showsTokenList ? [tokenListController preferredContentHeightForWidth:width] : 0;
    [tokenView setHidden:height <= 0];
    [tokenView setFrame:CGRectMake(0, 0, width, height)];
}

- (void)updateTokenListForListViewController:(MTHistoryListViewController *)listViewController {
    MTSearchTokenListViewController *tokenListController =
        [self tokenListViewControllerForListViewController:listViewController];
    if ([self listViewControllerIsFavorites:listViewController]) {
        [tokenListController setShowsCategorySectionEnabled:[self favoritesFilterShowsCategories]];
        [tokenListController setShowsAppSectionEnabled:[self favoritesFilterShowsApps]];
    } else {
        [tokenListController setShowsCategorySectionEnabled:YES];
        [tokenListController setShowsAppSectionEnabled:YES];
    }
    [tokenListController updateWithSearchCriteria:[listViewController searchCriteria]
                                        appTokens:([self listViewControllerIsFavorites:listViewController]
                                                       ? [self favoritesAppTokens]
                                                       : [self historyAppTokens])];
}

- (void)updateAllTokenLists {
    [self updateTokenListForListViewController:[self historyListViewController]];
    [self updateTokenListForListViewController:[self favoritesListViewController]];
    [self updateSearchTokenHeaderHeights];
}

- (void)resetSearchSessionState {
    [[self historyTokenListViewController] resetSearchSessionState];
    [[self favoritesTokenListViewController] resetSearchSessionState];
}

- (void)syncSearchBarsAfterTokenSourceChange {
    if (![self isSearchActive]) {
        return;
    }

    [self syncSearchBarForListViewController:[self historyListViewController]];
    [self syncSearchBarForListViewController:[self favoritesListViewController]];

    MTHistoryListViewController *activeListViewController = [self activeListViewController];
    UISearchBar *activeSearchBar = [self searchBarForTableView:[activeListViewController tableView]];
    MTSearchCriteria *criteria = [self criteriaFromSearchBar:activeSearchBar
                                              listViewController:activeListViewController];
    if (![criteria isEqualToCriteria:[activeListViewController searchCriteria]]) {
        [self applySearchCriteria:criteria toListViewController:activeListViewController];
        return;
    }

    [self updateTokenListForListViewController:activeListViewController];
    [self updateSearchTokenHeaderHeights];
}

#pragma mark - Token Loading

- (NSArray<MTSearchToken *> *)appTokensFromBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers {
    NSMutableArray<NSString *> *installedBundleIdentifiers = [[NSMutableArray alloc] init];
    for (NSString *bundleIdentifier in bundleIdentifiers) {
        if ([[self metadataProvider] hasApplicationForBundleIdentifier:bundleIdentifier]) {
            [installedBundleIdentifiers addObject:bundleIdentifier];
        }
    }

    NSMutableArray<MTSearchToken *> *appTokens =
        [[NSMutableArray alloc] initWithCapacity:[installedBundleIdentifiers count]];
    for (NSString *bundleIdentifier in installedBundleIdentifiers) {
        NSString *title = [[self metadataProvider] displayNameForBundleIdentifier:bundleIdentifier];
        [appTokens
            addObject:[MTSearchToken tokenWithType:kMTSearchTokenTypeApp
                                                 value:bundleIdentifier
                                                 title:title
                                             imageName:nil
                                      displaySignature:[self appDisplaySignatureForBundleIdentifier:bundleIdentifier
                                                                                              title:title]]];
    }
    return appTokens;
}

- (void)finishLoadingAppTokensAndReloadIfNeeded {
    BOOL shouldReload = [self needsAppTokenReloadAfterCurrentLoad] || [self appTokensDirty];
    [self setNeedsAppTokenReloadAfterCurrentLoad:NO];
    if (shouldReload) {
        [self setAppTokensDirty:YES];
        [self loadAppTokensIfNeeded];
    }
}

- (void)invalidateAppTokensAndReloadIfActive {
    [self setAppTokensDirty:YES];
    if ([self loadingAppTokens]) {
        [self setNeedsAppTokenReloadAfterCurrentLoad:YES];
        return;
    }
    if ([self isSearchActive] || [self isFavoritesFilterPanelVisible]) {
        [self loadAppTokensIfNeeded];
    }
}

- (void)finishAppTokenLoadForHistoryKey:(NSString *)historyKey
                       bundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                                   error:(NSError *_Nullable)error
                    requestIdentifier:(NSUInteger)requestIdentifier {
    if ([self appTokenLoadRequestIdentifier] != requestIdentifier) {
        return;
    }
    if (error) {
        [self setAppTokensDirty:YES];
        [self setAppTokenLoadHadError:YES];
        [self setAppTokenLoadError:error];
    } else if ([historyKey isEqualToString:kMTHistoryKeyFavorites]) {
        [self setFavoritesAppTokens:[self appTokensFromBundleIdentifiers:bundleIdentifiers]];
    } else {
        [self setHistoryAppTokens:[self appTokensFromBundleIdentifiers:bundleIdentifiers]];
    }

    [self setPendingAppTokenLoads:[self pendingAppTokenLoads] - 1];
    if ([self pendingAppTokenLoads] != 0) {
        return;
    }

    [self setLoadingAppTokens:NO];
    if ([self appTokenLoadHadError]) {
        [[self delegate] searchController:self didFailLoadingSearchWithError:[self appTokenLoadError]];
    } else {
        [self updateAllTokenLists];
        [self syncSearchBarsAfterTokenSourceChange];
    }
    [self finishLoadingAppTokensAndReloadIfNeeded];
}

- (void)loadAppTokensIfNeeded {
    if (![self appTokensDirty]) {
        return;
    }
    if ([self loadingAppTokens]) {
        [self setNeedsAppTokenReloadAfterCurrentLoad:YES];
        return;
    }
    [self setAppTokensDirty:NO];
    [self setLoadingAppTokens:YES];
    [self setPendingAppTokenLoads:2];
    [self setAppTokenLoadHadError:NO];
    [self setAppTokenLoadError:nil];
    NSUInteger requestIdentifier = [self appTokenLoadRequestIdentifier] + 1;
    [self setAppTokenLoadRequestIdentifier:requestIdentifier];
    __weak typeof(self) weakSelf = self;
    [[MTPasteboardManager sharedInstance]
        availableSearchAppBundleIdentifiersForHistoryKey:kMTHistoryKeyHistory
                                               completion:^(NSArray<NSString *> *bundleIdentifiers, NSError *error) {
          __strong typeof(weakSelf) strongSelf = weakSelf;
          if (!strongSelf) {
              return;
          }
          [strongSelf finishAppTokenLoadForHistoryKey:kMTHistoryKeyHistory
                                     bundleIdentifiers:bundleIdentifiers
                                                 error:error
                                      requestIdentifier:requestIdentifier];
        }];
    [[MTPasteboardManager sharedInstance]
        availableSearchAppBundleIdentifiersForHistoryKey:kMTHistoryKeyFavorites
                                               completion:^(NSArray<NSString *> *bundleIdentifiers, NSError *error) {
          __strong typeof(weakSelf) strongSelf = weakSelf;
          if (!strongSelf) {
              return;
          }
          [strongSelf finishAppTokenLoadForHistoryKey:kMTHistoryKeyFavorites
                                     bundleIdentifiers:bundleIdentifiers
                                                 error:error
                                      requestIdentifier:requestIdentifier];
        }];
}

#pragma mark - Search Application

- (void)cancelPendingTextSearch {
    dispatch_block_t block = [self pendingTextSearchBlock];
    if (block) {
        dispatch_block_cancel(block);
    }
    [self setPendingTextSearchBlock:nil];
    [self setPendingTextSearchCriteria:nil];
    [self setPendingTextSearchBar:nil];
}

- (void)invalidatePendingSearchRequests {
    [self cancelPendingTextSearch];
    [self setSearchRequestIdentifier:[self searchRequestIdentifier] + 1];
}

- (BOOL)favoritesSearchBarHiddenBeforeReload:(MTHistoryListViewController *)listViewController {
    if ([self isSearchActive] || ![self listViewControllerIsFavorites:listViewController]) {
        return NO;
    }
    return [[listViewController tableView] isSearchBarHiddenAtCurrentContentOffset];
}

- (void)keepFavoritesSearchBarHidden:(BOOL)wasHidden
                forListViewController:(MTHistoryListViewController *)listViewController {
    if (!wasHidden || [self isSearchActive] || ![self listViewControllerIsFavorites:listViewController]) {
        return;
    }
    [[listViewController tableView] keepSearchBarHiddenAfterReload];
}

- (void)applySearchCriteria:(MTSearchCriteria *)criteria
       toListViewController:(MTHistoryListViewController *)listViewController {
    [self cancelPendingTextSearch];
    BOOL searchBarWasHidden = [self favoritesSearchBarHiddenBeforeReload:listViewController];
    if (![self isSearchActive] && ![criteria hasActiveFilters]) {
        [self invalidatePendingSearchRequests];
        if ([listViewController hasActiveSearch] || [listViewController isBrowsingSearchTokens]) {
            [listViewController clearSearch];
        }
        [self updateTokenListForListViewController:listViewController];
        [self updateSearchTokenHeaderHeights];
        [self keepFavoritesSearchBarHidden:searchBarWasHidden forListViewController:listViewController];
        return;
    }

    if (![criteria hasActiveFilters]) {
        [self invalidatePendingSearchRequests];
        [listViewController showSearchTokensWithFullListForCriteria:criteria];
        [self updateTokenListForListViewController:listViewController];
        [self updateSearchTokenHeaderHeights];
        return;
    }

    NSUInteger requestIdentifier = [self searchRequestIdentifier] + 1;
    [self setSearchRequestIdentifier:requestIdentifier];
    [listViewController beginApplyingSearchCriteria:criteria];
    [self updateTokenListForListViewController:listViewController];
    [self updateSearchTokenHeaderHeights];
    __weak typeof(self) weakSelf = self;
    [[MTPasteboardManager sharedInstance]
        getItemsFromHistoryWithKey:[listViewController historyKey]
                    searchCriteria:criteria
                        completion:^(NSMutableArray<NSDictionary<NSString *, id> *> *items, NSError *error) {
                          __strong typeof(weakSelf) strongSelf = weakSelf;
                          if (!strongSelf || [strongSelf searchRequestIdentifier] != requestIdentifier) {
                              return;
                          }
                          if (error) {
                              [[strongSelf delegate] searchController:strongSelf didFailLoadingSearchWithError:error];
                              return;
                          }
                          [listViewController applySearchCriteria:criteria filteredItems:items];
                          [strongSelf updateTokenListForListViewController:listViewController];
                          [strongSelf updateSearchTokenHeaderHeights];
                          [strongSelf keepFavoritesSearchBarHidden:searchBarWasHidden
                                             forListViewController:listViewController];
                        }];
}

- (void)applySearchFromSearchBar:(UISearchBar *)searchBar {
    MTHistoryListViewController *listViewController = [self listViewControllerForSearchBar:searchBar];
    MTSearchCriteria *criteria = [self criteriaFromSearchBar:searchBar listViewController:listViewController];
    [self syncSearchTokensForSearchBar:searchBar criteria:criteria];
    [self applySearchCriteria:criteria toListViewController:listViewController];
}

- (void)scheduleTextSearchFromSearchBar:(UISearchBar *)searchBar {
    if ([self isResettingSearch] ||
        [self listViewControllerForSearchBar:searchBar] != [self activeListViewController]) {
        return;
    }

    if ([[searchBar searchTextField] markedTextRange]) {
        [self cancelPendingTextSearch];
        return;
    }

    MTHistoryListViewController *listViewController = [self listViewControllerForSearchBar:searchBar];
    MTSearchCriteria *criteria = [self criteriaFromSearchBar:searchBar listViewController:listViewController];
    [self syncSearchTokensForSearchBar:searchBar criteria:criteria];

    if ([criteria isEqualToCriteria:[listViewController searchCriteria]]) {
        [self cancelPendingTextSearch];
        return;
    }
    if ([self pendingTextSearchBar] == searchBar && [[self pendingTextSearchCriteria] isEqualToCriteria:criteria]) {
        return;
    }
    if ([[criteria searchText] length] == 0) {
        [self applySearchCriteria:criteria toListViewController:listViewController];
        return;
    }

    [self cancelPendingTextSearch];
    [self setPendingTextSearchCriteria:criteria];
    [self setPendingTextSearchBar:searchBar];
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || [strongSelf pendingTextSearchCriteria] != criteria ||
          [strongSelf pendingTextSearchBar] != searchBar) {
          return;
      }

      [strongSelf setPendingTextSearchBlock:nil];
      [strongSelf setPendingTextSearchCriteria:nil];
      [strongSelf setPendingTextSearchBar:nil];
      [strongSelf applySearchCriteria:criteria toListViewController:listViewController];
    });
    [self setPendingTextSearchBlock:block];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kMTSearchInputDebounceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

- (void)applySearchToActiveTableView {
    [self applySearchFromSearchBar:[self activeSearchBar]];
}

- (void)syncSearchBarForListViewController:(MTHistoryListViewController *)listViewController {
    UISearchBar *searchBar = [self searchBarForTableView:[listViewController tableView]];
    MTSearchCriteria *criteria = [self pendingTextSearchBar] == searchBar ? [self pendingTextSearchCriteria]
                                                                              : [listViewController searchCriteria];
    BOOL wasResettingSearch = [self isResettingSearch];
    [self setIsResettingSearch:YES];
    [searchBar setText:[criteria searchText]];
    [self syncSearchTokensForSearchBar:searchBar criteria:criteria];
    [self setIsResettingSearch:wasResettingSearch];
}

- (void)restoreContentOffset:(CGPoint)contentOffset
       forListViewController:(MTHistoryListViewController *)listViewController {
    [[listViewController tableView] setContentOffset:contentOffset animated:NO];
}

- (void)refreshForListViewController:(MTHistoryListViewController *)listViewController {
    [self attachToListViewController:listViewController hidesSearchBar:![self isSearchActive]];
    if ([self isSearchActive]) {
        [self loadAppTokensIfNeeded];
    } else if ([self listViewControllerIsFavorites:listViewController] && [self isFavoritesFilterPanelVisible] &&
               [self favoritesFilterShowsApps]) {
        [self bootstrapSearchTokenSourcesIfNeeded];
    } else if (![self listViewControllerIsFavorites:listViewController]) {
        [self loadAppTokensIfNeeded];
    }
    [self syncSearchBarForListViewController:listViewController];
    [self updateTokenListForListViewController:listViewController];
    [self applySearchFromSearchBar:[self searchBarForTableView:[listViewController tableView]]];
    if ([self isSearchActive] && listViewController == [self activeListViewController]) {
        [[self historySearchBar] setShowsCancelButton:NO animated:NO];
        [[self favoritesSearchBar] setShowsCancelButton:NO animated:NO];
        [[self activeSearchBar] setShowsCancelButton:YES animated:NO];
        UISearchBar *searchBarToFocus = [self activeSearchBar];
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
          __strong typeof(weakSelf) strongSelf = weakSelf;
          if (!strongSelf || ![strongSelf isSearchActive] ||
              [strongSelf activeSearchBar] != searchBarToFocus) {
              return;
          }
          if (![searchBarToFocus isFirstResponder] && ![[searchBarToFocus searchTextField] isFirstResponder]) {
              [searchBarToFocus becomeFirstResponder];
          }
        });
    }
}

- (void)refreshAfterTransientContentForListViewController:(MTHistoryListViewController *)listViewController
                                   restoresFirstResponder:(BOOL)restoresFirstResponder
                                      targetContentOffset:(CGPoint)targetContentOffset {
    CGPoint currentContentOffset = [[listViewController tableView] contentOffset];
    [[self presentationController] layout];
    [self syncSearchBarForListViewController:listViewController];
    [self updateTokenListForListViewController:listViewController];
    [self updateSearchTokenHeaderHeights];
    [self restoreContentOffset:currentContentOffset forListViewController:listViewController];
    if ([self isSearchActive] && listViewController == [self activeListViewController]) {
        [[self historySearchBar] setShowsCancelButton:NO animated:NO];
        [[self favoritesSearchBar] setShowsCancelButton:NO animated:NO];
        [[self activeSearchBar] setShowsCancelButton:YES animated:NO];
        if (restoresFirstResponder) {
            [[listViewController tableView] beginTransientContentOffsetPreservationAtContentOffset:targetContentOffset];
            [[self activeSearchBar] becomeFirstResponder];
        }
    }
}

#pragma mark - Search Session

- (void)setSearchBarsShowCancelButton:(BOOL)showsCancelButton animated:(BOOL)animated {
    [[self historySearchBar] setShowsCancelButton:NO animated:animated];
    [[self favoritesSearchBar] setShowsCancelButton:NO animated:animated];
    if (showsCancelButton) {
        [[self activeSearchBar] setShowsCancelButton:YES animated:animated];
    }
}

- (void)resignSearchFirstResponder {
    [[self activeSearchBar] resignFirstResponder];
}

- (BOOL)isActiveSearchFirstResponder {
    UISearchBar *searchBar = [self activeSearchBar];
    UITextField *searchTextField = [searchBar searchTextField];
    return [searchBar isFirstResponder] || [searchTextField isFirstResponder];
}

- (void)bootstrapSearchTokenSourcesIfNeeded {
    [self loadAppTokensIfNeeded];
}

- (void)performDeferredSearchTokenBootstrapIfNeeded {
    if (![self deferredSearchTokenBootstrapPending] || ![self isSearchActive]) {
        return;
    }

    [self setDeferredSearchTokenBootstrapPending:NO];
    [self bootstrapSearchTokenSourcesIfNeeded];
}

- (void)beginSearchIfNeeded {
    if ([self isSearchActive]) {
        return;
    }

    [self setSearchActive:YES];
    [self applySearchFromSearchBar:[self activeSearchBar]];
    [self updateSearchTokenHeaderHeights];
    [self setSearchBarsShowCancelButton:YES animated:NO];
    [self setDeferredSearchTokenBootstrapPending:YES];
    [[self delegate] searchControllerWillAnimateSearchState:self];
    __weak typeof(self) weakSelf = self;
    [[self presentationController]
        beginSearchWithActiveTableView:[[self activeListViewController] tableView]
                            completion:^{
                              __strong typeof(weakSelf) strongSelf = weakSelf;
                              if (!strongSelf) {
                                  return;
                              }
                              [strongSelf performDeferredSearchTokenBootstrapIfNeeded];
                              [[strongSelf delegate] searchControllerDidFinishAnimatingSearchState:strongSelf];
                            }];
}

- (void)endSearchRestoringFrame:(BOOL)restoresFrame
                   clearsSearch:(BOOL)clearsSearch
                     animations:(void (^)(void))animations
                     completion:(void (^)(void))completion {
    [self endSearchRestoringFrame:restoresFrame
                     clearsSearch:clearsSearch
                       animations:animations
                     panVelocityY:0
                       completion:completion];
}

- (void)endSearchRestoringFrame:(BOOL)restoresFrame
                   clearsSearch:(BOOL)clearsSearch
                     animations:(void (^)(void))animations
                   panVelocityY:(CGFloat)panVelocityY
                     completion:(void (^)(void))completion {
    [self endSearchRestoringFrame:restoresFrame
                         clearsSearch:clearsSearch
                           animations:animations
                         panVelocityY:panVelocityY
        coordinatesVisibleSearchReset:NO
                           completion:completion];
}

- (void)finishDeferredVisibleSearchResetClearingSearch:(BOOL)clearsSearch {
    [self setSearchActive:NO];
    [self setSearchBarsShowCancelButton:NO animated:NO];
    if (clearsSearch) {
        [self clearSearchForListViewController:[self historyListViewController]];
        [self clearSearchForListViewController:[self favoritesListViewController]];
    }
    [self applySearchToActiveTableView];
    [[self presentationController] hideSearchBarInTableView:[self activeTableView] animated:NO];
    [self setIsResettingSearch:NO];
}

- (void)endSearchRestoringFrame:(BOOL)restoresFrame
                     clearsSearch:(BOOL)clearsSearch
                       animations:(void (^)(void))animations
                     panVelocityY:(CGFloat)panVelocityY
    coordinatesVisibleSearchReset:(BOOL)coordinatesVisibleSearchReset
                       completion:(void (^)(void))completion {
    [self cancelPendingTextSearch];
    if (![self isSearchActive] && !clearsSearch) {
        if (animations) {
            animations();
        }
        [self resetSearchSessionState];
        if (completion) {
            completion();
        }
        return;
    }

    BOOL defersVisibleSearchReset = coordinatesVisibleSearchReset && clearsSearch &&
                                    [self presentationMode] == MTPanelPresentationModeCompactLandscapeFullscreen;
    [self setDeferredSearchTokenBootstrapPending:NO];
    [self setIsResettingSearch:YES];
    [self setIsEndingSearchTransition:YES];
    UISearchBar *activeSearchBar = [self activeSearchBar];
    if (!defersVisibleSearchReset) {
        [self setSearchActive:NO];
    }
    [activeSearchBar resignFirstResponder];
    if (!defersVisibleSearchReset) {
        [self setSearchBarsShowCancelButton:NO animated:YES];
    }
    if (clearsSearch && !defersVisibleSearchReset) {
        [self clearSearchForListViewController:[self historyListViewController]];
        [self clearSearchForListViewController:[self favoritesListViewController]];
    }
    [[self presentationController] resetKeyboardInsets];
    if (!defersVisibleSearchReset) {
        [self applySearchToActiveTableView];
        [self setIsResettingSearch:NO];
    }

    [[self delegate] searchControllerWillAnimateSearchState:self];
    [[self presentationController]
        endSearchRestoringFrame:restoresFrame
                activeTableView:[[self activeListViewController] tableView]
                     animations:animations
                   panVelocityY:panVelocityY
                     completion:^{
                       if (defersVisibleSearchReset) {
                           [self finishDeferredVisibleSearchResetClearingSearch:clearsSearch];
                       }
                       [self resetSearchSessionState];
                       [self setIsEndingSearchTransition:NO];
                       [self updateSearchTokenHeaderHeights];
                       [[self delegate] searchControllerDidFinishAnimatingSearchState:self];
                       if (completion) {
                           completion();
                       }
                     }];
}

- (void)endSearchRestoringFrame:(BOOL)restoresFrame
                   clearsSearch:(BOOL)clearsSearch
                     completion:(void (^)(void))completion {
    [self endSearchRestoringFrame:restoresFrame clearsSearch:clearsSearch animations:nil completion:completion];
}

- (void)endSearchRestoringFrame:(BOOL)restoresFrame clearsSearch:(BOOL)clearsSearch {
    [self endSearchRestoringFrame:restoresFrame clearsSearch:clearsSearch completion:nil];
}

- (void)cancelSearchWithCompletion:(void (^)(void))completion {
    [self endSearchRestoringFrame:YES clearsSearch:YES completion:completion];
}

- (void)cancelSearchWithAnimations:(void (^)(void))animations completion:(void (^)(void))completion {
    [self endSearchRestoringFrame:YES clearsSearch:YES animations:animations completion:completion];
}

- (void)collapseSearchFromFullscreenPanWithVelocity:(CGFloat)velocityY {
    [self endSearchRestoringFrame:YES clearsSearch:YES animations:nil panVelocityY:velocityY completion:nil];
}

- (void)handleFullscreenPanGestureRecognizer:(UIPanGestureRecognizer *)recognizer
                                  headerView:(nullable MTHeaderView *)headerView {
    [[self presentationController] handleFullscreenPanGestureRecognizer:recognizer
                                                        activeTableView:[self activeTableView]
                                                             headerView:headerView];
}

- (CGRect)resetSearchStateRestoringContainerFrame:(BOOL)restoresContainerFrame {
    [self cancelPendingTextSearch];
    BOOL hasSearch =
        [[self historyListViewController] hasActiveSearch] || [[self favoritesListViewController] hasActiveSearch];
    if (![self isSearchActive] && !hasSearch) {
        [self resetSearchSessionState];
        return CGRectZero;
    }

    [self setIsResettingSearch:YES];
    [self setSearchActive:NO];
    [[self historySearchBar] resignFirstResponder];
    [[self favoritesSearchBar] resignFirstResponder];
    [self setSearchBarsShowCancelButton:NO animated:NO];
    [self clearSearchForListViewController:[self historyListViewController]];
    [self clearSearchForListViewController:[self favoritesListViewController]];
    [self applySearchToActiveTableView];
    CGRect normalFrame =
        [[self presentationController] resetAfterSearchStateClearedWithActiveTableView:[self activeTableView]
                                                                restoresContainerFrame:restoresContainerFrame];
    [self resetSearchSessionState];
    [self setIsResettingSearch:NO];
    return normalFrame;
}

- (void)resetSearchState {
    [self resetSearchStateRestoringContainerFrame:YES];
}

- (CGRect)resetSearchStatePreservingContainerFrame {
    return [self resetSearchStateRestoringContainerFrame:NO];
}

#pragma mark - Clearing

- (void)clearSearchForListViewController:(MTHistoryListViewController *)listViewController {
    UISearchBar *searchBar = [self searchBarForTableView:[listViewController tableView]];
    BOOL wasResettingSearch = [self isResettingSearch];
    [self setIsResettingSearch:YES];
    [searchBar setText:@""];
    [(UISearchTextField *)[searchBar searchTextField] setTokens:@[]];
    [self invalidatePendingSearchRequests];
    [listViewController clearSearch];
    [self updateTokenListForListViewController:listViewController];
    [self updateSearchTokenHeaderHeights];
    [self setIsResettingSearch:wasResettingSearch];
}

#pragma mark - MTSearchPresentationControllerDelegate

- (void)searchPresentationController:(MTSearchPresentationController *)controller
        didUpdateKeyboardBottomInset:(CGFloat)keyboardBottomInset {
    [[self delegate] searchController:self didUpdateKeyboardBottomInset:keyboardBottomInset];
}

- (void)searchPresentationController:(MTSearchPresentationController *)controller
    didRequestCollapseFromFullscreenPanWithVelocity:(CGFloat)velocityY {
    [self collapseSearchFromFullscreenPanWithVelocity:velocityY];
}

#pragma mark - MTSearchTokenListViewControllerDelegate

- (void)searchTokenListViewController:(MTSearchTokenListViewController *)controller
                       didSelectToken:(MTSearchToken *)token {
    MTHistoryListViewController *listViewController = controller == [self favoritesTokenListViewController]
                                                              ? [self favoritesListViewController]
                                                              : [self historyListViewController];
    if (listViewController != [self activeListViewController]) {
        return;
    }

    UISearchBar *searchBar = [self searchBarForTableView:[listViewController tableView]];
    MTSearchCriteria *baseCriteria =
        [[listViewController searchCriteria] criteriaByReplacingSearchText:[searchBar text]];
    MTSearchCriteria *criteria = [self criteria:baseCriteria hasActiveToken:token]
                                         ? [baseCriteria criteriaByRemovingToken:token]
                                         : [baseCriteria criteriaBySelectingToken:token];
    BOOL wasResettingSearch = [self isResettingSearch];
    [self setIsResettingSearch:YES];
    [self syncSearchTokensForSearchBar:searchBar criteria:criteria];
    [self setIsResettingSearch:wasResettingSearch];
    [self applySearchCriteria:criteria toListViewController:listViewController];
}

- (BOOL)criteria:(MTSearchCriteria *)criteria hasActiveToken:(MTSearchToken *)token {
    NSString *type = [token type];
    if ([type isEqualToString:kMTSearchTokenTypeCategory]) {
        return [[token value] isEqualToString:([criteria categoryValue] ?: @"")];
    }
    if ([type isEqualToString:kMTSearchTokenTypeApp]) {
        return [[token value] isEqualToString:([criteria appBundleIdentifier] ?: @"")];
    }
    return NO;
}

#pragma mark - Search Text Events

- (void)handleSearchTextFieldEditingChanged:(UITextField *)textField {
    UISearchBar *searchBar =
        textField == [[self favoritesSearchBar] searchTextField] ? [self favoritesSearchBar] : [self historySearchBar];
    [self scheduleTextSearchFromSearchBar:searchBar];
}

- (void)handleSearchTextFieldTextDidChangeNotification:(NSNotification *)notification {
    UITextField *textField = [notification object];
    UISearchBar *searchBar =
        textField == [[self favoritesSearchBar] searchTextField] ? [self favoritesSearchBar] : [self historySearchBar];
    [self scheduleTextSearchFromSearchBar:searchBar];
}

#pragma mark - UISearchBarDelegate

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
    if ([self listViewControllerForSearchBar:searchBar] == [self activeListViewController]) {
        [[self delegate] searchControllerWillBeginSearchInputTransition:self];
    }
    return YES;
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    if ([self listViewControllerForSearchBar:searchBar] != [self activeListViewController]) {
        return;
    }
    [self beginSearchIfNeeded];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    (void)searchText;
    [self scheduleTextSearchFromSearchBar:searchBar];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    if ([self listViewControllerForSearchBar:searchBar] != [self activeListViewController]) {
        return;
    }
    [self endSearchRestoringFrame:YES
                         clearsSearch:YES
                           animations:nil
                         panVelocityY:0
        coordinatesVisibleSearchReset:YES
                           completion:nil];
}

@end
