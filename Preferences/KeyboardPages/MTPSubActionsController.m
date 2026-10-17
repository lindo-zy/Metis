#import "MTPanelRegistry.h"
#import "MTPSubActionsController.h"
#import "MTPSubActionPickerController.h"
#import "MTPLinkActionEditorController.h"
#import "MTHelper.h"
#import "common.h"

static NSBundle *mtpLocalBundle;

// Leading inset of every row's content: room for the editing minus control.
// Applied through layout margins (with the system editing indent disabled) so
// the "添加" row and the sub-action rows line up in edit mode.
static CGFloat const MTSubActionContentLeading = 40.0;

// Because the table registers cell classes, dequeue never returns nil; the
// fixed row content is therefore built in the cell subclasses instead of
// cellForRowAtIndexPath.

@interface MTPSubActionCell : UITableViewCell
@end

@implementation MTPSubActionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.contentView.layoutMargins = UIEdgeInsetsMake(0, MTSubActionContentLeading, 0, 0);
    }
    return self;
}

@end

@interface MTPSubActionAddCell : UITableViewCell
@end

@implementation MTPSubActionAddCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        UIImageView *plusView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"plus.circle.fill"]];
        plusView.tintColor = [UIColor systemGreenColor];
        plusView.contentMode = UIViewContentModeScaleAspectFit;
        plusView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:plusView];

        UILabel *addLabel = [[UILabel alloc] init];
        addLabel.text = LOCALIZED(@"ADD");
        addLabel.textColor = [UIColor systemBlueColor];
        addLabel.font = [UIFont systemFontOfSize:17];
        addLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:addLabel];

        [NSLayoutConstraint activateConstraints:@[
            [plusView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:MTSubActionContentLeading],
            [plusView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [plusView.widthAnchor constraintEqualToConstant:29],
            [plusView.heightAnchor constraintEqualToConstant:29],

            [addLabel.leadingAnchor constraintEqualToAnchor:plusView.trailingAnchor constant:10],
            [addLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [addLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [addLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];
    }
    return self;
}

@end

@interface MTPSubActionsController ()
// In-memory copy of this button's sub-action entries; persisted on every
// add/delete/move/selection.
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *entries;
@end

@implementation MTPSubActionsController

#pragma mark - Storage

// Each gesture has its own store. Persist one envelope even when the last
// action is deleted, so legacy/default actions do not reappear on reload.
- (NSString *)subActionsKey {
    return MTCustomActionsKeyForGesture((int)self.gestureType, self.configuration);
}

- (NSMutableArray<NSMutableDictionary *> *)entriesForIdentifier {
    NSMutableArray<NSMutableDictionary *> *entries = [NSMutableArray array];
    NSDictionary *prefs = [[MTPrefsManager sharedInstance] readPrefs];
    for (NSString *selector in MTGestureActionSelectors(prefs, self.identifier, (int)self.gestureType, self.configuration)) {
        [entries addObject:[@{@"identifier": self.identifier, @"selector": selector} mutableCopy]];
    }
    return entries;
}

- (void)writeEntries:(NSArray<NSDictionary *> *)entries {
    if (self.identifier.length == 0) return;
    NSMutableDictionary *prefs = [[[MTPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *key = self.subActionsKey;
    NSMutableArray *updated = [NSMutableArray array];
    id stored = prefs[key];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (id entry in stored) {
            if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"identifier"] isEqual:self.identifier]) {
                [updated addObject:entry];
            }
        }
    }
    NSMutableArray *selectors = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        NSString *selector = entry[@"selector"];
        if ([selector isKindOfClass:[NSString class]] && selector.length > 0) [selectors addObject:selector];
    }
    [updated addObject:@{@"identifier": self.identifier, @"selectors": selectors}];
    prefs[key] = updated;
    // writePrefs mirrors the shared snapshot and notifies open toolbar hosts.
    [[MTPrefsManager sharedInstance] writePrefs:prefs];
}

#pragma mark - Picker navigation

// The add row never stages an empty entry: actions are picked first in a
// multi-select pass, and only a non-empty pick appends entries in one batch.
- (void)pushMultiPickerForAdd {
    MTPSubActionPickerController *picker = [[MTPSubActionPickerController alloc] init];
    picker.fullOrder = self.fullOrder;
    picker.allowsMultipleSelection = YES;
    picker.title = LOCALIZED(@"CHOOSE_ACTION");

    __weak typeof(self) weakSelf = self;
    picker.multiSelectionCompletion = ^(NSArray<NSString *> *selectors) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || selectors.count == 0) return;
        for (NSString *selector in selectors) {
            [strongSelf.entries addObject:[@{
                @"identifier": strongSelf.identifier ?: @"",
                @"selector": selector ?: @"",
            } mutableCopy]];
        }
        [strongSelf.tableView reloadData];
        [strongSelf writeEntries:strongSelf.entries];
    };

    [picker setRootController:[self rootController]];
    [picker setParentController:[self parentController]];
    [self pushController:picker];
}

