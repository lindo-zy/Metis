#import "MTPContextTypesController.h"
#import "MTPJavaScriptRuleController.h"
#import "MTContextClassifier.h"
#import "MTPPanelActionCatalog.h"
#import "MTPSubActionPickerController.h"
#import "MTPLinkActionEditorController.h"
#import "MTSettingsNavigation.h"
#import "MTBottomBarLayout.h"
#import "MTCollectionView.h"
#import "MTFloatingAppShelfView.h"
#import "common.h"

NSString *MTPCTX(NSString *key) { return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil]; }
NSString *MTPCTXTypeName(MTContextType *type) {
    return [type.kind isEqual:@"js"] ? type.name : MTPCTX([@"CTX_" stringByAppendingString:type.identifier.uppercaseString]);
}
void MTPCTXSaveTypes(NSString *group, NSArray<MTContextType *> *types) {
    NSDictionary *prefs = [MTPrefsManager.sharedInstance readPrefs];
    NSMutableDictionary *groups = [[MTContextGroupConfig migratePreferences:prefs][kContextGroupTypesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *entries = [NSMutableArray array]; for (MTContextType *type in types) [entries addObject:type.dictionaryRepresentation];
    groups[MTContextCanonicalGroup(group)] = entries;
    [MTPrefsManager.sharedInstance setValue:groups forKey:kContextGroupTypesKey];
    [[MTContextClassifier sharedClassifier] invalidate];
}
// The user-defined definition a slot selector points at, if any. Only custom
// actions carry an editable definition here: panels and built-in shortcuts are
// reference-only in this list (the sub-action list treats them the same way),
// and the synthesized context actions (url:open / url:search / ai:seed) have no
// definition at all.
static NSDictionary *MTPContextTypeActionDefinition(NSString *selector) {
    if (![selector isKindOfClass:NSString.class] || !selector.length) return nil;
    if (!MTIsLinkActionSelector(selector)) return nil;
    for (NSDictionary *entry in [MTPrefsManager.sharedInstance readPrefs][kLinkActionskey]) {
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return entry;
    }
    return nil;
}
@interface MTPContextTypesController ()
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) NSMutableArray<MTContextType *> *types;
@property(nonatomic, assign) NSUInteger slots;
@end
@implementation MTPContextTypesController
- (void)viewDidLoad {
    [super viewDidLoad]; self.groupKey = MTContextCanonicalGroup(self.groupKey);
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.rowHeight = UITableViewAutomaticDimension; self.table.estimatedRowHeight = 56;
    self.table.delegate = self; self.table.dataSource = self; self.table.editing = YES; self.table.allowsSelectionDuringEditing = YES;
    [self.view addSubview:self.table];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    MTContextGroupConfig *config = [MTContextGroupConfig configFromPreferences:[MTPrefsManager.sharedInstance readPrefs]];
    self.types = [[config typesForGroup:self.groupKey] mutableCopy]; self.slots = [config slotsForGroup:self.groupKey]; [self.table reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.types.count : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? MTPCTX(@"CTX_PRIORITY") : nil; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? [NSString stringWithFormat:MTPCTX(@"CTX_CAPACITY"), (unsigned long)self.slots] : MTPCTX(@"CTX_NEW_RULE_HINT");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.detailTextLabel.numberOfLines = 0;
    if (path.section == 1) { cell.textLabel.text = MTPCTX(@"CTX_ADD_JS"); cell.textLabel.textColor = UIColor.systemBlueColor; return cell; }
    MTContextType *type = self.types[path.row]; cell.textLabel.text = MTPCTXTypeName(type);
    NSString *first = type.actions.count ? MTPPanelDisplayDefinition([MTPrefsManager.sharedInstance readPrefs], type.actions.firstObject)[@"name"] : nil;
    if (!first && type.actions.count) first = MTPCTX([@"CTX_ACTION_" stringByAppendingString:type.actions.firstObject]);
    cell.detailTextLabel.text = [NSString stringWithFormat:MTPCTX(@"CTX_TYPE_SUMMARY"), (unsigned long)type.actions.count, first ?: MTPCTX(@"CTX_NO_ACTIONS")];
    if (!type.enabled) { cell.textLabel.textColor = UIColor.secondaryLabelColor; cell.detailTextLabel.text = [MTPCTX(@"CTX_DISABLED") stringByAppendingFormat:@" · %@", cell.detailTextLabel.text]; }
    UILabel *badge = [UILabel new]; badge.text = [type.kind isEqual:@"js"] ? @" JS " : MTPCTX(@"CTX_BUILTIN");
    badge.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; badge.textColor = [type.kind isEqual:@"js"] ? UIColor.systemBlueColor : UIColor.secondaryLabelColor; [badge sizeToFit]; cell.accessoryView = badge; cell.editingAccessoryView = badge; cell.showsReorderControl = YES;
    return cell;
}
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path { return path.section == 0; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path { return path.section == 0 && [self.types[path.row].kind isEqual:@"js"] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone; }
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)destination { return destination.section == 0 ? destination : source; }
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    MTContextType *type = self.types[source.row]; [self.types removeObjectAtIndex:source.row]; [self.types insertObject:type atIndex:destination.row]; MTPCTXSaveTypes(self.groupKey, self.types); [self.table reloadData];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style == UITableViewCellEditingStyleDelete && path.section == 0 && [self.types[path.row].kind isEqual:@"js"]) { [self.types removeObjectAtIndex:path.row]; MTPCTXSaveTypes(self.groupKey, self.types); [self.table reloadData]; }
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; MTContextType *type;
    if (path.section == 1) {
        NSUInteger count = 0; for (MTContextType *entry in self.types) if ([entry.kind isEqual:@"js"]) count++;
        if (count >= 16) return;
        type = [MTContextType new]; type.kind = @"js"; type.identifier = [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""]; type.name = MTPCTX(@"CTX_NEW_RULE"); type.enabled = YES;
        type.source = @"function match(text) {\n  return /^[\\w.+-]+@[\\w-]+\\.[\\w.]+$/.test(text);\n}";
        type.actions = @[]; [self.types addObject:type]; MTPCTXSaveTypes(self.groupKey, self.types);
    } else type = self.types[path.row];
    MTPContextTypeActionsController *page = [type.kind isEqual:@"js"] ? [MTPJavaScriptRuleController new] : [MTPContextTypeActionsController new];
    page.groupKey = self.groupKey; page.typeID = type.identifier; page.title = MTPCTXTypeName(type); MTSettingsPushController(self, page, nil, YES);
}
@end

