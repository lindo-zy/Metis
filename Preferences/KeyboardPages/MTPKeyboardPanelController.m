#import "MTPKeyboardPanelController.h"
#import "MTPSubActionPickerController.h"
#import "MTPKeyboardPanelPreviewHeader.h"
#import "MTPPanelSliderCell.h"
#import "MTPLinkActionEditorController.h"
#import "MTPPanelActionCatalog.h"
#import "MTKeyboardPanelPreferences.h"
#import "MTHelper.h"
#import "common.h"
#import <Preferences/PSSpecifier.h>

static NSString *MTPanelLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}

// Keyboard context shows every action; gesture context excludes keyboard
// operations. Both offer same-type panels and custom-action creation.
@interface MTPKeyboardPanelActionPicker : MTPSubActionPickerController
@end
@implementation MTPKeyboardPanelActionPicker
- (void)viewDidLoad {
    self.allowsDeletingCustomActions = YES;
    [super viewDidLoad];
}
- (BOOL)showsBuiltInActionsSection { return ![self.actionContextKind isEqual:MTPanelGestureKind]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return MTPanelLocalized(@"KEYBOARD_PANEL_PICKER_DELETE_FOOTER");
}
@end

@interface MTPKeyboardPanelController ()
@property(nonatomic, strong) MTPKeyboardPanelPreviewHeader *previewHeader;
@property(nonatomic, strong) UISearchController *keyboardTestSearch;
- (NSString *)panelSelector;
@end
@implementation MTPKeyboardPanelController
- (NSString *)panelSelector { return [self.specifier propertyForKey:@"panelSelector"]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *selector = [self panelSelector];
    self.title = selector ? MTPanelString(MTPanelDefinition([MTPrefsManager.sharedInstance readPrefs], selector)[@"name"]) : MTPanelLocalized(@"KEYBOARD_PANEL_SETTINGS");
    if (selector) {
        self.previewHeader = [[MTPKeyboardPanelPreviewHeader alloc] initWithPanelSelector:selector];
        self.previewHeader.frame = CGRectMake(0, 0, self.table.bounds.size.width, self.previewHeader.bounds.size.height);
        self.table.tableHeaderView = self.previewHeader;
        if (MTPanelAllowed([MTPrefsManager.sharedInstance readPrefs], selector, MTPanelKeyboardKind)) {
            self.keyboardTestSearch = [[UISearchController alloc] initWithSearchResultsController:nil];
            self.keyboardTestSearch.obscuresBackgroundDuringPresentation = NO;
            self.keyboardTestSearch.hidesNavigationBarDuringPresentation = NO;
            self.keyboardTestSearch.searchBar.placeholder = MTPanelLocalized(@"PANEL_KEYBOARD_TEST");
            self.navigationItem.searchController = self.keyboardTestSearch;
            self.definesPresentationContext = YES;
        }
    } else {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addPanel)];
    }
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; [self.previewHeader refresh]; }
- (void)viewWillDisappear:(BOOL)animated {
    self.keyboardTestSearch.active = NO; [self.view endEditing:YES]; [super viewWillDisappear:animated];
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    if ([[self specifierAtIndexPath:path] propertyForKey:@"cellClass"] == MTPPanelSliderCell.class) return 80;
    return [super tableView:table heightForRowAtIndexPath:path];
}
- (PSSpecifier *)setting:(NSString *)label key:(NSString *)key defaultValue:(id)value cell:(PSCellType)cell {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:MTPanelLocalized(label) target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:cell edit:nil];
    [item setProperty:key forKey:@"key"]; [item setProperty:value forKey:@"default"];
    return item;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    NSString *selector = [self panelSelector];
    NSDictionary *preferences = [MTPrefsManager.sharedInstance readPrefs];
    if (!selector) {
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:MTPanelLocalized(@"PANEL_SETTINGS")];
        [group setProperty:MTPanelLocalized(@"PANEL_TYPES_FOOTER") forKey:@"footerText"]; [items addObject:group];
        [items addObject:[self setting:@"GLOBAL_PANEL_ENABLED" key:kMTPanelGlobalEnabled defaultValue:@YES cell:PSSwitchCell]];
        for (NSString *kind in @[MTPanelKeyboardKind, MTPanelGestureKind]) {
            [items addObject:[PSSpecifier groupSpecifierWithName:MTPanelLocalized([kind isEqual:MTPanelKeyboardKind] ? @"PANEL_KIND_KEYBOARD" : @"PANEL_KIND_GESTURE")]];
            for (NSDictionary *panel in MTPanelDefinitions(preferences, kind)) {
                PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:MTPanelString(panel[@"name"]) target:self set:nil get:nil detail:MTPKeyboardPanelController.class cell:PSLinkCell edit:nil];
                [link setProperty:MTPanelSelector(panel[@"id"]) forKey:@"panelSelector"];
                [link setProperty:[MTHelper imageForIconConfig:MTPanelDefaultIconName(panel[@"kind"]) defaultSymbolName:@"square.grid.2x2"] forKey:@"iconImage"];
                [items addObject:link];
            }
        }
        _specifiers = items; return items;
    }
    NSDictionary *panel = MTPanelDefinition(preferences, selector);
    if (!panel) { _specifiers = items; return items; }
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:MTPanelLocalized([panel[@"kind"] isEqual:MTPanelKeyboardKind] ? @"PANEL_KIND_KEYBOARD" : @"PANEL_KIND_GESTURE")];
    [group setProperty:MTPanelLocalized([panel[@"kind"] isEqual:MTPanelKeyboardKind] ? @"PANEL_KEYBOARD_FOOTER" : @"PANEL_GESTURE_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    [items addObject:[self setting:@"PANEL_NAME" key:@"name" defaultValue:@"" cell:PSEditTextCell]];
    [items addObject:[self setting:@"KEYBOARD_PANEL_SYSTEM_TOGGLES" key:kMTPanelSystemTogglesVisible defaultValue:@YES cell:PSSwitchCell]];
    [items addObject:[self setting:@"KEYBOARD_PANEL_SYSTEM_SLIDERS" key:kMTPanelSystemSlidersVisible defaultValue:@YES cell:PSSwitchCell]];
    PSSpecifier *actions = [PSSpecifier preferenceSpecifierNamed:MTPanelLocalized(@"KEYBOARD_PANEL_ACTIONS") target:self set:nil get:nil detail:MTPKeyboardPanelItemsController.class cell:PSLinkCell edit:nil];
    [actions setProperty:selector forKey:@"panelSelector"]; [items addObject:actions];
    [items addObject:[PSSpecifier groupSpecifierWithName:MTPanelLocalized(@"KEYBOARD_PANEL_APPEARANCE")]];
    [items addObject:[self setting:@"KEYBOARD_PANEL_DARK" key:kMTPanelDark defaultValue:@NO cell:PSSwitchCell]];
    for (NSArray *row in @[@[@"KEYBOARD_PANEL_COLUMNS", kMTPanelColumns, @4, @3, @5], @[@"KEYBOARD_PANEL_SCALE", kMTPanelScale, @100, @70, @120]]) {
        PSSpecifier *slider = [self setting:row[0] key:row[1] defaultValue:row[2] cell:PSStaticTextCell];
        [slider setProperty:MTPPanelSliderCell.class forKey:@"cellClass"]; [slider setProperty:row[3] forKey:@"min"]; [slider setProperty:row[4] forKey:@"max"];
        [slider setProperty:@YES forKey:@"showValue"]; [items addObject:slider];
    }
    _specifiers = items; return items;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *preferences = [MTPrefsManager.sharedInstance readPrefs];
    NSString *key = [specifier propertyForKey:@"key"], *selector = [self panelSelector];
    if (!selector) return preferences[key] ?: [specifier propertyForKey:@"default"];
    NSDictionary *panel = MTPanelDefinition(preferences, selector);
    return ([key isEqual:@"name"] ? panel[key] : MTPanelPreferences(preferences, selector)[key]) ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"], *selector = [self panelSelector];
    if (!key.length || !value) return;
    if (!selector) { [MTPrefsManager.sharedInstance setValue:value forKey:key]; return; }
    NSMutableDictionary *preferences = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy];
    if (!MTPanelDefinition(preferences, selector)) return;
    if ([key isEqual:@"name"]) {
        value = [MTPanelString(value) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![value length]) return;
        MTPanelUpdate(preferences, selector, @{key: value});
    } else {
        if ([key isEqual:kMTPanelColumns]) value = @(MIN(5, MAX(3, lround([value doubleValue]))));
        if ([key isEqual:kMTPanelScale]) value = @(MIN(120, MAX(70, lround([value doubleValue] / 5) * 5)));
        id stored = MTPanelDefinition(preferences, selector)[@"preferences"];
        NSMutableDictionary *options = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
        options[key] = value; MTPanelUpdate(preferences, selector, @{@"preferences": options});
    }
    [MTPrefsManager.sharedInstance writePrefs:preferences];
    self.title = MTPanelString(MTPanelDefinition(preferences, selector)[@"name"]); [self.previewHeader refresh];
}
- (void)addPanel {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:MTPanelLocalized(@"PANEL_ADD") message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSString *kind in @[MTPanelKeyboardKind, MTPanelGestureKind])
        [menu addAction:[UIAlertAction actionWithTitle:MTPanelLocalized([kind isEqual:MTPanelKeyboardKind] ? @"PANEL_KIND_KEYBOARD" : @"PANEL_KIND_GESTURE") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf addPanelOfKind:kind]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:MTPanelLocalized(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)addPanelOfKind:(NSString *)kind {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTPanelLocalized(@"PANEL_ADD") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = MTPanelLocalized(@"PANEL_NAME"); }];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:MTPanelLocalized(@"KEYBOARD_PANEL_SAVE") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !MTPanelKindValid(kind) || self.navigationController.topViewController != self) return;
        NSMutableDictionary *preferences = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy];
        NSMutableArray *panels = [MTPanelDefinitions(preferences, nil) mutableCopy];
        NSString *name = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length) name = MTPanelLocalized([kind isEqual:MTPanelKeyboardKind] ? @"PANEL_KIND_KEYBOARD" : @"PANEL_KIND_GESTURE");
        NSDictionary *panel = @{@"id": NSUUID.UUID.UUIDString, @"kind": kind, @"name": name, @"icon": MTPanelDefaultIconName(kind), @"items": @[], @"preferences": @{}};
        [panels addObject:panel]; preferences[kMTPanels] = panels;
        [MTPrefsManager.sharedInstance writePrefs:preferences]; [self reloadSpecifiers];
        MTPKeyboardPanelController *editor = [MTPKeyboardPanelController new];
        PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name target:nil set:nil get:nil detail:nil cell:PSLinkCell edit:nil];
        [specifier setProperty:MTPanelSelector(panel[@"id"]) forKey:@"panelSelector"]; editor.specifier = specifier;
        [editor setRootController:self.rootController]; [editor setParentController:self]; [self pushController:editor];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:MTPanelLocalized(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path {
    (void)tableView; return ![self panelSelector] && [[self specifierAtIndexPath:path] propertyForKey:@"panelSelector"] != nil;
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    (void)tableView;
    if (style == UITableViewCellEditingStyleDelete) [self deletePanelSelector:[[self specifierAtIndexPath:path] propertyForKey:@"panelSelector"]];
}
- (BOOL)deletePanelSelector:(NSString *)selector {
    if (!selector || [self panelSelector]) return NO;
    NSMutableDictionary *preferences = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy];
    NSDictionary *panel = MTPanelDefinition(preferences, selector);
    if (!panel) return NO;
    NSMutableArray *panels = [MTPanelDefinitions(preferences, nil) mutableCopy]; [panels removeObject:panel]; preferences[kMTPanels] = panels;
    [[MTPCustomActionViewController new] removeReferencesToSelector:selector fromPreferences:preferences];
    [MTPrefsManager.sharedInstance writePrefs:preferences]; [self reloadSpecifiers]; return YES;
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (![self tableView:tableView canEditRowAtIndexPath:path]) return nil;
    NSString *selector = [[self specifierAtIndexPath:path] propertyForKey:@"panelSelector"];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:MTPanelLocalized(@"DELETE") handler:^(__unused UIContextualAction *action, __unused UIView *view, void (^completion)(BOOL)) { completion([weakSelf deletePanelSelector:selector]); }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[remove]];
    configuration.performsFirstActionWithFullSwipe = NO; return configuration;
}
@end
// 面板条目只编辑名称，图标跟随引用的动作或面板。
@interface MTPPanelItemAppearanceController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, copy) NSDictionary *entry;
@property(nonatomic, strong) UITextField *nameField;
@property(nonatomic, copy) void (^completion)(NSDictionary *updatedEntry);
@end

