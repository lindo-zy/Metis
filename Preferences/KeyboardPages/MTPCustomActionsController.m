#import "MTPCustomActionsController.h"
#import "MTPNewActionTypeController.h"
#import "MTPLinkActionEditorController.h"
#import "MTPAppInfo.h"
#import "MTPBatchOpenAppEntries.h"
#import "MTPActionGroups.h"
#import "MTPActionOrganizationController.h"
#import "MTPOpenAppPickerController.h"
#import "MTHelper.h"
#import "common.h"
#import <objc/runtime.h>

static NSBundle *mtpLocalBundle;
@interface MTPManagedActionCell : UITableViewCell
@end
@implementation MTPManagedActionCell
// Registered via registerClass, which would otherwise build a Default-style
// cell; force Subtitle so the detail line (link / type) exists.
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    CGRect frame = self.imageView.frame;
    frame.origin.y = roundf((CGRectGetHeight(self.contentView.bounds) - frame.size.height) / 2.0);
    self.imageView.frame = frame;
}
@end

// Register on the rendering table itself, once per instance. The base table
// is configured before its data source is attached; this also protects any
// additional table that asks the controller to render a cell.
static char kMTManagedCellsRegisteredKey;
static void MTRegisterManagedCellsIfNeeded(UITableView *table) {
    if (!table || objc_getAssociatedObject(table, &kMTManagedCellsRegisteredKey)) return;
    [table registerClass:[MTPManagedActionCell class] forCellReuseIdentifier:@"MTPManagedActionCell"];
    [table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"MTPManagedEmptyCell"];
    objc_setAssociatedObject(table, &kMTManagedCellsRegisteredKey, @YES, OBJC_ASSOCIATION_RETAIN);
}


@interface MTPCustomActionsController ()
@property(nonatomic, copy) NSArray<NSString *> *groupNames;
@property(nonatomic, copy) NSArray<NSArray<NSNumber *> *> *groupIndexes;
@property(nonatomic, copy) NSArray<NSNumber *> *searchIndexes;
@property(nonatomic) BOOL isSearching;
@property(nonatomic) BOOL selectingActions;
@property(nonatomic) BOOL sortingActions;
@property(nonatomic, strong) NSMutableSet<NSString *> *batchSelectors;
@property(nonatomic, copy) NSString *filterSignature;
@end

