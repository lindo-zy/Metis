//
//  KayokoCustomJumpManagementViewController.m
//  Kayoko
//

#import "KayokoCustomJumpManagementViewController.h"
#import "KayokoCustomJump.h"
#import "KayokoCustomJumpStore.h"
#import "KayokoCustomJumpTableViewCell.h"
#import "KayokoCustomJumpEditorViewController.h"
#import "KayokoTagPlaceholderView.h"

static NSString *const kKayokoCustomJumpCellReuseIdentifier = @"KayokoCustomJumpCell";
static NSString *const kKayokoActionTypeCellReuseIdentifier = @"KayokoActionTypeCell";
static CGFloat const kKayokoCustomJumpPlaceholderMinimumHeight = 96.0;
static NSInteger const kKayokoSectionSelectedActions = 0;
static NSInteger const kKayokoSectionChooseAction = 1;

// The list page mirrors the reference layout: configured actions on top, the
// fixed add-action entries below, and a single Edit toggle driving both batch
// deletion and drag reordering.
@interface KayokoCustomJumpManagementViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) KayokoTagPlaceholderView *placeholderView;
@property(nonatomic, strong) NSMutableArray<KayokoCustomJump *> *jumps;
@property(nonatomic, strong) NSMutableSet<NSString *> *selectedJumpUUIDs;
@property(nonatomic, strong) KayokoCustomJumpStore *jumpStore;
@property(nonatomic, strong) NSBundle *localizationBundle;
@property(nonatomic, strong) UIBarButtonItem *toolbarFlexibleSpaceItem;
@property(nonatomic, strong) UIBarButtonItem *selectToolbarItem;
@property(nonatomic, strong) UIBarButtonItem *deleteToolbarItem;
@property(nonatomic, assign, getter=isUpdatingPlaceholderLayout) BOOL updatingPlaceholderLayout;
- (UIBarButtonItem *)editDoneButton;
- (void)updateToolbarItems;
- (void)toggleSelectAll;
- (void)deleteSelectedJumps;
- (BOOL)allJumpsSelected;
- (NSArray<NSString *> *)availableActionTypes;
- (void)addJumpWithType:(NSString *)type;
- (void)updatePlaceholderVisibility;
@end

@implementation KayokoCustomJumpManagementViewController

+ (BOOL)isImageActionManagement {
    return NO;
}

- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [view setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
    [self setView:view];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _localizationBundle = [NSBundle bundleForClass:[self class]];
    _jumps = [[NSMutableArray alloc] init];
    _selectedJumpUUIDs = [[NSMutableSet alloc] init];
    NSString *jumpsPath = [[self class] isImageActionManagement] ? [KayokoCustomJumpStore defaultImageActionsPath]
                                                                  : [KayokoCustomJumpStore defaultJumpsPath];
    _jumpStore = [[KayokoCustomJumpStore alloc] initWithJumpsPath:jumpsPath];

    [self setTitle:[self localizedStringForKey:[[self class] isImageActionManagement] ? @"Image Actions" : @"Custom Jumps"]];
    [self loadJumps];
    [self configureNavigationItem];
    [self configureTableView];
    [self configurePlaceholderView];
    [self configureToolbarItems];
    [self updateToolbarItems];
    [self updatePlaceholderVisibility];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updatePlaceholderLayout];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[self navigationController] setToolbarHidden:YES animated:animated];
}

- (void)loadJumps {
    NSError *error = nil;
    NSMutableArray<KayokoCustomJump *> *loadedJumps = [[self jumpStore] loadJumpsWithError:&error];
    if (!loadedJumps) {
        [self presentError:error];
        return;
    }
    [[self jumps] addObjectsFromArray:loadedJumps];
}

