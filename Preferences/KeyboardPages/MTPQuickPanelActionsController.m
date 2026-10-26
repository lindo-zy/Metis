#import "MTPQuickPanelActionsController.h"
#import "MTQuickPanelActions.h"
#import "MTHelper.h"
#import "common.h"

static NSString *MTQPA(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}

@interface MTPQuickPanelActionPicker : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, copy) NSArray<NSDictionary *> *definitions;
@property(nonatomic, copy) NSArray<NSDictionary *> *filtered;
@property(nonatomic, copy) NSString *selectedSelector;
@property(nonatomic, copy) void (^completion)(NSString *);
@property(nonatomic, strong) UISearchController *search;
@end
@implementation MTPQuickPanelActionPicker
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTQPA(@"QUICK_ACTION_CHOOSE");
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.obscuresBackgroundDuringPresentation = NO; self.search.searchResultsUpdater = self;
    self.navigationItem.searchController = self.search; self.definesPresentationContext = YES;
    self.filtered = self.definitions;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = [controller.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.filtered = query.length ? [self.definitions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
        NSString *name = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : @"";
        return [name localizedStandardContainsString:query];
    }]] : self.definitions;
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : self.filtered.count; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return section == 1 ? MTQPA(@"CUSTOM_ACTIONS") : nil; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { return section == 1 ? MTQPA(@"QUICK_ACTION_PICKER_FOOTER") : nil; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSDictionary *entry = path.section == 1 ? self.filtered[path.row] : nil;
    BOOL allowed = !entry || MTGlobalCustomActionSupported(entry);
    NSString *selector = entry ? entry[@"selector"] : @"";
    cell.textLabel.text = entry ? entry[@"name"] : MTQPA(@"QUICK_ACTION_NONE");
    cell.imageView.image = entry ? [MTHelper imageForCustomActionEntry:entry] : [UIImage systemImageNamed:@"minus.circle"];
    cell.imageView.tintColor = UIColor.systemBlueColor;
    cell.detailTextLabel.text = allowed ? nil : MTQPA(@"QUICK_ACTION_UNAVAILABLE");
    cell.textLabel.textColor = allowed ? UIColor.labelColor : UIColor.secondaryLabelColor;
    cell.selectionStyle = allowed ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    cell.accessoryType = [selector isEqual:self.selectedSelector ?: @""] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    if (!allowed) cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    NSDictionary *entry = path.section == 1 ? self.filtered[path.row] : nil;
    if (entry && !MTGlobalCustomActionSupported(entry)) return;
    if (self.completion) self.completion(entry ? entry[@"selector"] : @"");
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface MTPQuickPanelActionsController ()
@property(nonatomic, strong) UITableView *tableView;
@end
@implementation MTPQuickPanelActionsController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = MTQPA(@"QUICK_ACTIONS");
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self; self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = self.tableView;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; [MTPrefsManager.sharedInstance reload]; [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return 4; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { return MTQPA(@"QUICK_ACTIONS_FOOTER"); }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *prefs = MTPrefsManager.sharedInstance.readPrefs;
    NSArray *slots = MTQuickPanelActionSlots(prefs);
    NSDictionary *entry = MTQuickPanelActionDefinition(prefs[kLinkActionskey], slots[path.row]);
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = [NSString stringWithFormat:MTQPA(@"QUICK_ACTION_SLOT"), (long)path.row + 1];
    cell.detailTextLabel.text = entry ? entry[@"name"] : MTQPA(@"QUICK_ACTION_NONE");
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    NSDictionary *prefs = MTPrefsManager.sharedInstance.readPrefs;
    id raw = prefs[kLinkActionskey];
    NSMutableArray *definitions = [NSMutableArray array];
    for (id entry in [raw isKindOfClass:NSArray.class] ? raw : @[]) {
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isKindOfClass:NSString.class]) [definitions addObject:entry];
    }
    MTPQuickPanelActionPicker *picker = [[MTPQuickPanelActionPicker alloc] initWithStyle:UITableViewStyleInsetGrouped];
    picker.definitions = definitions; picker.selectedSelector = MTQuickPanelActionSlots(prefs)[path.row];
    NSUInteger slot = path.row;
    picker.completion = ^(NSString *selector) {
        MTPrefsManager *manager = MTPrefsManager.sharedInstance; [manager reload];
        NSMutableDictionary *live = [manager.readPrefs mutableCopy];
        if (!live) return;
        if (selector.length && !MTGlobalCustomActionSupported(MTQuickPanelActionDefinition(live[kLinkActionskey], selector))) return;
        NSMutableArray *slots = [MTQuickPanelActionSlots(live) mutableCopy]; slots[slot] = selector;
        live[kKbdLauncherActionsKey] = slots; [manager writePrefs:live];
    };
    [self.navigationController pushViewController:picker animated:YES];
}
@end
