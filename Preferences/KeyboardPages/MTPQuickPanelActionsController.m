#import "MTPQuickPanelActionsController.h"
#import "MTQuickPanelActions.h"
#import "MTHelper.h"
#import "MTPLinkActionEditorController.h"
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
// 就地新建动作后待回传的 selector：编辑器保存回调触发时编辑器仍在弹栈，
// completion 与 pop 延迟到本页 viewDidAppear 再执行，避免压栈竞态。
@property(nonatomic, copy) NSString *pendingCreatedSelector;
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
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 从编辑器返回时新动作已在库中：与宿主同规则重建定义列表。
    [self reloadDefinitionsFromPrefs];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.pendingCreatedSelector.length == 0) return;
    NSString *selector = self.pendingCreatedSelector;
    self.pendingCreatedSelector = nil;
    if (self.completion) self.completion(selector);
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)reloadDefinitionsFromPrefs {
    NSMutableArray *definitions = [NSMutableArray array];
    id raw = MTPrefsManager.sharedInstance.readPrefs[kLinkActionskey];
    for (id entry in [raw isKindOfClass:NSArray.class] ? raw : @[]) {
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isKindOfClass:NSString.class]) [definitions addObject:entry];
    }
    self.definitions = definitions;
    [self updateSearchResultsForSearchController:self.search];
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
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : self.filtered.count + 1; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return section == 1 ? MTQPA(@"CUSTOM_ACTIONS") : nil; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { return section == 1 ? MTQPA(@"QUICK_ACTION_PICKER_FOOTER") : nil; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (path.section == 1 && path.row == (NSInteger)self.filtered.count) {
        cell.textLabel.text = MTQPA(@"ADD");
        cell.textLabel.textColor = UIColor.systemBlueColor;
        cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.imageView.tintColor = UIColor.systemGreenColor;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
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
    if (path.section == 1 && path.row == (NSInteger)self.filtered.count) {
        [self presentAddActionTypeChooser];
        return;
    }
    NSDictionary *entry = path.section == 1 ? self.filtered[path.row] : nil;
    if (entry && !MTGlobalCustomActionSupported(entry)) return;
    if (self.completion) self.completion(entry ? entry[@"selector"] : @"");
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Add flow

// 类型集与草稿构造统一在编辑器类方法（免输入框四类，与其他入口同形）。
- (void)presentAddActionTypeChooser {
    __weak typeof(self) weakSelf = self;
    [MTPLinkActionEditorController presentGloballyExecutableTypeChooserFromController:self
        message:nil
        completion:^(NSString *type) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && type.length) [strongSelf startAddFlowForType:type];
        }];
}

- (void)startAddFlowForType:(NSString *)type {
    NSMutableDictionary *entry = [MTPLinkActionEditorController draftEntryForType:type];
    if (!entry) return;
    MTPLinkActionEditorController *editor = [[MTPLinkActionEditorController alloc] init];
    editor.entry = entry;
    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSDictionary *savedEntry) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![savedEntry isKindOfClass:NSDictionary.class]) return;
        MTPrefsManager *manager = MTPrefsManager.sharedInstance;
        NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
        if (!preferences) return;
        NSMutableArray *definitions = [preferences[kLinkActionskey] isKindOfClass:NSArray.class] ?
            [preferences[kLinkActionskey] mutableCopy] : [NSMutableArray array];
        [definitions addObject:savedEntry]; preferences[kLinkActionskey] = definitions;
        [manager writePrefs:preferences];
        // 保存的条目不满足快速面板执行要求（如未配置完整）时不自动绑定，
        // 留在本页让用户继续挑选；动作本身已进全局库。
        if (MTGlobalCustomActionSupported(savedEntry)) strongSelf.pendingCreatedSelector = savedEntry[@"selector"];
    };
    [self.navigationController pushViewController:editor animated:YES];
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