- (void)configureTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setAllowsMultipleSelectionDuringEditing:YES];
    [_tableView setRowHeight:64.0];
    [_tableView registerClass:[KayokoCustomJumpTableViewCell class]
       forCellReuseIdentifier:kKayokoCustomJumpCellReuseIdentifier];
    [_tableView registerClass:[UITableViewCell class]
       forCellReuseIdentifier:kKayokoActionTypeCellReuseIdentifier];
    [[self view] addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [[_tableView topAnchor] constraintEqualToAnchor:[[self view] topAnchor]],
        [[_tableView leadingAnchor] constraintEqualToAnchor:[[self view] leadingAnchor]],
        [[_tableView trailingAnchor] constraintEqualToAnchor:[[self view] trailingAnchor]],
        [[_tableView bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]]
    ]];
}

- (void)configurePlaceholderView {
    NSString *emptyKey = [[self class] isImageActionManagement] ? @"No Image Actions" : @"No Custom Jumps";
    _placeholderView = [[KayokoTagPlaceholderView alloc] initWithMessage:[self localizedStringForKey:emptyKey]];
}

- (void)configureToolbarItems {
    _toolbarFlexibleSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                target:nil
                                                                                action:nil];
    _selectToolbarItem = [[UIBarButtonItem alloc] initWithTitle:[self localizedStringForKey:@"Select All"]
                                                          style:UIBarButtonItemStylePlain
                                                         target:self
                                                         action:@selector(toggleSelectAll)];
    _deleteToolbarItem = [[UIBarButtonItem alloc] initWithTitle:[self localizedStringForKey:@"Delete"]
                                                          style:UIBarButtonItemStylePlain
                                                         target:self
                                                         action:@selector(deleteSelectedJumps)];
    [_deleteToolbarItem setTintColor:[UIColor systemRedColor]];
}

- (void)configureNavigationItem {
    [[self navigationItem] setLargeTitleDisplayMode:UINavigationItemLargeTitleDisplayModeNever];
    [[self navigationItem] setRightBarButtonItem:[self editDoneButton]];
}

- (UIBarButtonItem *)editDoneButton {
    NSString *key = [self isEditing] ? @"Done" : @"Edit";
    UIBarButtonItemStyle style = [self isEditing] ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain;
    return [[UIBarButtonItem alloc] initWithTitle:[self localizedStringForKey:key]
                                             style:style
                                            target:self
                                            action:@selector(toggleEditing)];
}

- (void)toggleEditing {
    [self setEditing:![self isEditing] animated:YES];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    BOOL wasEditing = [self isEditing];
    if (editing && !wasEditing) {
        [[self tableView] setEditing:NO animated:NO];
    }

    [super setEditing:editing animated:animated];
    [[self tableView] setEditing:editing animated:animated];
    [[self navigationItem] setRightBarButtonItem:[self editDoneButton] animated:animated];
    if (!editing) {
        [[self selectedJumpUUIDs] removeAllObjects];
    }
    [[self navigationController] setToolbarHidden:!editing animated:animated];
    [self updateToolbarItems];
}

- (void)updateToolbarItems {
    NSArray<UIBarButtonItem *> *toolbarItems = nil;
    if ([self isEditing]) {
        NSString *title = [self allJumpsSelected] ? [self localizedStringForKey:@"Deselect All"]
                                                  : [self localizedStringForKey:@"Select All"];
        [[self selectToolbarItem] setTitle:title];
        [[self selectToolbarItem] setEnabled:[[self jumps] count] > 0];
        [[self deleteToolbarItem] setEnabled:[[self selectedJumpUUIDs] count] > 0];
        toolbarItems = @[ [self selectToolbarItem], [self toolbarFlexibleSpaceItem], [self deleteToolbarItem] ];
    } else {
        toolbarItems = @[];
    }

    if (![[self toolbarItems] isEqualToArray:toolbarItems]) {
        [self setToolbarItems:toolbarItems animated:YES];
    }
}

#pragma mark - Adding

- (NSArray<NSString *> *)availableActionTypes {
    return @[ kKayokoCustomJumpTypeURLScheme, kKayokoCustomJumpTypeOpenApp, kKayokoCustomJumpTypeShortcut ];
}