@implementation MTPPanelItemAppearanceController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTPanelLocalized(@"KEYBOARD_PANEL_ITEM_APPEARANCE");
    self.nameField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 180, 36)];
    self.nameField.textAlignment = NSTextAlignmentRight;
    self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.nameField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.nameField.placeholder = MTPanelLocalized(@"KEYBOARD_PANEL_NAME");
    self.nameField.text = [self.entry[@"name"] isKindOfClass:NSString.class] ? self.entry[@"name"] : @"";

    UITableView *table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    table.dataSource = self;
    table.delegate = self;
    self.view = table;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:MTPanelLocalized(@"KEYBOARD_PANEL_SAVE")
        style:UIBarButtonItemStyleDone target:self action:@selector(saveTapped)];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PanelAppearanceCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PanelAppearanceCell"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    (void)indexPath;
    cell.textLabel.text = MTPanelLocalized(@"KEYBOARD_PANEL_NAME");
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.imageView.image = nil;
    cell.accessoryView = self.nameField;
    return cell;
}

- (void)saveTapped {
    [self.view endEditing:YES];
    NSMutableDictionary *updated = [self.entry mutableCopy] ?: [NSMutableDictionary dictionary];
    updated[@"name"] = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    [updated removeObjectForKey:@"icon"];
    if (self.completion) self.completion(updated);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface MTPKeyboardPanelItemsController () <UITableViewDragDelegate, UITableViewDropDelegate>
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) MTPKeyboardPanelPreviewHeader *previewHeader;
@property(nonatomic, copy) NSString *panelSelector;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *entries;
@end

