#import "MTPContextAppGroupEditorController.h"
#import "MTPContextTypesController.h"
#import "MTSettingsNavigation.h"
#import "MTPrefsManager.h"
#import "MTPAppInfo.h"
#import "MTPOpenAppPickerController.h"
#import "MTPSubActionPickerController.h"
#import "MTPPanelActionCatalog.h"
#import "MTContextTypes.h"
#import "MTContextGroupPreferences.h"
#import "MTContextGroupEngine.h"

static const NSUInteger MTPAppGroupActionLimit = 8;

@interface MTPContextAppGroupEditorController () <UITableViewDelegate, UITableViewDataSource>
@property(nonatomic, copy) NSString *groupIdentifier;
@property(nonatomic, strong) MTContextAppGroup *group;
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, assign) NSUInteger slots;
@end

@implementation MTPContextAppGroupEditorController

- (instancetype)initWithGroupIdentifier:(NSString *)identifier {
    if ((self = [super init])) _groupIdentifier = [identifier copy];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.delegate = self;
    self.table.dataSource = self;
    // 常驻编辑态只为了给动作行提供拖动与删除入口；行点击仍然要能进替换菜单。
    self.table.editing = YES;
    self.table.allowsSelectionDuringEditing = YES;
    [self.view addSubview:self.table];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    MTContextGroupConfig *config = [MTContextGroupConfig configFromPreferences:[MTPrefsManager.sharedInstance readPrefs]];
    MTContextAppGroup *found = nil;
    for (MTContextAppGroup *group in config.appGroups)
        if ([group.identifier isEqual:self.groupIdentifier]) { found = group; break; }
    self.group = found;
    self.slots = [config slotsForGroup:@"app"];
    self.title = self.group.name.length ? self.group.name : MTPCTX(@"CTXAPP_UNNAMED");
    [self.table reloadData];
}

// 绑定关系是全局唯一的：这里保存时把组内 App 从其它组移出，读回时不会再被
// 「先声明者优先」的规则悄悄丢掉。
- (void)save {
    if (!self.group) return;
    NSArray<MTContextAppGroup *> *current = [MTContextAppGroup groupsFromPreferences:[MTPrefsManager.sharedInstance readPrefs]];
    NSMutableArray *items = [NSMutableArray array];
    BOOL replaced = NO;
    for (MTContextAppGroup *group in current) {
        if ([group.identifier isEqual:self.group.identifier]) {
            [items addObject:self.group.dictionaryRepresentation];
            replaced = YES;
            continue;
        }
        NSMutableArray *rest = [NSMutableArray array];
        for (NSString *bundleID in group.bundleIDs)
            if (![self.group.bundleIDs containsObject:bundleID]) [rest addObject:bundleID];
        group.bundleIDs = rest;
        [items addObject:group.dictionaryRepresentation];
    }
    if (!replaced) [items addObject:self.group.dictionaryRepresentation];
    [MTPrefsManager.sharedInstance setValue:items forKey:kContextAppGroupsKey];
    [self reload];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : self.group.actions.count + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return MTPCTX(@"CTXAPP_SECTION_BIND");
    return [NSString stringWithFormat:MTPCTX(@"CTXAPP_SECTION_ACTIONS"), (unsigned long)self.slots];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? MTPCTX(@"CTXAPP_BIND_FOOTER") : MTPCTX(@"CTXAPP_ACTION_FOOTER");
}

- (NSString *)appsSummary {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *bundleID in self.group.bundleIDs) {
        [names addObject:[MTPAppInfo displayNameForBundleID:bundleID] ?: bundleID];
        if (names.count == 2) break;
    }
    NSString *summary = names.count ? [names componentsJoinedByString:@"、"] : MTPCTX(@"CTXAPP_UNBOUND");
    if (self.group.bundleIDs.count > 2) summary = [summary stringByAppendingString:@"…"];
    return summary;
}

- (UITableViewCell *)actionCellAtIndex:(NSUInteger)index {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (index >= self.group.actions.count) {
        BOOL room = self.group.actions.count < MTPAppGroupActionLimit;
        cell.textLabel.text = MTPCTX(@"CTXAPP_ADD_ACTION");
        cell.textLabel.textColor = room ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
        return cell;
    }
    NSString *selector = self.group.actions[index];
    cell.textLabel.text = MTPPanelDisplayDefinition([MTPrefsManager.sharedInstance readPrefs], selector)[@"name"]
        ?: MTPCTX([@"CTX_ACTION_" stringByAppendingString:selector]);
    cell.detailTextLabel.text = index >= self.slots ? MTPCTX(@"CTX_OVER_CAPACITY")
        : (index == 0 ? MTPCTX(@"CTX_DEFAULT") : [NSString stringWithFormat:MTPCTX(@"CTX_SLOT"), (unsigned long)index + 1]);
    cell.textLabel.textColor = index >= self.slots ? UIColor.tertiaryLabelColor : UIColor.labelColor;
    cell.showsReorderControl = YES;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 1) return [self actionCellAtIndex:path.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (path.row == 0) {
        cell.textLabel.text = MTPCTX(@"CTXAPP_NAME");
        cell.detailTextLabel.text = self.group.name.length ? self.group.name : MTPCTX(@"CTXAPP_UNNAMED");
    } else {
        cell.textLabel.text = MTPCTX(@"CTXAPP_APPS");
        cell.detailTextLabel.text = [self appsSummary];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.editingAccessoryView = [UIView new];
    return cell;
}

#pragma mark - 选中

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (!self.group) return;
    if (path.section == 0) {
        if (path.row == 0) [self editName];
        else [self editApps];
        return;
    }
    if (path.row >= (NSInteger)self.group.actions.count) { [self addAction]; return; }
    [self editActionAtRow:path.row];
}