- (NSString *)displayNameForActionType:(NSString *)type {
    if ([type isEqualToString:kKayokoCustomJumpTypeOpenApp]) {
        return [self localizedStringForKey:@"Open App"];
    }
    if ([type isEqualToString:kKayokoCustomJumpTypeShortcut]) {
        return [self localizedStringForKey:@"Shortcut"];
    }
    return [self localizedStringForKey:@"URL Scheme"];
}

- (UIImage *)iconForActionType:(NSString *)type {
    NSString *symbolName = [type isEqualToString:kKayokoCustomJumpTypeOpenApp]      ? @"apps.iphone"
        : [type isEqualToString:kKayokoCustomJumpTypeShortcut]                      ? @"square.grid.2x2"
                                                                                    : kKayokoCustomJumpDefaultIconName;
    return [UIImage systemImageNamed:symbolName];
}

- (void)addJumpWithType:(NSString *)type {
    // Adding happens straight from the fixed option rows; nothing touches the
    // store here — the action joins the list only when the editor's 完成
    // reports the finished entry, so backing out of the editor never leaves a
    // half-configured row behind.
    // New entries start with the generic 动作 title so a bare add+完成 round
    // trip still produces a readable row; the user can rename or let the
    // pickers fill in the app/shortcut identity.
    KayokoCustomJump *jump = [[KayokoCustomJump alloc] initWithUUID:[[NSUUID UUID] UUIDString]
                                                              title:[self localizedStringForKey:@"Action"]
                                                               link:@""
                                                               icon:nil
                                                               type:type
                                                       shortcutType:nil];
    KayokoCustomJumpEditorViewController *editor =
        [[KayokoCustomJumpEditorViewController alloc] initWithJump:jump
                                                 localizationBundle:[self localizationBundle]
                                                     isImageAction:[[self class] isImageActionManagement]];
    __weak typeof(self) weakSelf = self;
    [editor setCompletionHandler:^(KayokoCustomJump *updatedJump) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      NSMutableArray<KayokoCustomJump *> *updatedJumps = [[strongSelf jumps] mutableCopy];
      [updatedJumps addObject:updatedJump];
      if (![strongSelf saveJumps:updatedJumps]) {
          return;
      }
      [[strongSelf jumps] addObject:updatedJump];
      [strongSelf updatePlaceholderVisibility];
      NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)([[strongSelf jumps] count] - 1)
                                                  inSection:kKayokoSectionSelectedActions];
      [[strongSelf tableView] insertRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
      [[strongSelf tableView] scrollToRowAtIndexPath:indexPath
                                    atScrollPosition:UITableViewScrollPositionMiddle
                                           animated:YES];
    }];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:editor];
    [navigationController setModalPresentationStyle:UIModalPresentationPageSheet];
    [self presentViewController:navigationController animated:YES completion:nil];
}

#pragma mark - Editing

- (BOOL)deleteJumpAtIndexPath:(NSIndexPath *)indexPath {
    if ([indexPath section] != kKayokoSectionSelectedActions || (NSUInteger)[indexPath row] >= [[self jumps] count]) {
        return NO;
    }

    NSUInteger index = (NSUInteger)[indexPath row];
    KayokoCustomJump *deletedJump = [self jumps][index];
    NSMutableArray<KayokoCustomJump *> *updatedJumps = [[self jumps] mutableCopy];
    [updatedJumps removeObjectAtIndex:index];
    if (![self saveJumps:updatedJumps]) {
        return NO;
    }

    [[self jumps] removeObjectAtIndex:index];
    [[self selectedJumpUUIDs] removeObject:[deletedJump uuid]];
    [self updatePlaceholderVisibility];
    [[self tableView] deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self updateToolbarItems];
    return YES;
}

