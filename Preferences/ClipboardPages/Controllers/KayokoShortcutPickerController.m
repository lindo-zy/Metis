//
//  KayokoShortcutPickerController.m
//  Kayoko
//

#import "KayokoShortcutPickerController.h"

#import "KayokoAppInfo.h"
#import "KayokoShortcutCatalog.h"

static void KayokoShortcutSnapshotChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                  const void *object, CFDictionaryRef userInfo);

@interface KayokoShortcutPickerController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, copy) NSString *searchText;
@property(nonatomic, copy) NSArray<NSDictionary *> *groups;
@property(nonatomic, strong) NSBundle *localizationBundle;
@property(nonatomic, assign) BOOL didRequestSnapshotRefresh;
@end

// Subtitle style: localized quick action title on top, its
// UIApplicationShortcutItemType (the identifier the system dispatches)
// underneath.
@interface KayokoShortcutPickerCell : UITableViewCell
@end

@implementation KayokoShortcutPickerCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
}
@end

@implementation KayokoShortcutPickerController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _localizationBundle = [NSBundle bundleForClass:[self class]];
        _groups = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [[self view] setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
    [self setTitle:[self localizedStringForKey:@"Select Shortcut"]];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                    KayokoShortcutSnapshotChangedCallback,
                                    (__bridge CFStringRef)kKayokoShortcutDarwinNotificationSnapshotChanged, NULL,
                                    (CFNotificationSuspensionBehavior)CFNotificationSuspensionBehaviorDeliverImmediately);

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView registerClass:[KayokoShortcutPickerCell class] forCellReuseIdentifier:@"KayokoShortcutPickerCell"];
    [[self view] addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [[_tableView topAnchor] constraintEqualToAnchor:[[self view] topAnchor]],
        [[_tableView leadingAnchor] constraintEqualToAnchor:[[self view] leadingAnchor]],
        [[_tableView trailingAnchor] constraintEqualToAnchor:[[self view] trailingAnchor]],
        [[_tableView bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]]
    ]];

    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    [_searchController setSearchResultsUpdater:self];
    [_searchController setObscuresBackgroundDuringPresentation:NO];
    [_searchController setDefinesPresentationContext:YES];
    [[_searchController searchBar] setPlaceholder:[self localizedStringForKey:@"Search"]];
    [[self navigationItem] setSearchController:_searchController];
    [[self navigationItem] setHidesSearchBarWhenScrolling:NO];

    [self loadGroups];
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                       (__bridge CFStringRef)kKayokoShortcutDarwinNotificationSnapshotChanged, NULL);
}

- (void)loadGroups {
    __weak typeof(self) weakSelf = self;
    // The catalogue is one small shared plist authored by SpringBoard: a
    // plain read that renders immediately and refreshes on the Darwin change
    // notification after each catalogue rebuild.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSArray<NSDictionary *> *groups = [KayokoShortcutCatalog displayGroups];
      NSArray<KayokoAppInfo *> *installedApps = [KayokoAppInfo installedApps];
      NSMutableArray<NSString *> *bundleIdentifiers = [NSMutableArray arrayWithCapacity:[installedApps count]];
      for (KayokoAppInfo *app in installedApps) {
          if ([[app bundleID] length] > 0) {
              [bundleIdentifiers addObject:[app bundleID]];
          }
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf setGroups:groups];
        [[strongSelf tableView] reloadData];
        [strongSelf updateFooter];
        [strongSelf requestSpringBoardSnapshotRefreshIfNeededWithBundleIdentifiers:bundleIdentifiers];
      });
    });
}

// SpringBoard composes the real long-press menu and is the only process with
// reliable access to it: request one full catalogue refresh after the first
// paint. The snapshot (and a Darwin notification) comes back asynchronously.
- (void)requestSpringBoardSnapshotRefreshIfNeededWithBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers {
    if ([self didRequestSnapshotRefresh]) {
        return;
    }
    [self setDidRequestSnapshotRefresh:YES];
    [KayokoShortcutCatalog requestSnapshotRefreshForBundleIdentifiers:bundleIdentifiers];
}

// Searching keeps groups whose app name/bundle identifier matches with all
// their items; a title/type match shows the group with only the matching
// items.
- (NSArray<NSDictionary *> *)filteredGroups {
    NSString *searchText = [self searchText] ?: @"";
    NSString *query = [searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([query length] == 0) {
        return [self groups];
    }

    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *group in [self groups]) {
        NSString *name = [group isKindOfClass:[NSDictionary class]] ? (group[@"name"] ?: @"") : @"";
        NSString *bundleID = [group isKindOfClass:[NSDictionary class]] ? (group[@"bundleID"] ?: @"") : @"";
        if ([name localizedCaseInsensitiveContainsString:query] || [bundleID localizedCaseInsensitiveContainsString:query]) {
            [result addObject:group];
            continue;
        }
        NSMutableArray<KayokoShortcutItem *> *matches = [NSMutableArray array];
        for (KayokoShortcutItem *item in group[@"items"]) {
            if ([[item title] localizedCaseInsensitiveContainsString:query] ||
                [[item type] localizedCaseInsensitiveContainsString:query]) {
                [matches addObject:item];
            }
        }
        if ([matches count] > 0) {
            [result addObject:@{ @"name" : name, @"bundleID" : bundleID, @"items" : [matches copy] }];
        }
    }
    return result;
}

