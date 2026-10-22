#import "MTPOpenAppPickerController.h"
#import "MTPAppInfo.h"
#import "AltList/LSApplicationProxy+AltList.h"
#import "common.h"

static NSBundle *mtpLocalBundle;
static NSString *const MTOpenAppCellIdentifier = @"MTOpenAppCell";

typedef NS_ENUM(NSInteger, MTOpenAppSection) {
    MTOpenAppSectionCurrent = 0,
    MTOpenAppSectionUser    = 1,
    MTOpenAppSectionSystem  = 2,
    MTOpenAppSectionCount   = 3,
};

// Plain table controller (PullOver-X QSFavoritesPickerController shape): the
// enumeration runs off the main thread behind a loading spinner, every proxy
// is classified by the vendored AltList predicates (applicationType string,
// hidden entries dropped), and search lives in the navigation bar. The
// configured app keeps a pinned top section so the checkmark anchor never
// disappears — a placeholder carrying the raw bundle ID holds the row for
// apps the filters no longer show. One MTPAppInfo is reported to the editor,
// which owns persistence.
@interface MTPOpenAppPickerController () <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray<MTPAppInfo *> *userApps;
@property (nonatomic, strong) NSArray<MTPAppInfo *> *systemApps;
@property (nonatomic, strong) MTPAppInfo *currentApp;
@property (nonatomic, strong) NSArray<MTPAppInfo *> *searchResults;
@property (nonatomic, assign) BOOL isSearching;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) NSUInteger loadGeneration;
// Batch mode: the pending picks keyed by bundle ID keep tap order and stay
// consistent across search filtering, which re-renders pools in new orders.
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *pendingBundleIDs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, MTPAppInfo *> *pendingApps;
@end

@implementation MTPOpenAppPickerController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    mtpLocalBundle = [NSBundle bundleWithPath:bundlePath];
    [mtpLocalBundle load];
    [super viewDidLoad];

    self.title = LOCALIZED(@"SELECT_APP");
    self.userApps = @[];
    self.systemApps = @[];
    self.searchResults = @[];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:MTOpenAppCellIdentifier];
    self.view = self.tableView;

    [self setupSearchController];
    [self startLoadingInstalledApps];
    if (self.allowsMultipleSelection) {
        self.pendingBundleIDs = [NSMutableOrderedSet orderedSet];
        self.pendingApps = [NSMutableDictionary dictionary];
        self.title = LOCALIZED(@"BATCH_ADD_APPLICATIONS");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"DONE")
                                                                                 style:UIBarButtonItemStyleDone
                                                                                target:self
                                                                                action:@selector(confirmMultiSelection)];
    }
}

// Checkmark source for both modes: the batch pending set or the single
// configured anchor.
- (BOOL)isAppSelected:(NSString *)bundleID {
    if (bundleID.length == 0) return NO;
    return self.allowsMultipleSelection
        ? [self.pendingBundleIDs containsObject:bundleID]
        : [bundleID isEqualToString:self.selectedBundleIdentifier];
}

// 完成 reports the picks in tap order and pops; an empty pick pops silently
// and the host treats it as a no-op.
- (void)confirmMultiSelection {
    if (self.multiSelectionCompletion) {
        NSMutableArray<MTPAppInfo *> *apps = [NSMutableArray array];
        for (NSString *bundleID in self.pendingBundleIDs) [apps addObject:self.pendingApps[bundleID]];
        self.multiSelectionCompletion(apps);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Data loading

// One background enumeration per push; the generation counter discards a
// stale completion if the controller outlives its first load. PullOver-X
// acquisition: a single -allApplications pass — classification never comes
// from the enumeration, each proxy is measured by the vendored AltList
// predicates (atl_isUserApplication / atl_isSystemApplication, which read
// applicationType and drop hidden entries).
- (void)startLoadingInstalledApps {
    NSUInteger generation = ++self.loadGeneration;
    self.isLoading = YES;
    [self showLoadingIndicator];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<MTPAppInfo *> *user = [NSMutableArray array];
        NSMutableArray<MTPAppInfo *> *system = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];

        @try {
            Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
            id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)]
                ? [workspaceClass defaultWorkspace] : nil;
            NSArray *installed = [workspace respondsToSelector:@selector(allApplications)]
                ? [workspace allApplications] : nil;

            for (LSApplicationProxy *proxy in installed) {
                NSString *bundleID = proxy.atl_bundleIdentifier;
                if (bundleID.length == 0 || [seen containsObject:bundleID]) continue;

                BOOL isUser = [proxy atl_isUserApplication];
                if (!isUser && ![proxy atl_isSystemApplication]) continue;
                [seen addObject:bundleID];

                MTPAppInfo *app = [[MTPAppInfo alloc] init];
                app.bundleID = bundleID;
                app.name = proxy.atl_nameToDisplay ?: bundleID;
                [(isUser ? user : system) addObject:app];
            }
        } @catch (NSException *exception) {
            NSLog(@"[MetisKeyboard] openapp picker: application enumeration failed (%@)", exception);
        }

        NSComparator byName = ^NSComparisonResult(MTPAppInfo *left, MTPAppInfo *right) {
            return [left.name localizedStandardCompare:right.name];
        };
        [user sortUsingComparator:byName];
        [system sortUsingComparator:byName];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || generation != strongSelf.loadGeneration) return;

            [strongSelf applyUserApps:user systemApps:system];
            NSLog(@"[MetisKeyboard] openapp picker: loaded %lu user, %lu system apps (current %@)",
                  (unsigned long)strongSelf.userApps.count, (unsigned long)strongSelf.systemApps.count,
                  strongSelf.currentApp.bundleID ?: @"none");
            strongSelf.isLoading = NO;
            strongSelf.tableView.backgroundView = nil;
            [strongSelf.tableView reloadData];
        });
    });
}