- (void)toggleSelectAll {
    if ([[self jumps] count] == 0) {
        return;
    }

    BOOL shouldDeselect = [self allJumpsSelected];
    for (NSUInteger index = 0; index < [[self jumps] count]; index++) {
        KayokoCustomJump *jump = [self jumps][index];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)index inSection:kKayokoSectionSelectedActions];
        if (shouldDeselect) {
            [[self selectedJumpUUIDs] removeObject:[jump uuid]];
            [[self tableView] deselectRowAtIndexPath:indexPath animated:YES];
        } else {
            [[self selectedJumpUUIDs] addObject:[jump uuid]];
            [[self tableView] selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
        }
    }
    [self updateToolbarItems];
}

- (void)deleteSelectedJumps {
    if ([[self selectedJumpUUIDs] count] == 0) {
        return;
    }

    NSMutableArray<NSIndexPath *> *deletedIndexPaths = [[NSMutableArray alloc] init];
    for (NSUInteger index = 0; index < [[self jumps] count]; index++) {
        if ([[self selectedJumpUUIDs] containsObject:[[self jumps][index] uuid]]) {
            [deletedIndexPaths addObject:[NSIndexPath indexPathForRow:(NSInteger)index
                                                            inSection:kKayokoSectionSelectedActions]];
        }
    }

    NSMutableArray<KayokoCustomJump *> *updatedJumps = [[NSMutableArray alloc] init];
    for (KayokoCustomJump *jump in [self jumps]) {
        if (![[self selectedJumpUUIDs] containsObject:[jump uuid]]) {
            [updatedJumps addObject:jump];
        }
    }
    if (![self saveJumps:updatedJumps]) {
        return;
    }

    NSSet<NSString *> *deletedUUIDs = [[self selectedJumpUUIDs] copy];
    [self setJumps:updatedJumps];
    [[self selectedJumpUUIDs] minusSet:deletedUUIDs];
    [self updatePlaceholderVisibility];
    if ([deletedIndexPaths count] > 0) {
        [[self tableView] deleteRowsAtIndexPaths:deletedIndexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    [self updateToolbarItems];
}

- (void)presentEditorForJump:(KayokoCustomJump *)jump {
    KayokoCustomJumpEditorViewController *editor =
        [[KayokoCustomJumpEditorViewController alloc] initWithJump:jump
                                                   localizationBundle:[self localizationBundle]
                                                       isImageAction:[[self class] isImageActionManagement]];
    __weak typeof(self) weakSelf = self;
    [editor setCompletionHandler:^(KayokoCustomJump *updatedJump) {
      [weakSelf updateJump:updatedJump];
    }];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:editor];
    [navigationController setModalPresentationStyle:UIModalPresentationPageSheet];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)updateJump:(KayokoCustomJump *)updatedJump {
    NSUInteger index = [self indexOfJumpWithUUID:[updatedJump uuid]];
    if (index == NSNotFound) {
        return;
    }

    NSMutableArray<KayokoCustomJump *> *updatedJumps = [[self jumps] mutableCopy];
    updatedJumps[index] = updatedJump;
    if (![self saveJumps:updatedJumps]) {
        return;
    }

    [self setJumps:updatedJumps];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)index inSection:kKayokoSectionSelectedActions];
    KayokoCustomJumpTableViewCell *cell =
        (KayokoCustomJumpTableViewCell *)[[self tableView] cellForRowAtIndexPath:indexPath];
    if ([cell isKindOfClass:[KayokoCustomJumpTableViewCell class]]) {
        [cell configureWithJump:updatedJump editing:[self isEditing]];
    }
}

- (BOOL)allJumpsSelected {
    if ([[self jumps] count] == 0) {
        return NO;
    }
    for (KayokoCustomJump *jump in [self jumps]) {
        if (![[self selectedJumpUUIDs] containsObject:[jump uuid]]) {
            return NO;
        }
    }
    return YES;
}

