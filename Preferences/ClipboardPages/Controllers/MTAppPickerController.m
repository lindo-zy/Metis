//
//  MTAppPickerController.m
//  Mt
//

#import "MTAppPickerController.h"

#import "MTAppInfo.h"

// Section layout mirrors the PullOver-X favorites picker: the editor's current
// app on top, then all installed apps split by LaunchServices type. Searching
// collapses everything into one flat result section.
typedef NS_ENUM(NSInteger, MTAppPickerSection) {
    MTAppPickerSectionSelected = 0,
    MTAppPickerSectionUser = 1,
    MTAppPickerSectionSystem = 2
};

@interface MTAppPickerController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, copy) NSString *searchText;
@property(nonatomic, copy) NSArray<MTAppInfo *> *userApps;
@property(nonatomic, copy) NSArray<MTAppInfo *> *systemApps;
@property(nonatomic, copy) NSArray<MTAppInfo *> *searchResults;
@property(nonatomic, strong) NSBundle *localizationBundle;
@property(nonatomic, assign, getter=isLoadingApps) BOOL loadingApps;
// Guards against a stale background enumeration repopulating a picker that
// was already reloaded (LaunchServices can be slow on a cold start).
@property(nonatomic, assign) NSUInteger loadGeneration;
@end

// Subtitle style: app name on top, bundle identifier underneath.
@interface MTAppPickerCell : UITableViewCell
@end

@implementation MTAppPickerCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
}
@end

@implementation MTAppPickerController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _localizationBundle = [NSBundle bundleForClass:[self class]];
        _userApps = @[];
        _systemApps = @[];
        _searchResults = @[];
        _loadingApps = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [[self view] setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
    [self setTitle:[self localizedStringForKey:@"Select App"]];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView registerClass:[MTAppPickerCell class] forCellReuseIdentifier:@"MTAppPickerCell"];
    [[self view] addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [[_tableView topAnchor] constraintEqualToAnchor:[[self view] topAnchor]],
        [[_tableView leadingAnchor] constraintEqualToAnchor:[[self view] leadingAnchor]],
        [[_tableView trailingAnchor] constraintEqualToAnchor:[[self view] trailingAnchor]],
        [[_tableView bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]]
    ]];
    [self installLoadingIndicator];

    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    [_searchController setSearchResultsUpdater:self];
    [_searchController setObscuresBackgroundDuringPresentation:NO];
    [_searchController setDefinesPresentationContext:YES];
    [[_searchController searchBar] setPlaceholder:[self localizedStringForKey:@"Search"]];
    [[self navigationItem] setSearchController:_searchController];
    [[self navigationItem] setHidesSearchBarWhenScrolling:NO];

    [self startLoadingApps];
}

#pragma mark - Loading

// Enumeration blocks while LaunchServices is cold, so the spinner takes over
// the table until the background pass delivers.
- (void)installLoadingIndicator {
    UIView *loadingView = [[UIView alloc] initWithFrame:CGRectZero];
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [indicator setTranslatesAutoresizingMaskIntoConstraints:NO];
    [indicator setColor:[UIColor secondaryLabelColor]];
    [loadingView addSubview:indicator];
    [NSLayoutConstraint activateConstraints:@[
        [[indicator centerXAnchor] constraintEqualToAnchor:[loadingView centerXAnchor]],
        [[indicator centerYAnchor] constraintEqualToAnchor:[loadingView centerYAnchor]]
    ]];
    [indicator startAnimating];
    [self setLoadingIndicator:indicator];
    [[self tableView] setBackgroundView:loadingView];
}

- (void)startLoadingApps {
    NSUInteger generation = ++self.loadGeneration;
    [self setLoadingApps:YES];
    [[self loadingIndicator] startAnimating];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSArray<MTAppInfo *> *apps = [MTAppInfo installedApps];
      NSMutableArray<MTAppInfo *> *userApps = [NSMutableArray array];
      NSMutableArray<MTAppInfo *> *systemApps = [NSMutableArray array];
      for (MTAppInfo *app in apps) {
          if ([app isUserApp]) {
              [userApps addObject:app];
          } else {
              [systemApps addObject:app];
          }
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || generation != [strongSelf loadGeneration]) return;
        [strongSelf setUserApps:userApps];
        [strongSelf setSystemApps:systemApps];
        [strongSelf setLoadingApps:NO];
        [[strongSelf loadingIndicator] stopAnimating];
        [[strongSelf tableView] setBackgroundView:nil];
        [strongSelf setLoadingIndicator:nil];
        [[strongSelf tableView] reloadData];
      });
    });
}