@implementation MTPCustomActionsController
- (void)viewDidLoad {
    mtpLocalBundle = [NSBundle bundleWithPath:bundlePath];
    [mtpLocalBundle load];
    self.customActionsOnly = YES;
    self.selectionManagedExternally = YES;
    [super viewDidLoad];
    self.title = LOCALIZED(@"CUSTOM_ACTIONS");
    [self configureActionSearch];
    [self updateControls];
    NSLog(@"[MetisKeyboard][CustomActions] load actions=%lu groups=%lu",
        (unsigned long)self.linkActions.count, (unsigned long)self.groupNames.count);
}
- (void)configureActionTableView:(UITableView *)tableView {
    MTRegisterManagedCellsIfNeeded(tableView);
    tableView.allowsSelectionDuringEditing = YES;
}
- (void)reloadPreferences {
    [super reloadPreferences];
    [self refreshSections];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateControls];
    [self.navigationController setToolbarHidden:NO animated:animated];
}
- (void)refreshSections {
    if (!self.batchSelectors) self.batchSelectors = [NSMutableSet set];
    self.groupNames = MTActionGroupNames(self.prefs, self.linkActions);
    self.groupIndexes = MTActionGroupSectionIndexes(self.linkActions, self.groupNames);
    self.searchIndexes = MTActionFilteredIndexes(self.linkActions, self.actionQuery, self.actionTypeFilter,
        ^NSString *(NSDictionary *entry) { return [MTPLinkActionEditorController displayNameForType:MTActionDisplayType(entry)]; });
    self.isSearching = [self.actionQuery stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length || self.actionTypeFilter.length;
    NSMutableSet *live = [NSMutableSet set];
    for (NSDictionary *entry in self.linkActions) [live addObject:entry[@"selector"]];
    [self.batchSelectors intersectSet:live];
}
- (void)reloadDataKeepingSelection {
    [self refreshSections];
    [self.tableView reloadData];
    [self updateControls];
}
- (void)linkActionListDidChange { [self reloadDataKeepingSelection]; }
- (void)linkActionRowDidUpdate:(NSInteger)row { [self reloadDataKeepingSelection]; }
- (void)actionFilterDidChange {
    NSString *signature = [NSString stringWithFormat:@"%@|%@", self.actionQuery ?: @"", self.actionTypeFilter ?: @""];
    if (![self.filterSignature isEqual:signature]) {
        [self.batchSelectors removeAllObjects];
        self.sortingActions = NO;
        [self.tableView setEditing:NO animated:NO];
    }
    self.filterSignature = signature;
    [self reloadDataKeepingSelection];
}
- (NSInteger)ungroupedSection { return self.groupNames.count; }
- (NSString *)groupAtSection:(NSInteger)section {
    return section >= 0 && section < (NSInteger)self.groupNames.count ? self.groupNames[section] : @"";
}
- (NSInteger)globalIndexAtIndexPath:(NSIndexPath *)path {
    if (!path || path.row < 0 || path.section < 0) return NSNotFound;
    NSArray *indexes = self.isSearching ? (path.section == 0 ? self.searchIndexes : nil) :
        (path.section < (NSInteger)self.groupIndexes.count ? self.groupIndexes[path.section] : nil);
    if (path.row >= (NSInteger)indexes.count) return NSNotFound;
    NSInteger global = [indexes[path.row] integerValue];
    return global >= 0 && global < (NSInteger)self.linkActions.count ? global : NSNotFound;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.isSearching ? 1 : self.groupIndexes.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isSearching) return MAX(1, (NSInteger)self.searchIndexes.count);
    if (section < 0 || section >= (NSInteger)self.groupIndexes.count) return 0;
    if ([MTActionCollapsedGroups(self.prefs) containsObject:[self groupAtSection:section]]) return 0;
    return MAX(1, (NSInteger)self.groupIndexes[section].count);
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
    return [self globalIndexAtIndexPath:path] == NSNotFound ? 44 : 60;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.isSearching ? LOCALIZED(@"ACTION_SEARCH_RESULTS") : nil;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? LOCALIZED(@"ACTION_ORGANIZE_HINT") : nil;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.isSearching || section < 0 || section >= (NSInteger)self.groupIndexes.count) return nil;
    NSString *group = [self groupAtSection:section];
    BOOL collapsed = [MTActionCollapsedGroups(self.prefs) containsObject:group];
    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    UIButton *toggle = [UIButton buttonWithType:UIButtonTypeSystem];
    NSString *title = [NSString stringWithFormat:@"%@ %@ · %lu", collapsed ? @"▸" : @"▾",
        group.length ? group : LOCALIZED(@"UNGROUPED"), (unsigned long)self.groupIndexes[section].count];
    [toggle setTitle:title forState:UIControlStateNormal];
    toggle.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    toggle.tag = section;
    [toggle addTarget:self action:@selector(groupToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:toggle];
    UIButton *menu = [UIButton buttonWithType:UIButtonTypeSystem];
    [menu setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
    menu.tag = section;
    [menu addTarget:self action:@selector(groupHeaderTapped:) forControlEvents:UIControlEventTouchUpInside];
    menu.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:menu];
    [NSLayoutConstraint activateConstraints:@[
        [toggle.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [toggle.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [toggle.trailingAnchor constraintLessThanOrEqualToAnchor:menu.leadingAnchor constant:-8],
        [menu.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [menu.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [menu.widthAnchor constraintEqualToConstant:36],
        [menu.heightAnchor constraintEqualToConstant:36],
    ]];
    return header;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return self.isSearching ? UITableViewAutomaticDimension : 44;
}
- (void)groupToggleTapped:(UIButton *)sender {
    if (self.sortingActions || self.isSearching) return;
    [self toggleActionGroup:[self groupAtSection:sender.tag]];
    [self updateControls];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    MTRegisterManagedCellsIfNeeded(tableView);
    NSInteger global = [self globalIndexAtIndexPath:path];
    if (global != NSNotFound) return [self actionCellForRowAtIndexPath:path global:global table:tableView];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MTPManagedEmptyCell" forIndexPath:path];
    cell.textLabel.text = LOCALIZED(self.isSearching ? @"SEARCH_NO_MATCH" : @"NO_CUSTOM_ACTIONS");
    cell.textLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
- (UITableViewCell *)actionCellForRowAtIndexPath:(NSIndexPath *)indexPath global:(NSInteger)global table:(UITableView *)table {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"MTPManagedActionCell" forIndexPath:indexPath];
    NSDictionary *entry = self.linkActions[global];
    NSString *type = [entry[kCustomActionTypeKey] isKindOfClass:[NSString class]] ? entry[kCustomActionTypeKey] : @"";
    NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
    NSString *link = [entry[@"link"] isKindOfClass:[NSString class]] ? entry[@"link"] : @"";

    cell.textLabel.text = name.length ? name : LOCALIZED(@"DEFAULT_BUTTON_NAME");
    NSString *shortcutTitle = [entry[kCustomActionShortcutTitleKey] isKindOfClass:NSString.class]
        ? entry[kCustomActionShortcutTitleKey] : @"";
    cell.detailTextLabel.text = [type isEqualToString:kCustomActionTypeShortcut] && shortcutTitle.length
        ? [NSString stringWithFormat:@"%@ · %@", link, shortcutTitle]
        : (link.length ? link : [MTPLinkActionEditorController displayNameForType:type]);
    if ([type isEqualToString:kCustomActionTypeText]) {
        id records = entry[kCustomActionTextRecordsKey];
        NSUInteger count = [records isKindOfClass:NSArray.class] ? [records count] : 0;
        cell.detailTextLabel.text = [NSString stringWithFormat:LOCALIZED(@"TEXT_RECORD_COUNT"), (unsigned long)count];
    }
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.imageView.image = [MTHelper imageForCustomActionEntry:entry];
    // Same explicit tint as the 选择动作 rows; app icons are AlwaysOriginal and
    // unaffected, so both sections draw symbols in the same blue.
    cell.imageView.tintColor = [UIColor systemBlueColor];
    NSString *group = MTActionGroupNormalizedName(entry[kCustomActionGroupKey]);
    if (self.isSearching) cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", group.length ? group : LOCALIZED(@"UNGROUPED"), cell.detailTextLabel.text ?: @""];
    cell.accessoryType = self.selectingActions ? ([self.batchSelectors containsObject:entry[@"selector"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone) :
        (self.sortingActions ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator);
    cell.editingAccessoryType = UITableViewCellAccessoryNone;
    return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSInteger global = [self globalIndexAtIndexPath:path];
    if (global == NSNotFound || self.sortingActions) return;
    if (self.selectingActions) {
        NSString *selector = self.linkActions[global][@"selector"];
        if ([self.batchSelectors containsObject:selector]) [self.batchSelectors removeObject:selector];
        else [self.batchSelectors addObject:selector];
        [self.tableView reloadData];
        [self updateControls];
    } else [self pushEditorForCustomRow:global];
}
- (UIBarButtonItem *)button:(NSString *)key action:(SEL)action {
    return [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(key) style:UIBarButtonItemStylePlain target:self action:action];
}
- (void)updateControls {
    self.navigationItem.rightBarButtonItems = @[
        [self button:(self.selectingActions || self.sortingActions) ? @"DONE" : @"ACTION_SELECT" action:@selector(toggleEditing:)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addTapped)],
        [self button:@"ACTION_MORE" action:@selector(moreTapped)]];
    if (self.selectingActions) {
        self.title = [NSString stringWithFormat:LOCALIZED(@"ACTION_SELECTED_COUNT"), (unsigned long)self.batchSelectors.count];
        UIBarButtonItem *move = [self button:@"ACTION_MOVE_SHORT" action:@selector(moveSelected)];
        UIBarButtonItem *ungroup = [self button:@"ACTION_UNGROUP_SHORT" action:@selector(ungroupSelected)];
        UIBarButtonItem *delete = [self button:@"DELETE" action:@selector(deleteSelected)];
        move.enabled = ungroup.enabled = delete.enabled = self.batchSelectors.count > 0;
        self.toolbarItems = @[[self button:@"ACTION_SELECT_ALL" action:@selector(selectAllVisible)], move, ungroup, delete];
    } else {
        self.title = LOCALIZED(@"CUSTOM_ACTIONS");
        NSString *type = self.actionTypeFilter.length ? [MTPLinkActionEditorController displayNameForType:self.actionTypeFilter] : LOCALIZED(@"ACTION_ALL_TYPES");
        UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithTitle:[NSString stringWithFormat:@"%@: %@", LOCALIZED(@"ACTION_TYPE_FILTER"), type]
            style:UIBarButtonItemStylePlain target:self action:@selector(showActionTypeFilter)];
        self.toolbarItems = @[filter, [self button:@"ACTION_GROUP_MANAGER" action:@selector(showGroupManager)]];
    }
}
- (void)toggleEditing:(UIBarButtonItem *)sender {
    if (self.sortingActions) {
        self.sortingActions = NO;
        [self.tableView setEditing:NO animated:YES];
    } else self.selectingActions = !self.selectingActions;
    [self.batchSelectors removeAllObjects];
    [self updateControls];
    [self.tableView reloadData];
}
- (NSSet<NSString *> *)visibleSelectors {
    NSMutableSet *selectors = [NSMutableSet set];
    for (NSNumber *index in self.searchIndexes)
        if (index.unsignedIntegerValue < self.linkActions.count) [selectors addObject:self.linkActions[index.unsignedIntegerValue][@"selector"]];
    return selectors;
}
- (void)selectAllVisible {
    NSSet *visible = [self visibleSelectors];
    if (visible.count && [visible isSubsetOfSet:self.batchSelectors]) [self.batchSelectors minusSet:visible];
    else [self.batchSelectors unionSet:visible];
    [self updateControls];
    [self.tableView reloadData];
}
- (void)applySelectors:(NSSet *)selectors toGroup:(NSString *)group {
    NSMutableDictionary *prefs = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (group.length && ![MTActionGroupNames(prefs, MTActionMutableDefinitions(prefs)) containsObject:group]) {
        [self reloadPreferences];
        [self reloadDataKeepingSelection];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:LOCALIZED(@"ACTION_GROUP_GONE")
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_OK") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSUInteger count = MTActionMoveSelectors(prefs, selectors, group);
    if (count) [MTPrefsManager.sharedInstance writePrefs:prefs];
    [self.batchSelectors removeAllObjects];
    [self reloadPreferences];
    [self reloadDataKeepingSelection];
    NSLog(@"[MetisKeyboard][CustomActions] grouped count=%lu", (unsigned long)count);
}
- (void)chooseGroup:(void (^)(NSString *group))completion {
    NSDictionary *prefs = [MTPrefsManager.sharedInstance readPrefs];
    NSArray *groups = MTActionGroupNames(prefs, MTActionMutableDefinitions(prefs));
    MTPPresentActionGroupChooser(self, groups, self.defaultActionGroup ?: @"", ^(NSString *group, BOOL created) {
        if (created) {
            NSMutableDictionary *live = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
            NSArray *names = MTActionGroupNames(live, MTActionMutableDefinitions(live));
            if (![names containsObject:group]) {
                live[kLinkActionGroupsKey] = [names arrayByAddingObject:group];
                [MTPrefsManager.sharedInstance writePrefs:live];
            }
        }
        if (completion) completion(group);
    });
}
- (void)moveSelected {
    NSSet *selectors = [self.batchSelectors copy];
    __weak typeof(self) weakSelf = self;
    [self chooseGroup:^(NSString *group) { [weakSelf applySelectors:selectors toGroup:group]; }];
}
- (void)ungroupSelected { [self applySelectors:[self.batchSelectors copy] toGroup:@""]; }
- (void)deleteSelectors:(NSSet *)selectors {
    NSMutableDictionary *prefs = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *definitions = MTActionMutableDefinitions(prefs);
    NSIndexSet *removed = [definitions indexesOfObjectsPassingTest:^BOOL(id entry, NSUInteger index, BOOL *stop) {
        return [entry isKindOfClass:NSDictionary.class] && [selectors containsObject:entry[@"selector"] ?: @""];
    }];
    [definitions removeObjectsAtIndexes:removed];
    prefs[kLinkActionskey] = definitions;
    for (NSString *selector in selectors) [self removeReferencesToSelector:selector fromPreferences:prefs];
    [MTPrefsManager.sharedInstance writePrefs:prefs];
    [self.batchSelectors removeAllObjects];
    [self reloadPreferences];
    [self reloadDataKeepingSelection];
}
- (void)deleteSelected {
    NSSet *selectors = [self.batchSelectors copy];
    if (!selectors.count) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOCALIZED(@"DELETE")
        message:[NSString stringWithFormat:LOCALIZED(@"ACTION_DELETE_CONFIRM"), (unsigned long)selectors.count] preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"DELETE") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [weakSelf deleteSelectors:selectors];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showGroupManager {
    MTPActionOrganizationController *manager = [MTPActionOrganizationController new];
    manager.managesGroups = YES;
    [self.navigationController pushViewController:manager animated:YES];
}
- (void)addTapped {
    self.defaultActionGroup = @"";
    [self presentNewActionPage];
}
// 「新建动作」类型选择页（02 §3 + 设计稿第三屏）替代原 alert 菜单；
// 选中后仍走 startAddFlowForType: 暂存条目 + 编辑器，store 只在保存时写入。
// 批量添加应用移入「更多」菜单，保持本页与设计稿一致的六类型布局。
- (void)presentNewActionPage {
    // 防御：无导航栈时不静默失败——记录现场（编辑器同样依赖导航栈，
    // 此形态下「添加」点击本就无法走完，日志便于宿主侧定位）。
    if (!self.navigationController) {
        NSLog(@"[MetisKeyboard][CustomActions] add page skipped: no navigation controller");
        return;
    }
    MTPNewActionTypeController *page = [[MTPNewActionTypeController alloc] init];
    __weak typeof(self) weakSelf = self;
    page.selectionHandler = ^(NSString *type) {
        __strong typeof(weakSelf) owner = weakSelf;
        if (!owner) return;
        [owner startAddFlowForType:type];
    };
    // 本页是普通 UITableViewController（无 PS root 需求），走标准导航压栈；
    // 后续编辑器仍经 startAddFlowForType: 的 pushController:（PSListController 需要 root）。
    [self.navigationController pushViewController:page animated:YES];
}
- (void)groupHeaderTapped:(UIButton *)sender {
    NSString *group = [self groupAtSection:sender.tag];
    self.defaultActionGroup = group;
    [self presentNewActionPage];
}
- (void)setAllCollapsed:(BOOL)collapsed {
    NSMutableDictionary *prefs = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    prefs[kLinkActionCollapsedGroupsKey] = collapsed ? [MTActionGroupNames(prefs, MTActionMutableDefinitions(prefs)) arrayByAddingObject:@""] : @[];
    [MTPrefsManager.sharedInstance writePrefs:prefs];
    [self reloadPreferences];
    [self reloadDataKeepingSelection];
}
- (void)startSorting {
    self.selectingActions = NO;
    [self.batchSelectors removeAllObjects];
    self.actionQuery = @"";
    self.actionTypeFilter = @"";
    self.filterSignature = @"|";
    self.actionSearchController.searchBar.text = @"";
    [self setAllCollapsed:NO];
    self.sortingActions = YES;
    [self.tableView setEditing:YES animated:YES];
    [self updateControls];
}
- (void)moreTapped {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    NSArray *keys = @[@"ACTION_COLLAPSE_ALL", @"ACTION_EXPAND_ALL", @"ACTION_SORT", @"ACTION_GROUP_MANAGER", @"BATCH_ADD_APPLICATIONS"];
    for (NSUInteger index = 0; index < keys.count; index++) {
        NSUInteger operation = index;
        [menu addAction:[UIAlertAction actionWithTitle:LOCALIZED(keys[index]) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (operation < 2) [weakSelf setAllCollapsed:operation == 0];
            else if (operation == 2) [weakSelf startSorting];
            else if (operation == 3) [weakSelf showGroupManager];
            else [weakSelf startBatchAddApplicationsFlow];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path {
    return self.sortingActions && [self globalIndexAtIndexPath:path] != NSNotFound;
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path {
    return self.sortingActions && !self.isSearching && [self globalIndexAtIndexPath:path] != NSNotFound;
}
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)destination {
    return source.section == destination.section && [self tableView:tableView canMoveRowAtIndexPath:destination] ? destination : source;
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    NSInteger from = [self globalIndexAtIndexPath:source], to = [self globalIndexAtIndexPath:destination];
    if (source.section != destination.section || from == NSNotFound || to == NSNotFound) { [self.tableView reloadData]; return; }
    NSString *moving = self.linkActions[from][@"selector"], *target = self.linkActions[to][@"selector"];
    NSMutableDictionary *prefs = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *definitions = MTActionMutableDefinitions(prefs);
    NSUInteger a = NSNotFound, b = NSNotFound;
    for (NSUInteger index = 0; index < definitions.count; index++) {
        id entry = definitions[index];
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        if ([entry[@"selector"] isEqual:moving]) a = index;
        if ([entry[@"selector"] isEqual:target]) b = index;
    }
    if (a != NSNotFound && b != NSNotFound && [MTActionGroupNormalizedName(definitions[a][kCustomActionGroupKey]) isEqual:MTActionGroupNormalizedName(definitions[b][kCustomActionGroupKey])]) {
        id entry = definitions[a];
        [definitions removeObjectAtIndex:a];
        [definitions insertObject:entry atIndex:b];
        prefs[kLinkActionskey] = definitions;
        [MTPrefsManager.sharedInstance writePrefs:prefs];
    }
    [self reloadPreferences];
    [self reloadDataKeepingSelection];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    NSInteger global = [self globalIndexAtIndexPath:path];
    if (global == NSNotFound || self.selectingActions || self.sortingActions) return nil;
    NSString *selector = self.linkActions[global][@"selector"];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:LOCALIZED(@"DELETE")
        handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
            __strong typeof(weakSelf) owner = weakSelf;
            if (owner) [owner deleteSelectors:[NSSet setWithObject:selector]];
            completion(owner != nil);
        }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[action]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)path point:(CGPoint)point {
    NSInteger global = [self globalIndexAtIndexPath:path];
    if (global == NSNotFound || self.selectingActions || self.sortingActions) return nil;
    NSString *selector = self.linkActions[global][@"selector"];
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested) {
        UIAction *move = [UIAction actionWithTitle:LOCALIZED(@"MOVE_TO_GROUP") image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *action) {
            [weakSelf chooseGroup:^(NSString *group) { [weakSelf applySelectors:[NSSet setWithObject:selector] toGroup:group]; }];
        }];
        return [UIMenu menuWithTitle:@"" children:@[move]];
    }];
}
- (void)startBatchAddApplicationsFlow {
    __weak typeof(self) weakSelf = self;
    [self chooseGroup:^(NSString *group) {
        __strong typeof(weakSelf) owner = weakSelf;
        if (!owner) return;
        MTPOpenAppPickerController *picker = [MTPOpenAppPickerController new];
        picker.allowsMultipleSelection = YES;
        picker.multiSelectionCompletion = ^(NSArray<MTPAppInfo *> *apps) { [weakSelf addOpenAppActionsForApps:apps group:group]; };
        [picker setRootController:owner.rootController];
        [picker setParentController:owner.parentController];
        [owner pushController:picker];
    }];
}
- (void)addOpenAppActionsForApps:(NSArray<MTPAppInfo *> *)apps group:(NSString *)group {
    [self reloadPreferences];
    NSMutableArray *picks = [NSMutableArray array];
    for (MTPAppInfo *app in apps) [picks addObject:@{@"bundleID": app.bundleID ?: @"", @"name": app.name ?: @""}];
    NSUInteger skipped = 0;
    NSArray *entries = MTBatchOpenAppEntries(self.linkActions, picks, &skipped);
    BOOL validGroup = [self.groupNames containsObject:group];
    for (NSMutableDictionary *entry in entries) if (validGroup && group.length) entry[kCustomActionGroupKey] = group;
    if (entries.count) {
        [self.linkActions addObjectsFromArray:entries];
        [self persistLinkActions];
        [self reloadDataKeepingSelection];
    }
    if (skipped) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
            message:[NSString stringWithFormat:LOCALIZED(@"BATCH_ADD_RESULT"), (unsigned long)entries.count, (unsigned long)skipped]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_OK") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end