- (NSUInteger)indexOfJumpWithUUID:(NSString *)uuid {
    for (NSUInteger index = 0; index < [[self jumps] count]; index++) {
        if ([[[self jumps][index] uuid] isEqualToString:uuid]) {
            return index;
        }
    }
    return NSNotFound;
}

- (BOOL)saveJumps:(NSArray<KayokoCustomJump *> *)jumps {
    NSError *error = nil;
    if ([[self jumpStore] saveJumps:jumps error:&error]) {
        return YES;
    }
    [self presentError:error];
    return NO;
}

- (void)updatePlaceholderVisibility {
    UIView *footerView = [[self tableView] tableFooterView];
    if ([[self jumps] count] > 0) {
        if (footerView == [self placeholderView]) {
            [[self tableView] setTableFooterView:nil];
        }
        return;
    }

    if (footerView != [self placeholderView]) {
        [[self tableView] setTableFooterView:[self placeholderView]];
    }
    [[self placeholderView] setMessage:[self localizedStringForKey:[[self class] isImageActionManagement]
                                                                        ? @"No Image Actions"
                                                                        : @"No Custom Jumps"]];
    [self updatePlaceholderLayout];
}

- (void)updatePlaceholderLayout {
    if ([self isUpdatingPlaceholderLayout] || [[self tableView] tableFooterView] != [self placeholderView]) {
        return;
    }

    CGFloat availableHeight = CGRectGetHeight([[self tableView] bounds]) -
                              MAX([[self tableView] adjustedContentInset].top - [[self tableView] contentInset].top, 0.0) -
                              MAX([[self tableView] adjustedContentInset].bottom - [[self tableView] contentInset].bottom, 0.0);
    CGRect targetFrame = CGRectMake(0.0, 0.0, CGRectGetWidth([[self tableView] bounds]),
                                    floor(MAX(availableHeight, kKayokoCustomJumpPlaceholderMinimumHeight)));
    if (CGRectEqualToRect([[self placeholderView] frame], targetFrame)) {
        return;
    }

    [self setUpdatingPlaceholderLayout:YES];
    [[self placeholderView] setFrame:targetFrame];
    [[self tableView] setTableFooterView:[self placeholderView]];
    [self setUpdatingPlaceholderLayout:NO];
}

- (NSString *)localizedStringForKey:(NSString *)key {
    return [[self localizationBundle] localizedStringForKey:key value:key table:@"CustomJumps"] ?: key;
}