#pragma mark - Data

- (NSArray<MTAppInfo *> *)selectedApps {
    NSString *currentBundleID = [self currentBundleID];
    if ([currentBundleID length] == 0) {
        return @[];
    }
    NSMutableArray<MTAppInfo *> *result = [NSMutableArray array];
    for (MTAppInfo *app in [self userApps]) {
        if ([[app bundleID] isEqualToString:currentBundleID]) [result addObject:app];
    }
    for (MTAppInfo *app in [self systemApps]) {
        if ([[app bundleID] isEqualToString:currentBundleID]) [result addObject:app];
    }
    return result;
}

- (NSArray<MTAppInfo *> *)arrayForSection:(NSInteger)section {
    if ([self isSearching]) {
        return [self searchResults];
    }
    if ([[self selectedApps] count] > 0) {
        if (section == MTAppPickerSectionSelected) return [self selectedApps];
        if (section == MTAppPickerSectionUser) return [self userApps];
        return [self systemApps];
    }
    if (section == MTAppPickerSectionUser - 1) return [self userApps];
    return [self systemApps];
}

- (MTAppInfo *)appForIndexPath:(NSIndexPath *)indexPath {
    NSArray<MTAppInfo *> *array = [self arrayForSection:[indexPath section]];
    NSUInteger row = (NSUInteger)[indexPath row];
    return row < [array count] ? array[row] : nil;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    if ([self isLoadingApps]) {
        return 0;
    }
    if ([self isSearching]) {
        return 1;
    }
    return [[self selectedApps] count] > 0 ? 3 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if ([self isLoadingApps] || [self isSearching]) {
        return nil;
    }
    if ([[self selectedApps] count] > 0) {
        if (section == MTAppPickerSectionSelected) return [self localizedStringForKey:@"Selected"];
        if (section == MTAppPickerSectionUser) return [self localizedStringForKey:@"User Apps"];
        return [self localizedStringForKey:@"System Apps"];
    }
    if (section == MTAppPickerSectionUser - 1) return [self localizedStringForKey:@"User Apps"];
    return [self localizedStringForKey:@"System Apps"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)[[self arrayForSection:section] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return 60.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MTAppPickerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MTAppPickerCell"
                                                              forIndexPath:indexPath];
    MTAppInfo *app = [self appForIndexPath:indexPath];
    if (!app) {
        [[cell textLabel] setText:nil];
        [[cell detailTextLabel] setText:nil];
        [[cell imageView] setImage:nil];
        return cell;
    }
    [[cell textLabel] setText:[app name]];
    [[cell detailTextLabel] setText:[app bundleID]];
    [[cell detailTextLabel] setTextColor:[UIColor secondaryLabelColor]];
    [[cell detailTextLabel] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [[cell imageView] setImage:[MTAppInfo iconForBundleID:[app bundleID]]];
    [cell setAccessoryType:[[app bundleID] isEqualToString:[self currentBundleID]]
                               ? UITableViewCellAccessoryCheckmark
                               : UITableViewCellAccessoryNone];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    MTAppInfo *app = [self appForIndexPath:indexPath];
    if (!app) {
        return;
    }
    void (^completionHandler)(NSString *, NSString *) = [self completionHandler];
    if (completionHandler) {
        completionHandler([app name], [app bundleID]);
    }
    [[self navigationController] popViewControllerAnimated:YES];
}

#pragma mark - Search

- (BOOL)isSearching {
    return [[[self searchText] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        length] > 0;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self setSearchText:[[searchController searchBar] text]];

    NSString *query = [[self searchText] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<MTAppInfo *> *results = [NSMutableArray array];
    if ([query length] > 0) {
        for (MTAppInfo *app in [self userApps]) {
            if ([self app:app matchesQuery:query]) [results addObject:app];
        }
        for (MTAppInfo *app in [self systemApps]) {
            if ([self app:app matchesQuery:query]) [results addObject:app];
        }
    }
    [self setSearchResults:results];
    [[self tableView] reloadData];
}

- (BOOL)app:(MTAppInfo *)app matchesQuery:(NSString *)query {
    return [[app name] localizedCaseInsensitiveContainsString:query] ||
           [[app bundleID] localizedCaseInsensitiveContainsString:query];
}

#pragma mark - Localization

- (NSString *)localizedStringForKey:(NSString *)key {
    return [[self localizationBundle] localizedStringForKey:key value:key table:@"CustomJumps"] ?: key;
}

@end