@implementation MTPKeyboardPanelItemsController
- (NSMutableArray *)configuredEntries {
    NSDictionary *preferences = [[MTPrefsManager sharedInstance] readPrefs];
    return [MTPanelItems(preferences, self.panelSelector) mutableCopy];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.panelSelector = [self.specifier propertyForKey:@"panelSelector"];
    self.title = self.specifier.name;
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.delegate = self;
    self.table.dataSource = self;
    [self.view addSubview:self.table];
    self.previewHeader = [[MTPKeyboardPanelPreviewHeader alloc] initWithPanelSelector:self.panelSelector];
    self.previewHeader.frame = CGRectMake(0, 0, self.table.bounds.size.width, self.previewHeader.bounds.size.height);
    self.table.tableHeaderView = self.previewHeader;
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addActions)];
    self.navigationItem.rightBarButtonItem = addButton;
    self.entries = [self configuredEntries];
    // 排序不设编辑模式：长按直接拖动（drag & drop），左滑删除照旧。
    self.table.dragInteractionEnabled = YES;
    self.table.dragDelegate = self;
    self.table.dropDelegate = self;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.entries = [self configuredEntries];
    [self.previewHeader refresh];
    [self.table reloadData];
}
- (void)save {
    NSMutableDictionary *preferences = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy];
    if (!MTPanelDefinition(preferences, self.panelSelector)) return;
    MTPanelUpdate(preferences, self.panelSelector, @{@"items": [self.entries copy]});
    [MTPrefsManager.sharedInstance writePrefs:preferences];
    [self.previewHeader refresh];
}
- (NSDictionary *)definitionForSelector:(NSString *)selector {
    NSDictionary *preferences = [MTPrefsManager.sharedInstance readPrefs];
    return MTPPanelDisplayDefinition(preferences, selector);
}
- (NSDictionary *)customDefinitionForSelector:(NSString *)selector {
    id stored = [[MTPrefsManager sharedInstance] readPrefs][kLinkActionskey];
    if (![stored isKindOfClass:NSArray.class]) return nil;
    for (id entry in stored) if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return entry;
    return nil;
}
- (NSString *)nameForEntry:(NSDictionary *)entry {
    NSString *name = entry[@"name"];
    if (name.length) return name;
    name = [self definitionForSelector:entry[@"selector"]][@"name"];
    return name.length ? name : [MTHelper localizedStringForActionNamed:entry[@"selector"] shortName:NO bundle:[NSBundle bundleWithPath:bundlePath]];
}
- (UIImage *)imageForEntry:(NSDictionary *)entry {
    NSString *icon = [self definitionForSelector:entry[@"selector"]][@"icon"];
    if (icon.length) return [MTHelper imageForIconConfig:icon defaultSymbolName:@"link"];
    return [UIImage systemImageNamed:@"square.grid.2x2"];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.entries.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return MTPanelLocalized(@"KEYBOARD_PANEL_ITEMS_FOOTER");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PanelItem"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PanelItem"];
    NSDictionary *entry = self.entries[indexPath.row];
    cell.textLabel.text = [self nameForEntry:entry];
    cell.imageView.image = [self imageForEntry:entry];
    // 行尾固定拖动把手，让可拖动性可见；拖动本身仍由表格的长按 drag & drop 承担。
    UIImageView *handle = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
    handle.contentMode = UIViewContentModeScaleAspectFit;
    handle.tintColor = UIColor.secondaryLabelColor;
    handle.frame = CGRectMake(0, 0, 24, 24);
    cell.accessoryView = handle;
    return cell;
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != 0 || indexPath.row < 0 || indexPath.row >= (NSInteger)self.entries.count) return;
    [self removeEntry:self.entries[indexPath.row] fromTable:tableView];
}
- (BOOL)removeEntry:(NSDictionary *)entry fromTable:(UITableView *)tableView {
    // Resolve the captured item again, so a stale swipe cannot delete a different
    // item after reload/reorder. Delete only this panel's reference, not its definition.
    NSUInteger row = [self.entries indexOfObjectIdenticalTo:entry];
    if (row == NSNotFound) return NO;
    [self.entries removeObjectAtIndex:row];
    [self save];
    [tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];
    return YES;
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section == 0 && indexPath.row >= 0 && indexPath.row < (NSInteger)self.entries.count;
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath;
    return UITableViewCellEditingStyleDelete;
}
- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath;
    return MTPanelLocalized(@"DELETE");
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0 || indexPath.row < 0 || indexPath.row >= (NSInteger)self.entries.count) return nil;
    NSDictionary *entry = self.entries[indexPath.row];
    __weak typeof(self) weakSelf = self;
    __weak UITableView *weakTable = tableView;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:MTPanelLocalized(@"DELETE") handler:^(__unused UIContextualAction *action, __unused UIView *view, void (^completion)(BOOL)) {
            __strong typeof(weakSelf) self = weakSelf;
            UITableView *table = weakTable;
            completion(self && table && [self removeEntry:entry fromTable:table]);
        }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[remove]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}