- (void)presentError:(NSError *)error {
    NSString *titleKey = [[self class] isImageActionManagement] ? @"Image Actions" : @"Custom Jumps";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[self localizedStringForKey:titleKey]
                                                                    message:[error localizedDescription]
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[self localizedStringForKey:@"OK"]
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == kKayokoSectionChooseAction ? (NSInteger)[[self availableActionTypes] count]
                                                 : (NSInteger)[[self jumps] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([indexPath section] == kKayokoSectionChooseAction) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kKayokoActionTypeCellReuseIdentifier
                                                                forIndexPath:indexPath];
        NSString *type = [self availableActionTypes][(NSUInteger)[indexPath row]];
        [[cell imageView] setImage:[self iconForActionType:type]];
        [[cell textLabel] setText:[self displayNameForActionType:type]];
        [[cell textLabel] setFont:[UIFont systemFontOfSize:17.0]];
        [[cell textLabel] setTextColor:[UIColor labelColor]];
        [cell setAccessoryType:UITableViewCellAccessoryNone];
        return cell;
    }

    KayokoCustomJumpTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kKayokoCustomJumpCellReuseIdentifier
                                                                            forIndexPath:indexPath];
    [cell configureWithJump:[self jumps][(NSUInteger)[indexPath row]] editing:[self isEditing]];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [self localizedStringForKey:section == kKayokoSectionChooseAction ? @"Choose Action" : @"Selected"];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section != kKayokoSectionSelectedActions) {
        return nil;
    }

    UILabel *footerLabel = [[UILabel alloc] init];
    [footerLabel setNumberOfLines:0];
    [footerLabel setFont:[UIFont systemFontOfSize:13.0]];
    [footerLabel setTextColor:[UIColor secondaryLabelColor]];
    [footerLabel setText:[self localizedStringForKey:@"Selected Actions Footer"]];
    return footerLabel;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    // The fixed add-action rows never participate in editing; only configured
    // actions can be deleted or reordered.
    return [indexPath section] == kKayokoSectionSelectedActions;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    BOOL configuredAction = [indexPath section] == kKayokoSectionSelectedActions;
    return (![self isEditing] && configuredAction) ? UITableViewCellEditingStyleDelete
                                                   : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (editingStyle == UITableViewCellEditingStyleDelete && ![self isEditing]) {
        [self deleteJumpAtIndexPath:indexPath];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return [self isEditing] && [indexPath section] == kKayokoSectionSelectedActions;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
    targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
                           toProposedIndexPath:(NSIndexPath *)proposedIndexPath {
    (void)tableView;
    if ([proposedIndexPath section] == kKayokoSectionSelectedActions) {
        return proposedIndexPath;
    }
    return [NSIndexPath indexPathForRow:(NSInteger)([[self jumps] count] - 1)
                              inSection:kKayokoSectionSelectedActions];
}

- (void)tableView:(UITableView *)tableView
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
    if ([sourceIndexPath row] == [destinationIndexPath row]) {
        return;
    }

    NSUInteger sourceIndex = (NSUInteger)[sourceIndexPath row];
    NSUInteger destinationIndex = (NSUInteger)[destinationIndexPath row];
    if (sourceIndex >= [[self jumps] count] || destinationIndex >= [[self jumps] count]) {
        return;
    }

    NSMutableArray<KayokoCustomJump *> *updatedJumps = [[self jumps] mutableCopy];
    KayokoCustomJump *jump = updatedJumps[sourceIndex];
    [updatedJumps removeObjectAtIndex:sourceIndex];
    [updatedJumps insertObject:jump atIndex:destinationIndex];
    if (![self saveJumps:updatedJumps]) {
        [tableView moveRowAtIndexPath:destinationIndexPath toIndexPath:sourceIndexPath];
        return;
    }
    [self setJumps:updatedJumps];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([indexPath section] == kKayokoSectionChooseAction) {
        if (![self isEditing]) {
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            [self addJumpWithType:[self availableActionTypes][(NSUInteger)[indexPath row]]];
        }
        return;
    }

    if ([self isEditing]) {
        [[self selectedJumpUUIDs] addObject:[[self jumps][(NSUInteger)[indexPath row]] uuid]];
        [self updateToolbarItems];
        return;
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self presentEditorForJump:[self jumps][(NSUInteger)[indexPath row]]];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self isEditing] || [indexPath section] != kKayokoSectionSelectedActions ||
        (NSUInteger)[indexPath row] >= [[self jumps] count]) {
        return;
    }
    [[self selectedJumpUUIDs] removeObject:[[self jumps][(NSUInteger)[indexPath row]] uuid]];
    [self updateToolbarItems];
}

- (BOOL)tableView:(UITableView *)tableView shouldBeginMultipleSelectionInteractionAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return [indexPath section] == kKayokoSectionSelectedActions;
}

- (void)tableView:(UITableView *)tableView didBeginMultipleSelectionInteractionAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (![self isEditing]) {
        [self setEditing:YES animated:YES];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if ([self isEditing] || [indexPath section] != kKayokoSectionSelectedActions) {
        return nil;
    }
    UIContextualAction *deleteAction =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                title:[self localizedStringForKey:@"Delete"]
                                              handler:^(__kindof UIContextualAction *action,
                                                        __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
                                                (void)action;
                                                (void)sourceView;
                                                completionHandler([self deleteJumpAtIndexPath:indexPath]);
                                              }];
    [deleteAction setImage:[UIImage systemImageNamed:@"trash.fill"]];
    return [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction ]];
}

@end