- (void)pushPickerForRow:(NSInteger)row {
    if (row >= (NSInteger)self.entries.count) return;

    MTPSubActionPickerController *picker = [[MTPSubActionPickerController alloc] init];
    picker.fullOrder = self.fullOrder;
    picker.selectedSelector = self.entries[row][@"selector"];
    picker.title = LOCALIZED(@"CHOOSE_ACTION");

    __weak typeof(self) weakSelf = self;
    [picker setCompletion:^(NSString *selector) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || row >= (NSInteger)strongSelf.entries.count) return;
        strongSelf.entries[row][@"selector"] = selector ?: @"";
        [strongSelf writeEntries:strongSelf.entries];
        [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
                                    withRowAnimation:UITableViewRowAnimationNone];
    }];

    [picker setRootController:[self rootController]];
    [picker setParentController:[self parentController]];
    [self pushController:picker];
}

// Tapping a row edits that sub-action: user-defined actions open their own
// configuration page — the same editor the custom-actions management page
// uses — while built-in actions have no configuration, so editing them means
// swapping which action the row holds.
- (void)pushEditorForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.entries.count) return;
    NSString *selector = self.entries[row][@"selector"];
    if (![selector isKindOfClass:[NSString class]] || !MTIsLinkActionSelector(selector)) return;
    NSDictionary *linkAction = [self linkActionForSelector:selector];
    if (!linkAction) return;

    MTPLinkActionEditorController *editor = [[MTPLinkActionEditorController alloc] init];
    editor.entry = [linkAction mutableCopy];

    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSDictionary *savedEntry) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![savedEntry isKindOfClass:[NSDictionary class]]) return;
        // The editor only reports the normalized entry; write it back into the
        // shared custom-action store matched by the immutable selector. The
        // full domain is rewritten so other keys survive the replace-style
        // writePrefs of this unsandboxed process.
        NSMutableDictionary *prefs = [[[MTPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSMutableArray *linkActions = [NSMutableArray array];
        for (NSDictionary *entry in prefs[kLinkActionskey]) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            if ([entry[@"selector"] isEqual:savedEntry[@"selector"]]) {
                [linkActions addObject:[savedEntry mutableCopy]];
            } else {
                [linkActions addObject:[entry mutableCopy]];
            }
        }
        prefs[kLinkActionskey] = linkActions;
        [[MTPrefsManager sharedInstance] writePrefs:prefs];
        // Name and icon may have changed; viewWillAppear also reloads, this
        // covers the already-visible table right away.
        [strongSelf.tableView reloadData];
    };

    [editor setRootController:[self rootController]];
    [editor setParentController:[self parentController]];
    [self pushController:editor];
}

- (NSDictionary *)linkActionForSelector:(NSString *)selector {
    if (!MTIsLinkActionSelector(selector) && !MTIsPanelSelector(selector)) return nil;
    NSDictionary *prefs = [[MTPrefsManager sharedInstance] readPrefs];
    NSDictionary *panel = MTPanelDefinition(prefs, selector);
    if ([panel[@"kind"] isEqual:MTPanelKeyboardKind]) return panel;
    for (NSDictionary *entry in prefs[kLinkActionskey]) {
        if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"selector"] isEqual:selector]) return entry;
    }
    return nil;
}

// Built-in actions use localized selector names; link actions use the name
// configured by the user. Never feed a private link-action selector through
// the localization helper, otherwise it renders as LONG___TYPEX_... .
- (NSString *)displayNameForSelector:(NSString *)selector {
    NSDictionary *linkAction = [self linkActionForSelector:selector];
    if (MTIsLinkActionSelector(selector) || MTIsPanelSelector(selector)) {
        NSString *name = [linkAction[@"name"] isKindOfClass:[NSString class]] ? linkAction[@"name"] : @"";
        return name.length ? name : LOCALIZED(@"DEFAULT_BUTTON_NAME");
    }
    return [MTHelper localizedStringForActionNamed:selector shortName:NO bundle:mtpLocalBundle];
}