- (void)editName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTPCTX(@"CTXAPP_NAME_PROMPT")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = self.group.name;
        field.placeholder = MTPCTX(@"CTXAPP_UNNAMED");
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:MTPCTX(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:MTPCTX(@"DONE") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        weakSelf.group.name = name.length > 32 ? [name substringToIndex:32] : name;
        [weakSelf save];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editApps {
    MTPOpenAppPickerController *picker = [MTPOpenAppPickerController new];
    picker.allowsMultipleSelection = YES;
    picker.preselectedBundleIDs = self.group.bundleIDs;
    __weak typeof(self) weakSelf = self;
    picker.multiSelectionCompletion = ^(NSArray<MTPAppInfo *> *apps) {
        NSMutableArray *bundleIDs = [NSMutableArray array];
        for (MTPAppInfo *app in apps) {
            NSString *bundleID = app.bundleID.lowercaseString;
            if (bundleID.length && ![bundleIDs containsObject:bundleID]) [bundleIDs addObject:bundleID];
        }
        weakSelf.group.bundleIDs = bundleIDs;
        [weakSelf save];
    };
    [self pushPage:picker];
}

#pragma mark - 动作

- (void)addAction {
    if (!self.group || self.group.actions.count >= MTPAppGroupActionLimit) return;
    __weak typeof(self) weakSelf = self;
    MTPSubActionPickerController *picker = [MTPSubActionPickerController new];
    picker.actionContextKind = MTPanelKeyboardKind;
    picker.fullOrder = MTPPanelBuiltInActions();
    picker.title = MTPCTX(@"CTXAPP_ADD_ACTION");
    picker.completion = ^(NSString *selector) {
        MTPContextAppGroupEditorController *owner = weakSelf;
        if (!owner || !selector.length || owner.group.actions.count >= MTPAppGroupActionLimit) return;
        if (!MTContextActionAllowed(selector, [MTPrefsManager.sharedInstance readPrefs])) return;
        owner.group.actions = [owner.group.actions arrayByAddingObject:selector];
        [owner save];
    };
    [self pushPage:picker];
}

- (void)editActionAtRow:(NSUInteger)row {
    NSString *selector = self.group.actions[row];
    __weak typeof(self) weakSelf = self;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:selector message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:MTPCTX(@"CTXAPP_REPLACE_ACTION") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf replaceActionAtRow:row];
    }]];
    if (row > 0) [menu addAction:[UIAlertAction actionWithTitle:MTPCTX(@"BAR_UP") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf moveRow:row to:row - 1];
    }]];
    if (row + 1 < self.group.actions.count) [menu addAction:[UIAlertAction actionWithTitle:MTPCTX(@"BAR_DOWN") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf moveRow:row to:row + 1];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:MTPCTX(@"BAR_REMOVE") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [weakSelf removeActionAtRow:row];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:MTPCTX(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.table;
    menu.popoverPresentationController.sourceRect = [self.table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1]];
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)replaceActionAtRow:(NSUInteger)row {
    if (row >= self.group.actions.count) return;
    NSString *selector = self.group.actions[row];
    __weak typeof(self) weakSelf = self;
    MTPSubActionPickerController *picker = [MTPSubActionPickerController new];
    picker.actionContextKind = MTPanelKeyboardKind;
    picker.fullOrder = MTPPanelBuiltInActions();
    picker.selectedSelector = selector;
    picker.title = MTPCTX(@"CTXAPP_REPLACE_ACTION");
    picker.completion = ^(NSString *replacement) {
        MTPContextAppGroupEditorController *owner = weakSelf;
        if (!owner || !replacement.length || row >= owner.group.actions.count) return;
        if ([owner.group.actions[row] isEqual:replacement]) return;
        if (!MTContextActionAllowed(replacement, [MTPrefsManager.sharedInstance readPrefs])) return;
        NSMutableArray *actions = [owner.group.actions mutableCopy];
        actions[row] = replacement;
        owner.group.actions = actions;
        [owner save];
    };
    [self pushPage:picker];
}

- (void)moveRow:(NSUInteger)from to:(NSUInteger)to {
    if (from >= self.group.actions.count || to >= self.group.actions.count) return;
    NSMutableArray *actions = [self.group.actions mutableCopy];
    NSString *item = actions[from];
    [actions removeObjectAtIndex:from];
    [actions insertObject:item atIndex:to];
    self.group.actions = actions;
    [self save];
}

- (void)removeActionAtRow:(NSUInteger)row {
    if (row >= self.group.actions.count) return;
    NSMutableArray *actions = [self.group.actions mutableCopy];
    [actions removeObjectAtIndex:row];
    self.group.actions = actions;
    [self save];
}

#pragma mark - 拖动与删除

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 1 && path.row < (NSInteger)self.group.actions.count;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return [self tableView:tableView canMoveRowAtIndexPath:path] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

// 只让动作区保留编辑缩进：其余行没有编辑控件，缩进会让卡片比分组标题多凹一截。
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 1;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    [self moveRow:source.row to:destination.row];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style == UITableViewCellEditingStyleDelete) [self removeActionAtRow:path.row];
}

- (void)pushPage:(UIViewController *)page {
    MTSettingsPushController(self, page, nil, YES);
}

@end
