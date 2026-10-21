#import "MTPContextGroupsController.h"
#import "MTBottomBarLayout.h"
#import "MTPGesturePickerController.h"
#import "MTPOpenAppPickerController.h"
#import "MTPAppInfo.h"
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
    self.navigationItem.rightBarButtonItem.enabled = self.selectors.count < 3;
    [self.table reloadData];
}
- (void)saveAutomatic:(BOOL)automatic {
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    NSDictionary *prefs = [manager readPrefs];
    id stored = prefs[kContextActionsKey];
    NSMutableDictionary *groups = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    if (automatic) [groups removeObjectForKey:self.groupKey]; else groups[self.groupKey] = [self.selectors copy];
    [manager setValue:groups forKey:kContextActionsKey];
    self.navigationItem.rightBarButtonItem.enabled = self.selectors.count < 3;
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

// Reuse the toolbar's appearance controls and input avoidance on the unified
// page; only their section mapping changes. No second bottom settings screen.
@interface MTPManageShortcutsController (BottomArrangementControls)
@property(nonatomic, copy) NSDictionary *toolbarPreviewPreferences;
- (void)buildSettingsRows;
- (MTPToolbarSettingsRow *)settingsRowForIndexPath:(NSIndexPath *)path;
- (void)installToolbarPreview;
- (void)refreshToolbarPreview;
- (void)applyToolbarPreviewPreferences:(NSDictionary *)preferences;
- (void)layoutToolbarPreviewHeader;
@end

@interface MTPContextGroupsController ()
@property(nonatomic, copy) NSDictionary *preferences;
@property(nonatomic, strong) NSMutableDictionary *layout;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *priority;
@property(nonatomic, strong) UIView *previewHeader;
@property(nonatomic, strong) UIView *previewDock;
@property(nonatomic, strong) UILabel *previewTitle;
@property(nonatomic, strong) UILabel *previewMetrics;
@property(nonatomic, strong) UISegmentedControl *scenario;
@property(nonatomic, strong) MTCollectionView *actionHost;
@property(nonatomic, strong) MTFloatingAppShelfView *barPreview;
@property(nonatomic, strong) UIImageView *globe;
@property(nonatomic, strong) UIImageView *microphone;
@end

@implementation MTPContextGroupsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTCGL(@"BAR_TITLE");
    self.navigationItem.rightBarButtonItem = nil;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }
- (void)updateOrder:(BOOL)reset {
    // Keep all legacy definitions/bindings intact. Arrangement is authoritative
    // for visibility, so the old fixed-button capacity normalizer must not run.
    self.fullOrder = MTPPanelBuiltInActions();
}
- (NSInteger)testInputSection { return 6; }
- (void)buildSettingsRows {
    [super buildSettingsRows];
    self.appearanceRows = [self.appearanceRows subarrayWithRange:NSMakeRange(1, self.appearanceRows.count - 1)];
}
- (void)refresh {
    self.preferences = [MTPrefsManager.sharedInstance readPrefs];
    NSDictionary *layout = MTBottomBarLayout(self.preferences);
    if (![self.preferences[kBottomBarLayoutKey] isEqual:layout]) {
        [MTPrefsManager.sharedInstance setValue:layout forKey:kBottomBarLayoutKey];
        self.preferences = [MTPrefsManager.sharedInstance readPrefs];
    }
    self.layout = [layout mutableCopy];
    self.priority = [MTContextPriority(self.preferences) mutableCopy];
    [self.tableView reloadData]; [self refreshToolbarPreview];
}
- (void)saveLayout {
    NSMutableDictionary *snapshot = [self.preferences mutableCopy]; snapshot[kBottomBarLayoutKey] = self.layout;
    [MTPrefsManager.sharedInstance setValue:MTBottomBarLayout(snapshot) forKey:kBottomBarLayoutKey];
    [self refresh];
}
- (void)pushPage:(PSViewController *)controller {
    if (!controller) return;
    [controller setRootController:self.rootController]; [controller setParentController:self]; [self pushController:controller];
}
- (void)installToolbarPreview {
    self.previewHeader = [UIView new];
    self.previewTitle = [UILabel new]; self.previewTitle.text = MTCGL(@"BAR_PREVIEW");
    self.previewTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; self.previewTitle.textColor = UIColor.secondaryLabelColor;
    [self.previewHeader addSubview:self.previewTitle];
    self.scenario = [[UISegmentedControl alloc] initWithItems:@[MTCGL(@"CONTEXT_DEFAULT"), MTCGL(@"CONTEXT_SELECTION"), MTCGL(@"CONTEXT_CLIPBOARD"), MTCGL(@"CONTEXT_PASTE"), MTCGL(@"CONTEXT_INPUT"), MTCGL(@"CONTEXT_IDLE")]];
    [self.scenario setTitleTextAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:11]} forState:UIControlStateNormal];
    self.scenario.selectedSegmentIndex = 0; [self.scenario addTarget:self action:@selector(refreshToolbarPreview) forControlEvents:UIControlEventValueChanged];
    [self.previewHeader addSubview:self.scenario];
    self.previewDock = [UIView new]; self.previewDock.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.previewDock.layer.cornerRadius = 12; self.previewDock.userInteractionEnabled = NO;
    [self.previewHeader addSubview:self.previewDock];
    self.actionHost = [[MTCollectionView alloc] initWithConfiguration:@"bottom" preview:YES];
    self.actionHost.bottomActionHostOnly = YES;
    [self.previewDock addSubview:self.actionHost];
    self.barPreview = [[MTFloatingAppShelfView alloc] initForPreview]; self.barPreview.actionTarget = self.actionHost;
    [self.previewDock addSubview:self.barPreview];
    self.globe = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"globe"]];
    self.microphone = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"mic"]];
    for (UIImageView *view in @[self.globe, self.microphone]) { view.contentMode = UIViewContentModeScaleAspectFit; view.tintColor = UIColor.secondaryLabelColor; [self.previewDock addSubview:view]; }
    self.previewMetrics = [UILabel new]; self.previewMetrics.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.previewMetrics.textColor = UIColor.secondaryLabelColor; self.previewMetrics.numberOfLines = 0;
    [self.previewHeader addSubview:self.previewMetrics];
    self.tableView.tableHeaderView = self.previewHeader;
}
- (void)refreshToolbarPreview { [self applyToolbarPreviewPreferences:[MTPrefsManager.sharedInstance readPrefs]]; }
- (void)applyToolbarPreviewPreferences:(NSDictionary *)preferences {
    self.toolbarPreviewPreferences = preferences;
    [self.actionHost configurePreviewWithPreferences:preferences];
    MTContextSnapshot *snapshot = [MTContextSnapshot new]; snapshot.inputAvailable = YES; snapshot.inputLength = 12; snapshot.pasteAge = -1;
    switch (self.scenario.selectedSegmentIndex) {
        case 1: snapshot.selectionText = @"Metis"; snapshot.selectionLength = 5; break;
        case 2: snapshot.clipboardAvailable = YES; snapshot.clipboardText = @"Metis"; break;
        case 3: snapshot.pastedLength = 30; snapshot.pasteAge = 0; break;
        case 4: snapshot.contentType = @"oneTimeCode"; snapshot.clipboardAvailable = YES; snapshot.clipboardAge = 100; break;
        case 5: snapshot.inputLength = 0; break;
        default: break;
    }
    MTContextDecision *decision = [MTContextGroupEngine decisionForSnapshot:snapshot settings:[MTContextGroupSettings settingsFromPreferences:preferences]];
    if (decision.group == MTContextGroupDefault || decision.group == MTContextGroupNone) decision = nil;
    [self.barPreview configurePreviewWithPreferences:preferences decision:decision];
    [self layoutToolbarPreviewHeader];
}
- (void)layoutToolbarPreviewHeader {
    if (!self.previewHeader) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    CGFloat dockHeight = MTContextNumber(self.toolbarPreviewPreferences, kHeightOffsetkey, heightOffsetDefault, 50, 80);
    CGFloat strip = MAX(0, width - MTBottomToolbarLeadingInset - MTBottomToolbarTrailingInset);
    self.previewTitle.frame = CGRectMake(20, 8, MAX(0, width - 40), 22);
    self.scenario.frame = CGRectMake(16, 36, MAX(0, width - 32), 32);
    self.previewDock.frame = CGRectMake(0, 78, width, dockHeight + MTBottomToolbarBottomInset);
    self.actionHost.frame = CGRectMake(MTBottomToolbarLeadingInset, 0, strip, dockHeight);
    self.barPreview.frame = self.actionHost.frame;
    self.globe.frame = CGRectMake(20, MTBottomToolbarCellTopInset, 26, 28);
    self.microphone.frame = CGRectMake(MAX(0, width - 44), MTBottomToolbarCellTopInset, 24, 28);
    NSDictionary *layout = MTBottomBarLayout(self.toolbarPreviewPreferences);
    BOOL single = [layout[@"single"] boolValue]; NSUInteger left = [layout[@"left"] count], right = single ? 0 : [layout[@"right"] count];
    CGFloat fraction = MTBottomBarLeftFraction(layout);
    self.previewMetrics.text = [NSString stringWithFormat:MTCGL(@"BAR_METRICS"), (unsigned long)left, (unsigned long)right, strip, left ? strip * fraction / left : 0, right ? strip * (1 - fraction) / right : 0];
    CGFloat top = CGRectGetMaxY(self.previewDock.frame) + 8;
    CGFloat metricHeight = [self.previewMetrics sizeThatFits:CGSizeMake(MAX(0, width - 40), CGFLOAT_MAX)].height;
    self.previewMetrics.frame = CGRectMake(20, top, MAX(0, width - 40), metricHeight);
    CGRect frame = CGRectMake(0, 0, width, top + metricHeight + 12);
    if (!CGRectEqualToRect(frame, self.previewHeader.frame)) { self.previewHeader.frame = frame; self.tableView.tableHeaderView = self.previewHeader; }
}
- (MTPToolbarSettingsRow *)settingsRowForIndexPath:(NSIndexPath *)path {
    return [super settingsRowForIndexPath:[NSIndexPath indexPathForRow:path.row inSection:path.section - 5]];
}
// Sections 0/1 hold the segments, 2 layout, 3 context groups, 4 priority,
// 5 behavior timing and 6-8 the shared appearance/panel/offset controls.
// Bottom bar long swipes are configured in the global gesture page only.
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 9; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < 2) return [self.layout[section ? @"right" : @"left"] count] + 1;
    if (section == 2) return 4;
    if (section == 3) return 7;
    if (section == 4) return self.priority.count;
    if (section == 5) return 4;
    return [super tableView:tableView numberOfRowsInSection:section - 5];
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section < 2) return [NSString stringWithFormat:@"%@ · %lu / 8", MTCGL(section ? @"BAR_RIGHT" : @"BAR_LEFT"), (unsigned long)[self.layout[section ? @"right" : @"left"] count]];
    if (section >= 6) return [super tableView:tableView titleForHeaderInSection:section - 5];
    return MTCGL(@{@2:@"BAR_LAYOUT", @3:@"CONTEXT_ENABLED_GROUPS", @4:@"CONTEXT_PRIORITY", @5:@"CONTEXT_BEHAVIOR"}[@(section)]);
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section < 2) return MTCGL(section == 1 && [self.layout[@"single"] boolValue] ? @"BAR_RIGHT_SAVED" : @"BAR_EDIT_HINT");
    if (section == 2) return MTCGL(@"BAR_LAYOUT_HINT");
    if (section == 3) return MTCGL(@"BAR_CONTEXT_HINT");
    if (section == 4) return MTCGL(@"CONTEXT_PRIORITY_FOOTER");
    if (section == 5) return MTCGL(@"CONTEXT_BEHAVIOR_FOOTER");
    if (section == 6) return nil;
    return [super tableView:tableView titleForFooterInSection:section - 5];
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return section == 6 ? [super tableView:tableView viewForHeaderInSection:1] : nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 6 ? [super tableView:tableView heightForHeaderInSection:1] : UITableViewAutomaticDimension;
}
- (NSString *)entryTitle:(NSDictionary *)entry {
    NSString *kind = entry[@"kind"], *value = entry[@"value"];
    if ([kind isEqual:@"action"]) {
        id sections = self.preferences[kShortcutskey];
        for (id section in [sections isKindOfClass:NSArray.class] ? sections : @[])
            for (id item in [section isKindOfClass:NSArray.class] ? section : @[])
                if ([item isKindOfClass:NSDictionary.class] && [item[@"selector"] isEqual:value]) {
                    NSString *name = [MTHelper customNameForShortcutItem:item]; if (name.length) return name;
                }
        return [self.actionHost subActionPanelTitleForSelector:value];
    }
    if ([kind isEqual:@"context"]) return [NSString stringWithFormat:@"%@ · %ld", MTCGL([@"BAR_CONTEXT_" stringByAppendingString:value.uppercaseString]), (long)[entry[@"index"] integerValue] + 1];
    return [MTPAppInfo displayNameForBundleID:value] ?: value;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section >= 6 && path.section <= 8) return [super tableView:tableView cellForRowAtIndexPath:path];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.detailTextLabel.numberOfLines = 0; cell.textLabel.numberOfLines = 0;
    if (path.section < 2) {
        NSArray *entries = self.layout[path.section ? @"right" : @"left"];
        if (path.row == entries.count) {
            cell.textLabel.text = MTCGL(entries.count < 8 ? @"BAR_ADD" : @"BAR_FULL"); cell.textLabel.textColor = entries.count < 8 ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
            cell.imageView.image = [UIImage systemImageNamed:@"plus.circle"];
        } else {
            NSDictionary *entry = entries[path.row]; cell.textLabel.text = [self entryTitle:entry];
            NSString *kind = entry[@"kind"];
            cell.detailTextLabel.text = MTCGL([@"BAR_KIND_" stringByAppendingString:kind.uppercaseString]);
            cell.imageView.image = [kind isEqual:@"action"] ? [self.actionHost subActionPanelImageForSelector:entry[@"value"]] : [UIImage systemImageNamed:[kind isEqual:@"app"] ? @"app" : @"square.stack.3d.up"];
            cell.showsReorderControl = YES;
        }
    } else if (path.section == 2) {
        if (path.row == 0) {
            // An explicit tap target instead of a plain row: swapping is an
            // action, so it gets a real button rather than a switch.
            UIButton *swap = [self swapSegmentsButton];
            [cell.contentView addSubview:swap];
            swap.translatesAutoresizingMaskIntoConstraints = NO;
            UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
            [NSLayoutConstraint activateConstraints:@[
                [swap.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
                [swap.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
                [swap.topAnchor constraintEqualToAnchor:margins.topAnchor constant:2],
                [swap.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-2]
            ]];
        } else {
            cell.textLabel.text = MTCGL(@[@"BAR_SWAP", @"BAR_SINGLE", @"BAR_EQUAL", @"BAR_LABEL"][path.row]);
            UISwitch *toggle = [UISwitch new]; toggle.tag = path.row;
            toggle.on = path.row == 3 ? [self.preferences[kShortLabelEnabledKey] boolValue] : [self.layout[path.row == 1 ? @"single" : @"equal"] boolValue];
            [toggle addTarget:self action:@selector(toggleLayout:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        }
    } else if (path.section == 3) {
        cell.textLabel.text = MTCGL(MTCGTitles()[path.row]);
        cell.detailTextLabel.text = MTCGL(@[@"CONTEXT_SELECTION_HINT", @"CONTEXT_CLIPBOARD_HINT", @"CONTEXT_PASTE_HINT", @"CONTEXT_INPUT_HINT", @"CONTEXT_IDLE_HINT", @"CONTEXT_FLOATING_HINT", @"CONTEXT_MASTER_HINT"][path.row]);
        UISwitch *toggle = [UISwitch new]; toggle.tag = path.row;
        id value = self.preferences[MTCGKeys()[path.row]];
        toggle.on = [value isKindOfClass:NSNumber.class] ? [value boolValue] : (path.row < 4 || path.row == 6);
        [toggle addTarget:self action:@selector(toggleGroup:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    } else if (path.section == 4) {
        cell.textLabel.text = MTCGTitle(self.priority[path.row].integerValue); cell.showsReorderControl = YES;
    } else if (path.section == 5) {
        NSString *key = @[kContextDebounceKey, kContextClipboardFreshnessKey, kContextPasteFreshnessKey, kContextLockKey][path.row];
        NSArray *defaults = @[@200,@8,@3,@5], *low = @[@0,@2,@1,@0], *high = @[@1000,@60,@15,@15];
        double value = MTContextNumber(self.preferences, key, [defaults[path.row] doubleValue], [low[path.row] doubleValue], [high[path.row] doubleValue]);
        cell.textLabel.text = MTCGL(@[@"CONTEXT_DEBOUNCE", @"CONTEXT_CLIPBOARD_TTL", @"CONTEXT_PASTE_TTL", @"CONTEXT_LOCK"][path.row]);
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f %@", value, MTCGL(path.row ? @"CONTEXT_SECONDS" : @"CONTEXT_MS")];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
// A prominent capsule button so the swap action is unmistakable.
- (UIButton *)swapSegmentsButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration];
    configuration.title = MTCGL(@"BAR_SWAP");
    configuration.image = [UIImage systemImageNamed:@"arrow.left.arrow.right"];
    configuration.imagePlacement = NSDirectionalRectEdgeLeading;
    configuration.imagePadding = 6;
    configuration.baseForegroundColor = UIColor.systemBlueColor;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    button.configuration = configuration;
    [button addTarget:self action:@selector(swapSegments) forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)swapSegments {
    id left = self.layout[@"left"]; self.layout[@"left"] = self.layout[@"right"]; self.layout[@"right"] = left; [self saveLayout];
}
- (void)toggleLayout:(UISwitch *)sender {
    if (sender.tag == 3) { [MTPrefsManager.sharedInstance setValue:@(sender.on) forKey:kShortLabelEnabledKey]; [self refresh]; return; }
    self.layout[sender.tag == 1 ? @"single" : @"equal"] = @(sender.on); [self saveLayout];
}
- (void)toggleGroup:(UISwitch *)sender { [MTPrefsManager.sharedInstance setValue:@(sender.on) forKey:MTCGKeys()[sender.tag]]; [self refresh]; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 4 || (path.section < 2 && path.row < [self.layout[path.section ? @"right" : @"left"] count]);
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path { return [self tableView:tableView canMoveRowAtIndexPath:path]; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path { return path.section < 2 && [self tableView:tableView canEditRowAtIndexPath:path] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path { return path.section < 2; }
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)destination {
    if (source.section == 4) return destination.section == 4 ? destination : source;
    if (destination.section >= 2 || (destination.section != source.section && [self.layout[destination.section ? @"right" : @"left"] count] >= 8)) return source;
    NSUInteger count = [self.layout[destination.section ? @"right" : @"left"] count];
    return [NSIndexPath indexPathForRow:MIN(destination.row, count - (source.section == destination.section ? 1 : 0)) inSection:destination.section];
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    if (source.section == 4) {
        NSNumber *item = self.priority[source.row]; [self.priority removeObjectAtIndex:source.row]; [self.priority insertObject:item atIndex:destination.row];
        [MTPrefsManager.sharedInstance setValue:self.priority forKey:kContextPriorityKey]; [self refresh]; return;
    }
    NSMutableArray *from = [self.layout[source.section ? @"right" : @"left"] mutableCopy]; NSDictionary *entry = from[source.row]; [from removeObjectAtIndex:source.row];
    NSMutableArray *to = source.section == destination.section ? from : [self.layout[destination.section ? @"right" : @"left"] mutableCopy];
    if (to.count >= 8) { [self refresh]; return; }
    [to insertObject:entry atIndex:MIN((NSUInteger)destination.row, to.count)];
    self.layout[source.section ? @"right" : @"left"] = from; self.layout[destination.section ? @"right" : @"left"] = to; [self saveLayout];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete || path.section >= 2) return;
    NSMutableArray *entries = [self.layout[path.section ? @"right" : @"left"] mutableCopy]; [entries removeObjectAtIndex:path.row]; self.layout[path.section ? @"right" : @"left"] = entries; [self saveLayout];
}
- (void)presentMenu:(UIAlertController *)menu atPath:(NSIndexPath *)path {
    [menu addAction:[UIAlertAction actionWithTitle:MTCGL(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.tableView;
    menu.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:path];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section < 2) {
        NSArray *entries = self.layout[path.section ? @"right" : @"left"];
        if (path.row == entries.count) { if (entries.count < 8) [self addEntryAtPath:path]; return; }
        [self editEntryAtPath:path];
    } else if (path.section == 2 && path.row == 0) {
        [self swapSegments];
    } else if (path.section == 3) {
        if (path.row == 5) { [self openFloatingApps]; return; }
        if (path.row < 5) [self openContextGroup:@[@"selection",@"clipboard",@"paste",@"input",@"idle"][path.row]];
    } else if (path.section == 5) [self chooseBehavior:path.row];
}
- (void)openContextGroup:(NSString *)key {
    if ([key isEqual:@"auto"]) return;
    MTPContextActionsController *editor = [MTPContextActionsController new]; editor.groupKey = key;
    editor.title = MTCGL([@"BAR_CONTEXT_" stringByAppendingString:key.uppercaseString]); [self pushPage:editor];
}
- (void)appendEntry:(NSDictionary *)entry segment:(NSInteger)segment {
    NSMutableArray *entries = [self.layout[segment ? @"right" : @"left"] mutableCopy];
    if (entries.count >= 8) return; [entries addObject:entry]; self.layout[segment ? @"right" : @"left"] = entries; [self saveLayout];
}
- (void)addEntryAtPath:(NSIndexPath *)path {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:MTCGL(@"BAR_ADD") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [menu addAction:[UIAlertAction actionWithTitle:MTCGL(@"BAR_KIND_ACTION") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        MTPSubActionPickerController *picker = [MTPSubActionPickerController new]; picker.actionContextKind = MTPanelKeyboardKind; picker.fullOrder = MTPPanelBuiltInActions();
        picker.title = MTCGL(@"CHOOSE_ACTION");
        picker.completion = ^(NSString *selector) { [weakSelf ensureShortcutDefinition:selector]; [weakSelf appendEntry:@{@"kind":@"action",@"value":selector} segment:path.section]; };
        [weakSelf pushPage:picker];
    }]];
    id oldOrder = self.preferences[kShortcutskey];
    NSArray *savedButtons = [oldOrder isKindOfClass:NSArray.class] && [oldOrder count] && [oldOrder[0] isKindOfClass:NSArray.class] ? oldOrder[0] : @[];
    if (savedButtons.count) [menu addAction:[UIAlertAction actionWithTitle:MTCGL(@"BAR_SAVED_ACTIONS") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIAlertController *saved = [UIAlertController alertControllerWithTitle:MTCGL(@"BAR_SAVED_ACTIONS") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        for (id definition in savedButtons) {
            if (![definition isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *entry = MTBottomBarEntry(@{@"kind":@"action", @"value":definition[@"selector"] ?: @""});
            if (!entry) continue;
            [saved addAction:[UIAlertAction actionWithTitle:[weakSelf entryTitle:entry] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *selected) { [weakSelf appendEntry:entry segment:path.section]; }]];
        }
        [weakSelf presentMenu:saved atPath:path];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:MTCGL(@"BAR_KIND_CONTEXT") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf chooseContextAtPath:path]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:MTCGL(@"BAR_KIND_APP") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        MTPOpenAppPickerController *picker = [MTPOpenAppPickerController new];
        picker.completion = ^(MTPAppInfo *app) { if (app.bundleID.length) [weakSelf appendEntry:@{@"kind":@"app",@"value":app.bundleID,@"title":app.name ?: app.bundleID} segment:path.section]; };
        [weakSelf pushPage:picker];
    }]];
    [self presentMenu:menu atPath:path];
}
- (void)chooseContextAtPath:(NSIndexPath *)path {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:MTCGL(@"BAR_KIND_CONTEXT") message:MTCGL(@"BAR_CONTEXT_HINT") preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSString *group in @[@"auto",@"selection",@"clipboard",@"paste",@"input",@"idle"]) {
        [menu addAction:[UIAlertAction actionWithTitle:MTCGL([@"BAR_CONTEXT_" stringByAppendingString:group.uppercaseString]) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            UIAlertController *slots = [UIAlertController alertControllerWithTitle:MTCGL(@"BAR_CONTEXT_INDEX") message:nil preferredStyle:UIAlertControllerStyleAlert];
            for (NSInteger index = 0; index < 3; index++) [slots addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%ld", (long)index + 1] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *selected) {
                [weakSelf appendEntry:@{@"kind":@"context",@"value":group,@"index":@(index),@"fallback":@YES} segment:path.section];
            }]];
            [slots addAction:[UIAlertAction actionWithTitle:MTCGL(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
            [weakSelf presentViewController:slots animated:YES completion:nil];
        }]];
    }
    [self presentMenu:menu atPath:path];
}
- (void)ensureShortcutDefinition:(NSString *)selector {
    NSDictionary *prefs = [MTPrefsManager.sharedInstance readPrefs]; id raw = prefs[kShortcutskey];
    NSMutableArray *enabled = [NSMutableArray array], *disabled = [NSMutableArray array];
    if ([raw isKindOfClass:NSArray.class] && [raw count] >= 2) {
        if ([raw[0] isKindOfClass:NSArray.class]) [enabled addObjectsFromArray:raw[0]];
        if ([raw[1] isKindOfClass:NSArray.class]) [disabled addObjectsFromArray:raw[1]];
    }
    for (id section in @[enabled,disabled]) for (id item in section)
        if ([item isKindOfClass:NSDictionary.class] && [item[@"selector"] isEqual:selector]) return;
    NSDictionary *definition = MTPPanelDisplayDefinition(prefs, selector);
    NSString *icon = definition[@"images13"] ?: definition[@"icon"] ?: @"bolt";
    [enabled addObject:@{@"selector":selector,@"label":definition[@"name"] ?: selector,@"images12":icon,@"images13":icon}];
    [MTPrefsManager.sharedInstance setValue:@[enabled,disabled] forKey:kShortcutskey];
}
- (void)editEntryAtPath:(NSIndexPath *)path {
    NSString *segment = path.section ? @"right" : @"left";
    NSDictionary *entry = self.layout[segment][path.row];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:[self entryTitle:entry] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    if ([entry[@"kind"] isEqual:@"action"]) [menu addAction:[UIAlertAction actionWithTitle:MTCGL(@"BAR_EDIT_ACTION") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf ensureShortcutDefinition:entry[@"value"]];
        MTPGesturePickerController *editor = [MTPGesturePickerController new]; editor.identifier = entry[@"value"]; editor.configuration = @"bottom"; editor.fullOrder = weakSelf.fullOrder; editor.title = [weakSelf entryTitle:entry]; [weakSelf pushPage:editor];
    }]];
    if ([entry[@"kind"] isEqual:@"context"] && ![entry[@"value"] isEqual:@"auto"]) [menu addAction:[UIAlertAction actionWithTitle:MTCGL(@"BAR_EDIT_GROUP") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf openContextGroup:entry[@"value"]]; }]];
    NSArray *entries = self.layout[segment];
    for (NSInteger delta = -1; delta <= 1; delta += 2) {
        NSInteger target = path.row + delta; if (target < 0 || target >= entries.count) continue;
        [menu addAction:[UIAlertAction actionWithTitle:MTCGL(delta < 0 ? @"BAR_UP" : @"BAR_DOWN") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [weakSelf tableView:weakSelf.tableView moveRowAtIndexPath:path toIndexPath:[NSIndexPath indexPathForRow:target inSection:path.section]];
        }]];
    }
    if ([self.layout[path.section ? @"left" : @"right"] count] < 8) [menu addAction:[UIAlertAction actionWithTitle:MTCGL(@"BAR_MOVE") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf tableView:weakSelf.tableView moveRowAtIndexPath:path toIndexPath:[NSIndexPath indexPathForRow:[weakSelf.layout[path.section ? @"left" : @"right"] count] inSection:1 - path.section]];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:MTCGL(@"BAR_REMOVE") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [weakSelf tableView:weakSelf.tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:path];
    }]];
    [self presentMenu:menu atPath:path];
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
    if (![controller isKindOfClass:PSViewController.class]) return;
    [controller setSpecifier:item]; [controller setRootController:self.rootController]; [controller setParentController:self]; [self pushController:controller];
}
- (id)floatingApps:(PSSpecifier *)specifier { return MTKbdHandleAppsFromPreferences([MTPrefsManager.sharedInstance readPrefs]); }
- (void)setFloatingApps:(id)value specifier:(PSSpecifier *)specifier {
    if ([value isKindOfClass:NSArray.class]) [MTPrefsManager.sharedInstance setValue:value forKey:kKbdHandleAppsKey];
}
- (void)chooseBehavior:(NSInteger)row {
    NSArray *choices = @[@[@0, @100, @200, @300, @500, @1000], @[@2, @5, @8, @15, @30, @60], @[@1, @2, @3, @5, @10, @15], @[@0, @1, @3, @5, @10, @15]][row];
    NSString *key = @[kContextDebounceKey, kContextClipboardFreshnessKey, kContextPasteFreshnessKey, kContextLockKey][row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTCGL(@[@"CONTEXT_DEBOUNCE", @"CONTEXT_CLIPBOARD_TTL", @"CONTEXT_PASTE_TTL", @"CONTEXT_LOCK"][row]) message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *value in choices) [alert addAction:[UIAlertAction actionWithTitle:value.stringValue style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [MTPrefsManager.sharedInstance setValue:value forKey:key]; [weakSelf refresh];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:MTCGL(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