@implementation MTPContextTypeActionsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped]; self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.rowHeight = UITableViewAutomaticDimension; self.table.estimatedRowHeight = 56;
    self.table.delegate = self; self.table.dataSource = self; self.table.editing = YES; self.table.allowsSelectionDuringEditing = YES; [self.view addSubview:self.table];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadType]; }
- (void)reloadType {
    MTContextGroupConfig *config = [MTContextGroupConfig configFromPreferences:[MTPrefsManager.sharedInstance readPrefs]];
    self.type = nil; for (MTContextType *type in [config typesForGroup:self.groupKey]) if ([type.identifier isEqual:self.typeID]) self.type = type;
    self.slots = [config slotsForGroup:self.groupKey]; [self.table reloadData]; [self installPreview];
}
- (void)installPreview {
    if (!self.type) return;
    NSDictionary *prefs = [MTPrefsManager.sharedInstance readPrefs];
    MTCollectionView *host = [[MTCollectionView alloc] initWithConfiguration:@"bottom" preview:YES]; host.bottomActionHostOnly = YES; [host configurePreviewWithPreferences:prefs];
    NSMutableArray *actions = [NSMutableArray array];
    for (NSUInteger i = 0; i < MIN(self.slots, self.type.actions.count); i++) {
        NSString *selector = self.type.actions[i];
        BOOL contextual = [@[@"url:open", @"url:search", @"ai:seed"] containsObject:selector];
        NSString *symbol = [selector isEqual:@"url:open"] ? @"link" : ([selector isEqual:@"ai:seed"] ? @"sparkles" : @"magnifyingglass");
        [actions addObject:[MTContextAction actionWithIdentifier:contextual ? selector : [@"configured:" stringByAppendingString:selector] title:contextual ? MTPCTX([@"CTX_ACTION_" stringByAppendingString:selector]) : selector symbol:symbol payloadKind:contextual ? MTContextPayloadURL : MTContextPayloadSelector payload:selector]];
    }
    NSDictionary *mapping = @{@"delete":@(MTContextGroupDelete), @"selection":@(MTContextGroupSelection), @"copy":@(MTContextGroupCopy), @"paste":@(MTContextGroupPaste), @"typing":@(MTContextGroupTyping)};
    MTContextDecision *decision = [MTContextDecision decisionWithGroup:[mapping[self.groupKey] integerValue] reason:@"preview" actions:actions ttl:0];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,CGRectGetWidth(self.view.bounds),110)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20,4,CGRectGetWidth(header.bounds)-40,40)]; label.text = [NSString stringWithFormat:MTPCTX(@"CTX_CAPACITY"), (unsigned long)self.slots]; label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; label.textColor = UIColor.secondaryLabelColor; label.numberOfLines = 0; label.autoresizingMask = UIViewAutoresizingFlexibleWidth; [header addSubview:label];
    host.frame = CGRectMake(0,48,CGRectGetWidth(header.bounds),56); host.autoresizingMask = UIViewAutoresizingFlexibleWidth; [header addSubview:host];
    MTFloatingAppShelfView *preview = [[MTFloatingAppShelfView alloc] initForPreview]; preview.actionTarget = host; preview.frame = host.bounds; preview.autoresizingMask = UIViewAutoresizingFlexibleWidth; [host addSubview:preview]; [preview configurePreviewWithPreferences:prefs decision:decision]; header.userInteractionEnabled = NO;
    self.table.tableHeaderView = header;
}
- (void)saveType {
    NSMutableArray *types = [[[MTContextGroupConfig configFromPreferences:[MTPrefsManager.sharedInstance readPrefs]] typesForGroup:self.groupKey] mutableCopy];
    for (NSUInteger i = 0; i < types.count; i++) if ([((MTContextType *)types[i]).identifier isEqual:self.typeID]) { types[i] = self.type; break; }
    MTPCTXSaveTypes(self.groupKey, types); [self.table reloadData]; [self installPreview];
}
- (void)pushPage:(UIViewController *)page { MTSettingsPushController(self, page, nil, YES); }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : self.type.actions.count + 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 1 ? MTPCTX(@"CTX_ACTIONS") : nil; }
- (UITableViewCell *)actionCellAtIndex:(NSUInteger)index {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (index >= self.type.actions.count) { cell.textLabel.text = MTPCTX(@"CTX_ADD_ACTION"); cell.textLabel.textColor = self.type.actions.count < 8 ? UIColor.systemBlueColor : UIColor.secondaryLabelColor; return cell; }
    NSString *selector = self.type.actions[index];
    cell.textLabel.text = MTPPanelDisplayDefinition([MTPrefsManager.sharedInstance readPrefs], selector)[@"name"] ?: MTPCTX([@"CTX_ACTION_" stringByAppendingString:selector]);
    cell.detailTextLabel.text = index >= self.slots ? MTPCTX(@"CTX_OVER_CAPACITY") : (index == 0 ? MTPCTX(@"CTX_DEFAULT") : [NSString stringWithFormat:MTPCTX(@"CTX_SLOT"), (unsigned long)index + 1]);
    cell.textLabel.textColor = index >= self.slots ? UIColor.tertiaryLabelColor : UIColor.labelColor; cell.showsReorderControl = YES; return cell;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 1) return [self actionCellAtIndex:path.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.textLabel.text = MTPCTX(@"CTX_ENABLED");
    UISwitch *toggle = [UISwitch new]; toggle.on = self.type.enabled; [toggle addTarget:self action:@selector(toggleEnabled:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; cell.editingAccessoryView = toggle; return cell;
}
- (void)toggleEnabled:(UISwitch *)sender { self.type.enabled = sender.on; [self saveType]; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path { return path.section == [self numberOfSectionsInTableView:tableView] - 1 && path.row < self.type.actions.count; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path { return [self tableView:tableView canMoveRowAtIndexPath:path] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone; }
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)destination { return source.section == destination.section && destination.row < self.type.actions.count ? destination : source; }
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    NSMutableArray *actions = [self.type.actions mutableCopy]; NSString *item = actions[source.row]; [actions removeObjectAtIndex:source.row]; [actions insertObject:item atIndex:destination.row]; self.type.actions = actions; [self saveType];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style == UITableViewCellEditingStyleDelete && [self tableView:tableView canMoveRowAtIndexPath:path]) { NSMutableArray *actions = [self.type.actions mutableCopy]; [actions removeObjectAtIndex:path.row]; self.type.actions = actions; [self saveType]; }
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section != 1) return;
    if (path.row >= (NSInteger)self.type.actions.count) { [self addAction]; return; }
    [self editActionAtRow:path.row];
}
- (void)addAction {
    // 动作组规则添加动作只允许从动作列表挑选，不再提供快捷子项菜单。
    if (self.type.actions.count >= 8) return;
    __weak typeof(self) weakSelf = self;
    MTPSubActionPickerController *picker = [MTPSubActionPickerController new];
    picker.actionContextKind = MTPanelKeyboardKind; picker.fullOrder = MTPPanelBuiltInActions();
    picker.title = MTPCTX(@"CTX_ADD_ACTION");
    picker.completion = ^(NSString *selector) {
        MTPContextTypeActionsController *owner = weakSelf; if (!owner || owner.type.actions.count >= 8 || !MTContextActionAllowed(selector, [MTPrefsManager.sharedInstance readPrefs])) return;
        owner.type.actions = [owner.type.actions arrayByAddingObject:selector]; [owner saveType];
    };
    [self pushPage:picker];
}
// Tapping an action row opens its configuration, mirroring the sub-action
// list: a user-defined action opens the editor for its shared definition (the
// change is global — every reference to that selector follows), while an
// action without a definition (built-in shortcuts, panels, url:open /
// url:search / ai:seed) is replaced through the same catalog the add row uses.
- (void)editActionAtRow:(NSUInteger)row {
    if (row >= self.type.actions.count) return;
    NSString *selector = self.type.actions[row];
    NSDictionary *definition = MTPContextTypeActionDefinition(selector);
    __weak typeof(self) weakSelf = self;
    if ([definition isKindOfClass:NSDictionary.class]) {
        MTPLinkActionEditorController *editor = [MTPLinkActionEditorController new];
        editor.entry = [definition mutableCopy];
        editor.completion = ^(NSDictionary *savedEntry) {
            MTPContextTypeActionsController *owner = weakSelf;
            if (!owner || ![savedEntry isKindOfClass:NSDictionary.class] || ![savedEntry[@"selector"] isEqual:selector]) return;
            // The definition lives in its own store, not in the group config:
            // rewrite the whole domain so other keys survive the replace-style
            // writePrefs of this unsandboxed process.
            NSMutableDictionary *prefs = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
            NSMutableArray *linkActions = [NSMutableArray array];
            for (NSDictionary *entry in prefs[kLinkActionskey]) {
                if (![entry isKindOfClass:NSDictionary.class]) continue;
                [linkActions addObject:[entry[@"selector"] isEqual:selector] ? [savedEntry mutableCopy] : [entry mutableCopy]];
            }
            prefs[kLinkActionskey] = linkActions;
            [MTPrefsManager.sharedInstance writePrefs:prefs];
            [owner.table reloadData]; [owner installPreview];
        };
        [self pushPage:editor];
        return;
    }
    MTPSubActionPickerController *picker = [MTPSubActionPickerController new];
    picker.actionContextKind = MTPanelKeyboardKind; picker.fullOrder = MTPPanelBuiltInActions();
    picker.selectedSelector = selector; picker.title = MTPCTX(@"KEYBOARD_PANEL_REPLACE_ACTION");
    picker.completion = ^(NSString *replacement) {
        MTPContextTypeActionsController *owner = weakSelf;
        if (!owner || !replacement.length || row >= owner.type.actions.count) return;
        if ([owner.type.actions[row] isEqual:replacement]) return;
        if (!MTContextActionAllowed(replacement, [MTPrefsManager.sharedInstance readPrefs])) return;
        NSMutableArray *actions = [owner.type.actions mutableCopy];
        actions[row] = replacement; owner.type.actions = actions; [owner saveType];
    };
    [self pushPage:picker];
}
@end
