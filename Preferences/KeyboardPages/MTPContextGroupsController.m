#import "MTPContextGroupsController.h"
#import "MTPSubActionPickerController.h"
#import "MTPPanelActionCatalog.h"
#import "MTContextGroupEngine.h"
#import "MTCollectionView.h"
#import "MTFloatingAppShelfView.h"
#import "MTHelper.h"
#import "common.h"
#import <Preferences/PSSpecifier.h>

static NSString *MTCGL(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}
static NSArray *MTCGKeys(void) {
    return @[kContextSelectionGroupKey, kContextClipboardGroupKey, kContextPasteGroupKey, kContextInputGroupKey, kContextIdleGroupKey, kFloatingShelfEnabledKey, kContextGroupsEnabledKey];
}
static NSArray *MTCGTitles(void) {
    return @[@"CONTEXT_SELECTION", @"CONTEXT_CLIPBOARD", @"CONTEXT_PASTE", @"CONTEXT_INPUT", @"CONTEXT_IDLE", @"CONTEXT_FLOATING", @"CONTEXT_GROUPS_SWITCH"];
}
static NSString *MTCGTitle(MTContextGroup group) {
    return MTCGL(MTCGTitles()[group == MTContextGroupIdle ? 4 : group - MTContextGroupSelection]);
}

@interface MTPContextActionsController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property(nonatomic, copy) NSString *groupKey;
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) NSMutableArray<NSString *> *selectors;
@end

@implementation MTPContextActionsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.delegate = self; self.table.dataSource = self; self.table.editing = YES; self.table.allowsSelectionDuringEditing = YES;
    [self.view addSubview:self.table];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addAction)];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    id groups = [MTPrefsManager.sharedInstance readPrefs][kContextActionsKey];
    id stored = [groups isKindOfClass:NSDictionary.class] ? groups[self.groupKey] : nil;
    self.selectors = [NSMutableArray array];
    for (id value in [stored isKindOfClass:NSArray.class] ? stored : @[]) {
        if ([value isKindOfClass:NSString.class] && [value length] && ![self.selectors containsObject:value] && self.selectors.count < 3) [self.selectors addObject:value];
    }
    [self.table reloadData];
}
- (void)saveAutomatic:(BOOL)automatic {
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    NSDictionary *prefs = [manager readPrefs];
    id stored = prefs[kContextActionsKey];
    NSMutableDictionary *groups = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    if (automatic) [groups removeObjectForKey:self.groupKey]; else groups[self.groupKey] = [self.selectors copy];
    [manager setValue:groups forKey:kContextActionsKey];
    [self.table reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.selectors.count : 2; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        NSDictionary *stored = [MTPrefsManager.sharedInstance readPrefs][kContextActionsKey];
        BOOL configured = [stored isKindOfClass:NSDictionary.class] && [stored[self.groupKey] isKindOfClass:NSArray.class];
        return [NSString stringWithFormat:@"%@\n%@", MTCGL(configured ? @"CONTEXT_STATE_CONFIGURED" : @"CONTEXT_STATE_AUTOMATIC"), MTCGL(@"CONTEXT_ACTIONS_FOOTER")];
    }
    return MTCGL(@"CONTEXT_AUTOMATIC_FOOTER");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (path.section == 0) {
        NSDictionary *prefs = [MTPrefsManager.sharedInstance readPrefs];
        NSDictionary *definition = MTPPanelDisplayDefinition(prefs, self.selectors[path.row]);
        cell.textLabel.text = definition[@"name"] ?: MTCGL(@"CONTEXT_MISSING_ACTION");
        cell.showsReorderControl = YES;
    } else {
        cell.textLabel.text = MTCGL(path.row == 0 ? @"CONTEXT_USE_AUTOMATIC" : @"CONTEXT_CLEAR_ACTIONS");
        cell.textLabel.textColor = path.row == 0 ? UIColor.systemBlueColor : UIColor.systemRedColor;
    }
    return cell;
}
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path { return path.section == 0; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path { return path.section == 0 ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path { return path.section == 0; }
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)destination { return destination.section == 0 ? destination : source; }
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    NSString *selector = self.selectors[source.row]; [self.selectors removeObjectAtIndex:source.row]; [self.selectors insertObject:selector atIndex:destination.row]; [self saveAutomatic:NO];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style == UITableViewCellEditingStyleDelete && path.section == 0) { [self.selectors removeObjectAtIndex:path.row]; [self saveAutomatic:NO]; }
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section != 1) return;
    [self.selectors removeAllObjects]; [self saveAutomatic:path.row == 0];
}
- (void)addAction {
    if (self.selectors.count >= 3) return;
    MTPSubActionPickerController *picker = [MTPSubActionPickerController new];
    picker.actionContextKind = MTPanelKeyboardKind; picker.fullOrder = MTPPanelBuiltInActions();
    picker.title = MTCGL(@"CHOOSE_ACTION");
    __weak typeof(self) weakSelf = self;
    picker.completion = ^(NSString *selector) {
        MTPContextActionsController *owner = weakSelf;
        NSDictionary *prefs = [MTPrefsManager.sharedInstance readPrefs];
        if (!owner || owner.selectors.count >= 3 || [owner.selectors containsObject:selector] || !MTPanelItemAllowed(prefs, selector, MTPanelKeyboardKind)) return;
        [owner.selectors addObject:selector]; [owner saveAutomatic:NO];
    };
    [picker setRootController:self.rootController]; [picker setParentController:self]; [self pushController:picker];
}
@end