// 长按拖动排序：本地拖动会话由表格跟踪落点间隙，落点即最终数组位置，
// 数据源更新与 moveRow 动画在同一 beginUpdates 里提交。
- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)session;
    if (indexPath.section != 0 || indexPath.row < 0 || indexPath.row >= (NSInteger)self.entries.count) return @[];
    NSDictionary *entry = self.entries[indexPath.row];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:[[NSItemProvider alloc] initWithObject:entry[@"id"] ?: @""]];
    item.localObject = entry;
    return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
    (void)tableView; (void)destinationIndexPath;
    if (!session.localDragSession) return nil;
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
        intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *destination = coordinator.destinationIndexPath;
    id<UITableViewDropItem> dropItem = coordinator.items.firstObject;
    if (!destination || !dropItem.sourceIndexPath) return;
    NSDictionary *entry = dropItem.dragItem.localObject;
    if (![entry isKindOfClass:NSDictionary.class]) return;
    NSUInteger sourceRow = [self.entries indexOfObjectIdenticalTo:entry];
    if (sourceRow == NSNotFound) return;
    // 落点按当前序的插入位计（末尾追加=行数）；先移除源行，向下移动回缩一位。
    NSInteger targetRow = MIN(MAX(destination.row, 0), (NSInteger)self.entries.count);
    if (targetRow > (NSInteger)sourceRow) targetRow--;
    if (targetRow == (NSInteger)sourceRow) return;
    [tableView beginUpdates];
    [self.entries removeObjectAtIndex:sourceRow];
    [self.entries insertObject:entry atIndex:targetRow];
    [tableView moveRowAtIndexPath:[NSIndexPath indexPathForRow:sourceRow inSection:0]
        toIndexPath:[NSIndexPath indexPathForRow:targetRow inSection:0]];
    [tableView endUpdates];
    [self save];
}
- (void)pushPicker:(MTPSubActionPickerController *)picker {
    NSDictionary *panel = MTPanelDefinition([MTPrefsManager.sharedInstance readPrefs], self.panelSelector);
    if (!panel) return;
    picker.actionContextKind = panel[@"kind"];
    picker.fullOrder = [panel[@"kind"] isEqual:MTPanelKeyboardKind] ? MTPPanelBuiltInActions() : @[];
    picker.title = MTPanelLocalized(@"CHOOSE_ACTION");
    [picker setRootController:[self rootController]];
    [picker setParentController:[self parentController]];
    [self pushController:picker];
}
- (void)addActions {
    MTPSubActionPickerController *picker = [[MTPKeyboardPanelActionPicker alloc] init];
    picker.allowsMultipleSelection = YES;
    __weak typeof(self) weakSelf = self;
    __weak MTPSubActionPickerController *weakPicker = picker;
    picker.multiSelectionCompletion = ^(NSArray<NSString *> *selectors) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.navigationController.topViewController != weakPicker || ![self.navigationController.viewControllers containsObject:self]) return;
        // The picker can delete definitions and saved panel references. Start
        // from that latest configuration instead of restoring the parent's copy.
        self.entries = [self configuredEntries];
        for (NSString *selector in selectors) {
            if (MTPanelItemAllowed([MTPrefsManager.sharedInstance readPrefs], selector, MTPanelDefinition([MTPrefsManager.sharedInstance readPrefs], self.panelSelector)[@"kind"]) && [self definitionForSelector:selector])
                [self.entries addObject:@{@"id": NSUUID.UUID.UUIDString, @"selector": selector}];
        }
        [self save];
        [self.table reloadData];
    };
    [self pushPicker:picker];
}
- (void)replaceActionAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.entries.count) return;
    NSDictionary *original = self.entries[row];
    MTPSubActionPickerController *picker = [[MTPKeyboardPanelActionPicker alloc] init];
    picker.selectedSelector = original[@"selector"];
    __weak typeof(self) weakSelf = self;
    __weak MTPSubActionPickerController *weakPicker = picker;
    picker.completion = ^(NSString *selector) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.navigationController.topViewController != weakPicker || ![self.navigationController.viewControllers containsObject:self] || ![self definitionForSelector:selector] || !MTPanelItemAllowed([MTPrefsManager.sharedInstance readPrefs], selector, MTPanelDefinition([MTPrefsManager.sharedInstance readPrefs], self.panelSelector)[@"kind"])) return;
        self.entries = [self configuredEntries];
        NSUInteger currentRow = [self.entries indexOfObject:original];
        if (currentRow == NSNotFound) return;
        NSMutableDictionary *entry = [original mutableCopy];
        entry[@"selector"] = selector;
        self.entries[currentRow] = entry;
        [self save];
        [self.table reloadData];
    };
    [self pushPicker:picker];
}
// 名称编辑保留独立页面；图标不提供条目覆盖。
- (void)pushAppearanceEditorAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.entries.count) return;
    NSDictionary *original = self.entries[row];
    MTPPanelItemAppearanceController *editor = [[MTPPanelItemAppearanceController alloc] init];
    editor.entry = original;
    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSDictionary *updated) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![updated isKindOfClass:NSDictionary.class]) return;
        // Resolve against the latest saved items; a deleted reference stays deleted.
        strongSelf.entries = [strongSelf configuredEntries];
        NSUInteger currentRow = [strongSelf.entries indexOfObject:original];
        if (currentRow == NSNotFound) return;
        strongSelf.entries[currentRow] = updated;
        [strongSelf save];
        [strongSelf.table reloadData];
    };
    [editor setRootController:[self rootController]];
    [editor setParentController:[self parentController]];
    [self pushController:editor];
}
- (void)editDefinition:(NSDictionary *)definition {
    MTPLinkActionEditorController *editor = [[MTPLinkActionEditorController alloc] init];
    editor.entry = [definition mutableCopy];
    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSDictionary *saved) {
        NSMutableDictionary *preferences = [[[MTPrefsManager sharedInstance] readPrefs] mutableCopy];
        id stored = preferences[kLinkActionskey];
        if (![stored isKindOfClass:NSArray.class]) return;
        NSMutableArray *actions = [stored mutableCopy];
        for (NSUInteger index = 0; index < actions.count; index++) {
            if ([actions[index] isKindOfClass:NSDictionary.class] && [actions[index][@"selector"] isEqual:saved[@"selector"]]) {
                actions[index] = saved;
                preferences[kLinkActionskey] = actions;
                [[MTPrefsManager sharedInstance] writePrefs:preferences];
                [weakSelf.previewHeader refresh];
                [weakSelf.table reloadData];
                break;
            }
        }
    };
    [editor setRootController:[self rootController]];
    [editor setParentController:[self parentController]];
    [self pushController:editor];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger row = indexPath.row;
    if (row < 0 || row >= (NSInteger)self.entries.count) return;
    NSDictionary *entry = self.entries[row];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:[self nameForEntry:entry] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [menu addAction:[UIAlertAction actionWithTitle:MTPanelLocalized(@"KEYBOARD_PANEL_ITEM_APPEARANCE") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf pushAppearanceEditorAtRow:row]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:MTPanelLocalized(@"KEYBOARD_PANEL_REPLACE_ACTION") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf replaceActionAtRow:row]; }]];
    NSDictionary *definition = [self customDefinitionForSelector:entry[@"selector"]];
    if (definition) [menu addAction:[UIAlertAction actionWithTitle:MTPanelLocalized(@"KEYBOARD_PANEL_EDIT_ACTION") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf editDefinition:definition]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:MTPanelLocalized(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
    menu.popoverPresentationController.sourceRect = menu.popoverPresentationController.sourceView.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
@end