- (NSDictionary *)groupForSection:(NSInteger)section {
    NSArray<NSDictionary *> *groups = [self filteredGroups];
    if (section < 0 || section >= (NSInteger)[groups count]) {
        return @{};
    }
    NSDictionary *group = groups[(NSUInteger)section];
    return [group isKindOfClass:[NSDictionary class]] ? group : @{};
}

- (NSArray<KayokoShortcutItem *> *)itemsForSection:(NSInteger)section {
    NSArray *items = [self groupForSection:section][@"items"];
    return [items isKindOfClass:[NSArray class]] ? items : @[];
}

- (KayokoShortcutItem *)itemForIndexPath:(NSIndexPath *)indexPath {
    NSArray<KayokoShortcutItem *> *items = [self itemsForSection:[indexPath section]];
    if ((NSUInteger)[indexPath row] >= [items count]) {
        return nil;
    }
    return items[(NSUInteger)[indexPath row]];
}

// Explains what the page lists and doubles as the empty-state message: the
// catalogue is authored by SpringBoard in the background, so a just-opened
// empty state is a building one, not a broken one.
- (void)updateFooter {
    NSString *text = [[self filteredGroups] count] > 0 ? [self localizedStringForKey:@"Shortcuts Footer"]
                                                       : [self localizedStringForKey:@"No App Shortcuts"];

    CGFloat width = CGRectGetWidth([[self tableView] bounds]) - 40.0;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 8.0, MAX(width, 40.0), 40.0)];
    [label setText:text];
    [label setFont:[UIFont systemFontOfSize:13.0]];
    [label setTextColor:[UIColor secondaryLabelColor]];
    [label setTextAlignment:NSTextAlignmentCenter];
    [label setNumberOfLines:0];
    CGFloat height = [label sizeThatFits:CGSizeMake(MAX(width, 40.0), CGFLOAT_MAX)].height + 8.0;
    [label setFrame:CGRectMake(20.0, 8.0, MAX(width, 40.0), height)];
    [[self tableView] setTableFooterView:label];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)[[self filteredGroups] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [self groupForSection:section][@"name"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return [self groupForSection:section][@"bundleID"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)[[self itemsForSection:section] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return 60.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    KayokoShortcutPickerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"KayokoShortcutPickerCell"
                                                                    forIndexPath:indexPath];
    KayokoShortcutItem *item = [self itemForIndexPath:indexPath];
    if (item) {
        [[cell textLabel] setText:[item title] ?: [item type]];
        NSString *source =
            [item isDynamic] ? [self localizedStringForKey:@"Shortcut Source Dynamic"]
                             : [self localizedStringForKey:@"Shortcut Source Static"];
        [[cell detailTextLabel] setText:[[item type] length] > 0
            ? [NSString stringWithFormat:@"%@ · %@", [item type], source]
            : source];
    } else {
        [[cell textLabel] setText:nil];
        [[cell detailTextLabel] setText:nil];
    }
    [[cell detailTextLabel] setTextColor:[UIColor secondaryLabelColor]];
    [[cell detailTextLabel] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [[cell imageView] setImage:[KayokoAppInfo iconForBundleID:[self groupForSection:[indexPath section]][@"bundleID"]]];

    BOOL isSelected = [[item type] isKindOfClass:[NSString class]] && [[item type] isEqualToString:[self currentType]] &&
                      [[self groupForSection:[indexPath section]][@"bundleID"] isEqualToString:[self currentBundleID]];
    [cell setAccessoryType:isSelected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    KayokoShortcutItem *item = [self itemForIndexPath:indexPath];
    if (![item isKindOfClass:[KayokoShortcutItem class]] || [[item type] length] == 0) {
        return;
    }
    NSString *bundleID = [self groupForSection:[indexPath section]][@"bundleID"];
    if (![bundleID isKindOfClass:[NSString class]] || [bundleID length] == 0) {
        return;
    }

    void (^completionHandler)(NSString *, NSString *, NSString *) = [self completionHandler];
    if (completionHandler) {
        completionHandler([item title] ?: [item type], bundleID, [item type]);
    }
    [[self navigationController] popViewControllerAnimated:YES];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self setSearchText:[[searchController searchBar] text]];
    [[self tableView] reloadData];
    [self updateFooter];
}

#pragma mark - Localization

- (NSString *)localizedStringForKey:(NSString *)key {
    return [[self localizationBundle] localizedStringForKey:key value:key table:@"CustomJumps"] ?: key;
}

@end

static void KayokoShortcutSnapshotChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                  const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)name;
    (void)object;
    (void)userInfo;
    KayokoShortcutPickerController *controller = (__bridge KayokoShortcutPickerController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
      [controller loadGroups];
    });
}