@interface MTPContextGroupsController () <UITableViewDelegate, UITableViewDataSource>
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, copy) NSDictionary *preferences;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *priority;
@property(nonatomic, strong) UIView *previewHeader;
@property(nonatomic, strong) UILabel *previewTitle;
@property(nonatomic, strong) UISegmentedControl *scenario;
@property(nonatomic, strong) MTCollectionView *fixedPreview;
@property(nonatomic, strong) MTFloatingAppShelfView *contextPreview;
@end

@implementation MTPContextGroupsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTCGL(@"CONTEXT_GROUPS_TITLE");
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.delegate = self; self.table.dataSource = self;
    self.table.editing = YES; self.table.allowsSelectionDuringEditing = YES;
    [self.view addSubview:self.table];
    self.previewHeader = [UIView new];
    self.previewTitle = [UILabel new]; self.previewTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.previewTitle.textColor = UIColor.secondaryLabelColor; self.previewTitle.text = MTCGL(@"CONTEXT_PREVIEW_TITLE");
    [self.previewHeader addSubview:self.previewTitle];
    self.scenario = [[UISegmentedControl alloc] initWithItems:@[MTCGL(@"CONTEXT_DEFAULT"), MTCGL(@"CONTEXT_SELECTION"), MTCGL(@"CONTEXT_CLIPBOARD"), MTCGL(@"CONTEXT_PASTE"), MTCGL(@"CONTEXT_INPUT"), MTCGL(@"CONTEXT_IDLE")]];
    [self.scenario setTitleTextAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11]} forState:UIControlStateNormal];
    self.scenario.selectedSegmentIndex = 0;
    [self.scenario addTarget:self action:@selector(refreshPreview) forControlEvents:UIControlEventValueChanged];
    [self.previewHeader addSubview:self.scenario];
    self.fixedPreview = [[MTCollectionView alloc] initWithConfiguration:@"bottom" preview:YES];
    self.fixedPreview.visibleItemLimit = 3;
    [self.previewHeader addSubview:self.fixedPreview];
    self.contextPreview = [[MTFloatingAppShelfView alloc] initForPreview];
    self.contextPreview.actionTarget = self.fixedPreview;
    [self.previewHeader addSubview:self.contextPreview];
    self.table.tableHeaderView = self.previewHeader;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }
- (void)refresh {
    self.preferences = [MTPrefsManager.sharedInstance readPrefs];
    self.priority = [MTContextPriority(self.preferences) mutableCopy];
    [self.table reloadData]; [self refreshPreview];
}
- (void)refreshPreview {
    [self.fixedPreview configurePreviewWithPreferences:self.preferences];
    MTContextSnapshot *snapshot = [MTContextSnapshot new]; snapshot.inputAvailable = YES;
    snapshot.inputLength = 12; snapshot.pasteAge = -1;
    switch (self.scenario.selectedSegmentIndex) {
        case 1: snapshot.selectionText = @"Metis"; snapshot.selectionLength = 5; break;
        case 2: snapshot.clipboardAvailable = YES; snapshot.clipboardText = @"Metis"; break;
        case 3: snapshot.pastedLength = 30; snapshot.pasteAge = 0; break;
        case 4: snapshot.contentType = @"oneTimeCode"; snapshot.clipboardAvailable = YES; snapshot.clipboardAge = 100; break;
        case 5: snapshot.inputLength = 0; break;
        default: break;
    }
    MTContextDecision *decision = [MTContextGroupEngine decisionForSnapshot:snapshot settings:[MTContextGroupSettings settingsFromPreferences:self.preferences]];
    [self.contextPreview configurePreviewWithPreferences:self.preferences decision:decision];
    [self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.table.bounds);
    CGRect headerFrame = CGRectMake(0, 0, width, 145);
    if (!CGRectEqualToRect(self.previewHeader.frame, headerFrame)) {
        self.previewHeader.frame = headerFrame;
        self.table.tableHeaderView = self.previewHeader;
    }
    self.previewTitle.frame = CGRectMake(20, 8, MAX(0, width - 40), 22);
    self.scenario.frame = CGRectMake(16, 35, MAX(0, width - 32), 32);
    CGFloat strip = MAX(0, width - MTBottomToolbarLeadingInset - MTBottomToolbarTrailingInset);
    CGFloat fixed = strip * MTBottomFixedFraction(self.preferences);
    self.fixedPreview.frame = CGRectMake(MTBottomToolbarLeadingInset, 72, fixed, 65);
    self.contextPreview.frame = CGRectMake(MTBottomToolbarLeadingInset + fixed, 72, strip - fixed, 65);
    [self.fixedPreview.collectionViewLayout invalidateLayout];

}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 7 : (section == 1 ? self.priority.count : 5); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return MTCGL(@[@"CONTEXT_ENABLED_GROUPS", @"CONTEXT_PRIORITY", @"CONTEXT_BEHAVIOR"][section]); }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return MTCGL(@[@"CONTEXT_LAYOUT_FOOTER", @"CONTEXT_PRIORITY_FOOTER", @"CONTEXT_BEHAVIOR_FOOTER"][section]); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (path.section == 0) {
        cell.textLabel.text = MTCGL(MTCGTitles()[path.row]);
        cell.detailTextLabel.text = MTCGL(@[@"CONTEXT_SELECTION_HINT", @"CONTEXT_CLIPBOARD_HINT", @"CONTEXT_PASTE_HINT", @"CONTEXT_INPUT_HINT", @"CONTEXT_IDLE_HINT", @"CONTEXT_FLOATING_HINT", @"CONTEXT_MASTER_HINT"][path.row]);
        cell.detailTextLabel.numberOfLines = 0;
        UISwitch *toggle = [UISwitch new]; toggle.tag = path.row;
        id value = self.preferences[MTCGKeys()[path.row]];
        toggle.on = [value isKindOfClass:NSNumber.class] ? [value boolValue] : (path.row < 4 || path.row == 6);
        [toggle addTarget:self action:@selector(toggleGroup:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (path.section == 1) {
        cell.textLabel.text = [NSString stringWithFormat:@"%ld  %@", (long)path.row + 1, MTCGTitle(self.priority[path.row].integerValue)];
        cell.showsReorderControl = YES;
    } else {
        NSString *key = @[kContextDebounceKey, kContextClipboardFreshnessKey, kContextPasteFreshnessKey, kContextLockKey, kContextSlotsKey][path.row];
        NSArray *defaults = @[@200, @8, @3, @5, @3], *low = @[@0, @2, @1, @0, @1], *high = @[@1000, @60, @15, @15, @3];
        double value = MTContextNumber(self.preferences, key, [defaults[path.row] doubleValue], [low[path.row] doubleValue], [high[path.row] doubleValue]);
        cell.textLabel.text = MTCGL(@[@"CONTEXT_DEBOUNCE", @"CONTEXT_CLIPBOARD_TTL", @"CONTEXT_PASTE_TTL", @"CONTEXT_LOCK", @"CONTEXT_SLOTS"][path.row]);
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f %@", value, MTCGL(path.row == 0 ? @"CONTEXT_MS" : (path.row == 4 ? @"CONTEXT_CELLS" : @"CONTEXT_SECONDS"))];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)toggleGroup:(UISwitch *)sender { [MTPrefsManager.sharedInstance setValue:@(sender.on) forKey:MTCGKeys()[sender.tag]]; [self refresh]; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path { return path.section == 1; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path { return NO; }
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)destination { return destination.section == 1 ? destination : source; }
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    NSNumber *group = self.priority[source.row]; [self.priority removeObjectAtIndex:source.row]; [self.priority insertObject:group atIndex:destination.row];
    [MTPrefsManager.sharedInstance setValue:self.priority forKey:kContextPriorityKey]; [self refresh];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0) {
        if (path.row == 5) { [self openFloatingApps]; return; }
        if (path.row == 6) return;
        MTPContextActionsController *editor = [MTPContextActionsController new];
        editor.groupKey = @[@"selection", @"clipboard", @"paste", @"input", @"idle"][path.row]; editor.title = MTCGL(MTCGTitles()[path.row]);
        [editor setRootController:self.rootController]; [editor setParentController:self]; [self pushController:editor];
    } else if (path.section == 2) { [self chooseBehavior:path.row]; }
}
- (void)openFloatingApps {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:MTCGL(@"CONTEXT_FLOATING") target:self set:@selector(setFloatingApps:specifier:) get:@selector(floatingApps:) detail:NSClassFromString(@"ATLApplicationListMultiSelectionController") cell:PSLinkListCell edit:nil];
    [item setProperty:kKbdHandleAppsKey forKey:@"key"];
    [item setProperty:@[] forKey:@"default"];
    [item setProperty:@NO forKey:@"defaultApplicationSwitchValue"];
    [item setProperty:@[@{@"sectionType": @"User"}, @{@"sectionType": @"System"}] forKey:@"sections"];
    [item setProperty:@YES forKey:@"useSearchBar"];
    [item setProperty:kIdentifier forKey:@"defaults"];
    PSViewController *controller = [NSClassFromString(@"ATLApplicationListMultiSelectionController") new];
    [controller setSpecifier:item]; [controller setRootController:self.rootController]; [controller setParentController:self]; [self pushController:controller];
}
- (id)floatingApps:(PSSpecifier *)specifier { return MTKbdHandleAppsFromPreferences([MTPrefsManager.sharedInstance readPrefs]); }
- (void)setFloatingApps:(id)value specifier:(PSSpecifier *)specifier {
    if ([value isKindOfClass:NSArray.class]) [MTPrefsManager.sharedInstance setValue:value forKey:kKbdHandleAppsKey];
}
- (void)chooseBehavior:(NSInteger)row {
    NSArray *choices = @[@[@0, @100, @200, @300, @500, @1000], @[@2, @5, @8, @15, @30, @60], @[@1, @2, @3, @5, @10, @15], @[@0, @1, @3, @5, @10, @15], @[@1, @2, @3]][row];
    NSString *key = @[kContextDebounceKey, kContextClipboardFreshnessKey, kContextPasteFreshnessKey, kContextLockKey, kContextSlotsKey][row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTCGL(@[@"CONTEXT_DEBOUNCE", @"CONTEXT_CLIPBOARD_TTL", @"CONTEXT_PASTE_TTL", @"CONTEXT_LOCK", @"CONTEXT_SLOTS"][row]) message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *value in choices) [alert addAction:[UIAlertAction actionWithTitle:value.stringValue style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [MTPrefsManager.sharedInstance setValue:value forKey:key]; [weakSelf refresh];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:MTCGL(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