- (UIImage *)displayImageForSelector:(NSString *)selector {
    NSDictionary *linkAction = [self linkActionForSelector:selector];
    if (MTIsLinkActionSelector(selector) || MTIsPanelSelector(selector)) {
        NSString *icon = [linkAction[@"icon"] isKindOfClass:[NSString class]] ? linkAction[@"icon"] : @"";
        return [MTHelper imageForIconConfig:icon defaultSymbolName:@"link"]
            ?: [UIImage systemImageNamed:@"link"];
    }

    for (NSUInteger index = 0; index < self.fullOrder.count; index++) {
        if ([[MTHelper actionNameFromArray:self.fullOrder atIndex:index] isEqualToString:selector]) {
            return [MTHelper imageFromArray:self.fullOrder atIndex:index withSystemColor:YES completion:nil];
        }
    }
    return nil;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return LOCALIZED(@"ADD_SUB_ACTION");
}

// Fixed standard row height: the add cell pins its label to the contentView's
// top and bottom, so self-sizing would otherwise squash the row down to the
// text height and clip the plus icon.
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44;
}

// The last row is the fixed "添加" row.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.entries.count) {
        return [tableView dequeueReusableCellWithIdentifier:@"MTPSubActionAddCell" forIndexPath:indexPath];
    }

    MTPSubActionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MTPSubActionCell" forIndexPath:indexPath];

    NSString *selector = self.entries[indexPath.row][@"selector"];
    cell.textLabel.text = [selector isKindOfClass:[NSString class]] && selector.length > 0
        ? [self displayNameForSelector:selector]
        : LOCALIZED(@"SUB_ACTION");
    cell.imageView.image = [selector isKindOfClass:[NSString class]] && selector.length > 0
        ? [self displayImageForSelector:selector]
        : nil;
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![cell isKindOfClass:[MTPSubActionCell class]]) return;
    // UIKit resets cell margins from the table defaults during layout, so the
    // fixed leading inset is re-applied here on every display pass.
    cell.preservesSuperviewLayoutMargins = NO;
    UIEdgeInsets insets = UIEdgeInsetsMake(0, MTSubActionContentLeading, 0, 0);
    cell.layoutMargins = insets;
    cell.contentView.layoutMargins = insets;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= (NSInteger)self.entries.count) {
        [self pushMultiPickerForAdd];
        return;
    }

    NSString *selector = self.entries[indexPath.row][@"selector"];
    if (MTIsLinkActionSelector(selector) && [self linkActionForSelector:selector]) {
        [self pushEditorForRow:indexPath.row];
    } else {
        [self pushPickerForRow:indexPath.row];
    }
}

#pragma mark - Editing (delete + reorder)

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row < (NSInteger)self.entries.count ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    // The system indent is replaced by the fixed layout margin above so the
    // add row and the sub-action rows align.
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row < (NSInteger)self.entries.count;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    // Never drop onto the trailing add row.
    if (proposedDestinationIndexPath.row >= (NSInteger)self.entries.count) {
        return [NSIndexPath indexPathForRow:self.entries.count - 1 inSection:0];
    }
    return proposedDestinationIndexPath;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.row >= (NSInteger)self.entries.count) return;

    [self.entries removeObjectAtIndex:indexPath.row];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self writeEntries:self.entries];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.row >= (NSInteger)self.entries.count || destinationIndexPath.row >= (NSInteger)self.entries.count) return;

    NSMutableDictionary *entry = self.entries[sourceIndexPath.row];
    [self.entries removeObjectAtIndex:sourceIndexPath.row];
    [self.entries insertObject:entry atIndex:destinationIndexPath.row];
    [self writeEntries:self.entries];
}

#pragma mark - View lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The unified action picker can delete a custom action globally. Reload so
    // a sub-action that referenced the deleted definition disappears at once.
    self.entries = [self entriesForIdentifier];
    [self.tableView reloadData];
}

- (void)viewDidLoad {
    mtpLocalBundle = [NSBundle bundleWithPath:bundlePath];
    [mtpLocalBundle load];
    [super viewDidLoad];

    self.entries = [self entriesForIdentifier];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.tableView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [self.tableView registerClass:[MTPSubActionCell class] forCellReuseIdentifier:@"MTPSubActionCell"];
    [self.tableView registerClass:[MTPSubActionAddCell class] forCellReuseIdentifier:@"MTPSubActionAddCell"];
    // Edit mode supplies the delete minus and the drag handle for every row.
    [self.tableView setEditing:YES];
    self.tableView.allowsSelectionDuringEditing = YES;

    self.view = self.tableView;
}

@end