- (void)showLoadingIndicator {
    UIView *loadingView = [[UIView alloc] initWithFrame:CGRectZero];
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    indicator.color = [UIColor secondaryLabelColor];
    [indicator startAnimating];
    [loadingView addSubview:indicator];
    [NSLayoutConstraint activateConstraints:@[
        [indicator.centerXAnchor constraintEqualToAnchor:loadingView.centerXAnchor],
        [indicator.centerYAnchor constraintEqualToAnchor:loadingView.centerYAnchor],
    ]];
    self.tableView.backgroundView = loadingView;
}

// The configured app gets a dedicated pinned section even when the filters
// dropped it or it was uninstalled since — a placeholder carrying the raw
// bundle ID keeps the current value visible and re-selectable.
- (void)applyUserApps:(NSArray<MTPAppInfo *> *)user systemApps:(NSArray<MTPAppInfo *> *)system {
    NSMutableArray<MTPAppInfo *> *mutableUser = [user mutableCopy];
    NSMutableArray<MTPAppInfo *> *mutableSystem = [system mutableCopy];
    MTPAppInfo *current = nil;
    for (MTPAppInfo *app in [mutableUser arrayByAddingObjectsFromArray:mutableSystem]) {
        if ([app.bundleID isEqualToString:self.selectedBundleIdentifier]) {
            current = app;
            break;
        }
    }
    if (current) {
        if ([mutableUser containsObject:current]) [mutableUser removeObject:current];
        else [mutableSystem removeObject:current];
    } else if (self.selectedBundleIdentifier.length > 0) {
        current = [[MTPAppInfo alloc] init];
        current.bundleID = self.selectedBundleIdentifier;
        current.name = self.selectedBundleIdentifier;
    }

    self.currentApp = current;
    self.userApps = mutableUser;
    self.systemApps = mutableSystem;
}

#pragma mark - Search

- (void)setupSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    // no placeholder: the system-localized "Search" is used

    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

// The pinned Current section already shows the selection, so search matches
// against the User/System pools only.
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = [controller.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    self.isSearching = query.length > 0;

    if (self.isSearching) {
        NSMutableArray<MTPAppInfo *> *results = [NSMutableArray array];
        for (MTPAppInfo *app in [self.userApps arrayByAddingObjectsFromArray:self.systemApps]) {
            if ([app.name localizedCaseInsensitiveContainsString:query] ||
                [app.bundleID localizedCaseInsensitiveContainsString:query]) {
                [results addObject:app];
            }
        }
        self.searchResults = results;
    } else {
        self.searchResults = @[];
    }

    [self.tableView reloadData];
}

#pragma mark - Table view data source

- (MTPAppInfo *)appAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == MTOpenAppSectionCurrent) return self.currentApp;
    if (indexPath.section == MTOpenAppSectionUser) {
        NSArray<MTPAppInfo *> *pool = self.isSearching ? self.searchResults : self.userApps;
        return (indexPath.row < (NSInteger)pool.count) ? pool[indexPath.row] : nil;
    }
    if (indexPath.section == MTOpenAppSectionSystem) {
        return (indexPath.row < (NSInteger)self.systemApps.count) ? self.systemApps[indexPath.row] : nil;
    }
    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.isLoading) return 0;
    return self.isSearching ? 2 : MTOpenAppSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case MTOpenAppSectionCurrent:
            return self.currentApp ? 1 : 0;
        case MTOpenAppSectionUser:
            return self.isSearching ? self.searchResults.count : self.userApps.count;
        case MTOpenAppSectionSystem:
            return self.isSearching ? 0 : self.systemApps.count;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.isLoading) return nil;
    if (self.isSearching) return nil;
    switch (section) {
        case MTOpenAppSectionCurrent:
            return nil; // pinned selection row, self-evident at the top
        case MTOpenAppSectionUser:
            return LOCALIZED(@"User Applications");
        case MTOpenAppSectionSystem:
            return LOCALIZED(@"System Applications");
        default:
            return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return 52.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // The registered cell class means dequeue never returns nil; the fixed
    // row content is therefore applied on every pass, not at creation.
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MTOpenAppCellIdentifier forIndexPath:indexPath];

    MTPAppInfo *app = [self appAtIndexPath:indexPath];
    cell.imageView.layer.cornerRadius = 8.0;
    cell.imageView.layer.masksToBounds = YES;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];

    cell.textLabel.text = app.name;
    cell.detailTextLabel.text = app.bundleID;
    cell.imageView.image = app ? [MTPAppInfo iconForBundleID:app.bundleID] : nil;
    cell.accessoryType = [self isAppSelected:app.bundleID]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    MTPAppInfo *app = [self appAtIndexPath:indexPath];
    if (!app) return;

    if (self.allowsMultipleSelection) {
        NSString *bundleID = app.bundleID;
        if (bundleID.length == 0) return;
        BOOL selected;
        if ([self.pendingBundleIDs containsObject:bundleID]) {
            [self.pendingBundleIDs removeObject:bundleID];
            [self.pendingApps removeObjectForKey:bundleID];
            selected = NO;
        } else {
            [self.pendingBundleIDs addObject:bundleID];
            self.pendingApps[bundleID] = app;
            selected = YES;
        }
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return;
    }

    self.selectedBundleIdentifier = app.bundleID;
    if (self.completion) self.completion(app);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
