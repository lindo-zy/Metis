#import "MTCustomJumpManagementViewController.h"
#import "MTClipboardActionReferences.h"
#import "MTSharedResourceStore.h"
#import "MTPrefsManager.h"
#import "MTHelper.h"
#import "MTPreferenceKeys.h"
#import "MTPLinkActionEditorController.h"
#import "MTPActionGroups.h"
#import "common.h"
#import <roothide.h>
#import <UIKit/UIKit.h>

static NSString * const MTClipboardActionReuseIdentifier = @"MTClipboardActionPickerCell";
static NSString * const MTClipboardAuxiliaryReuseIdentifier = @"MTClipboardAuxiliaryCell";

// Clipboard-internal distinctness: every row kind the picker can render. Each
// row carries the action dictionary (@"action") so the cell builder never has
// to map an index path back through two different arrays.
typedef NS_ENUM(NSInteger, MTClipboardActionRowKind) {
    MTClipboardActionRowKindAction = 0,
    MTClipboardActionRowKindAdd = 1,
    MTClipboardActionRowKindEmpty = 2,
};

// 剪切板可执行类型：与 MTClipboardActionReferences.supportsEntry 一一对应。
// AI / 文本 / JavaScript 不在其中——它们依赖输入框或脚本通道，在此新建会产出
// 无法执行的动作，因此不出现在类型选择器里。
static NSArray<NSString *> *MTClipboardCreatableActionTypes(void) {
    static NSArray<NSString *> *types;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        types = @[kCustomActionTypeURLScheme, kCustomActionTypeOpenApp, kCustomActionTypeShortcut, kCustomActionTypeSystem];
    });
    return types;
}

static NSString *MTClipboardActionName(NSDictionary *entry) {
    NSString *name = entry[@"name"];
    return [name isKindOfClass:NSString.class] && name.length ? name : @"未命名动作";
}

static NSString *MTClipboardActionTypeLabel(NSDictionary *entry) {
    NSString *type = entry[kCustomActionTypeKey];
    NSString *label = [type isKindOfClass:NSString.class] ? [MTPLinkActionEditorController displayNameForType:type] : nil;
    return label.length ? label : @"URL Scheme";
}

// Subtitle cells are not reachable through -registerClass:[UITableViewCell class]
// (that always builds UITableViewCellStyleDefault), so the picker registers its
// own subclass — the same shape every other action picker renders.
@interface MTClipboardActionCell : UITableViewCell
@end
@implementation MTClipboardActionCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
}
@end

@interface MTCustomJumpManagementViewController () <UITableViewDataSource, UITableViewDelegate,
                                                     UISearchResultsUpdating,
                                                     UITableViewDragDelegate, UITableViewDropDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic, copy) NSArray<NSDictionary *> *availableActions;
@property(nonatomic, strong) NSMutableArray<NSString *> *selectedIDs;
// Rendered rows: referenced actions first (in reference order), the rest in
// library order, then the trailing 添加 row. Rebuilt by rebuildDisplayRows.
@property(nonatomic, copy) NSArray<NSDictionary *> *displayRows;
@property(nonatomic, copy) NSString *query;
@end

@implementation MTCustomJumpManagementViewController

+ (BOOL)isImageActionManagement { return NO; }
+ (NSString *)referenceSlot { return [self isImageActionManagement] ? @"image" : @"text"; }

// Single-select slots replace instead of append; every other slot keeps an
// ordered reference list.
+ (BOOL)usesSingleSelectionForSlot:(NSString *)slot { return [slot isEqual:@"image-double-tap"]; }
- (BOOL)usesSingleSelection { return [self.class usesSingleSelectionForSlot:[self.class referenceSlot]]; }

+ (BOOL)prepareSharedActionsWithError:(NSError **)error {
    // Settings owns migration and all writes; runtime only resolves published bindings.
    [MTPrefsManager.sharedInstance readPrefs];
    NSDictionary *snapshot = [MTSharedResourceStore readSnapshotError:error];
    if (!snapshot) return NO;
    if ([snapshot[@"migration"][@"clipboardActionReferencesV1"] boolValue]) return YES;
    NSMutableArray *legacy = [NSMutableArray array];
    for (NSString *name in @[@"custom-jumps-v1.plist", @"image-actions-v1.plist"]) {
        NSString *path = [jbroot(@"/var/mobile/Library/com.lindo.metis.clipboard") stringByAppendingPathComponent:name];
        NSArray *items = @[];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
            NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
            if (!data) return NO;
            id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:error];
            if (![plist isKindOfClass:NSArray.class]) {
                if (error && !*error) *error = [NSError errorWithDomain:@"MetisClipboardMigration" code:1
                    userInfo:@{NSLocalizedDescriptionKey: @"旧动作文件无法读取，已保留原文件。"}];
                return NO;
            }
            items = plist;
        }
        [legacy addObject:items];
    }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
    NSDictionary *next = [MTClipboardActionReferences document:snapshot importingText:legacy[0] image:legacy[1]
        doubleTapURL:[defaults stringForKey:kMTPreferenceKeyImageDoubleTapActionURL] ?: @""];
    return [MTSharedResourceStore commitSnapshot:next expectedRevision:[snapshot[@"revision"] unsignedLongLongValue] error:error];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *slot = [self.class referenceSlot];
    self.title = [slot isEqual:@"image-double-tap"] ? @"图片双击动作" :
        ([self.class isImageActionManagement] ? @"图片动作" : @"文字动作");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    // No 排序 button: ordering lives in the list itself (long-press drag).
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.dragDelegate = self;
    self.tableView.dropDelegate = self;
    self.tableView.dragInteractionEnabled = YES;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    [self.tableView registerClass:[MTClipboardActionCell class] forCellReuseIdentifier:MTClipboardActionReuseIdentifier];
    [self.tableView registerClass:[MTClipboardActionCell class] forCellReuseIdentifier:MTClipboardAuxiliaryReuseIdentifier];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    [self configureActionSearch];
}

- (void)configureActionSearch {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.hidesNavigationBarDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索动作";
    self.definesPresentationContext = YES;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:YES animated:animated];
    NSError *error = nil;
    if (![self.class prepareSharedActionsWithError:&error]) [self showError:error];
    [self reloadReferences];
}

#pragma mark - Model

- (void)reloadReferences {
    self.snapshot = [MTSharedResourceStore readSnapshot];
    NSMutableArray *available = [NSMutableArray array];
    for (NSDictionary *action in self.snapshot[@"actions"]) {
        if ([MTClipboardActionReferences supportsEntry:action[@"entry"]]) [available addObject:action];
    }
    self.availableActions = available;
    self.selectedIDs = [NSMutableArray array];
    for (NSDictionary *entry in [MTClipboardActionReferences actionsInDocument:self.snapshot slot:[self.class referenceSlot]]) {
        [self.selectedIDs addObject:entry[@"id"]];
    }
    [self rebuildDisplayRows];
    [self.tableView reloadData];
}

- (NSDictionary *)availableActionWithID:(NSString *)uuid {
    if (!uuid.length) return nil;
    for (NSDictionary *action in self.availableActions) if ([action[@"id"] isEqual:uuid]) return action;
    return nil;
}

- (BOOL)matchesQueryForEntry:(NSDictionary *)entry {
    NSString *query = self.query;
    if (!query.length) return YES;
    NSString *name = MTClipboardActionName(entry);
    if ([name localizedCaseInsensitiveContainsString:query]) return YES;
    NSString *type = MTClipboardActionTypeLabel(entry);
    if ([type localizedCaseInsensitiveContainsString:query]) return YES;
    NSString *group = MTActionGroupNormalizedName(entry[kCustomActionGroupKey]);
    return group.length ? [group localizedCaseInsensitiveContainsString:query] : NO;
}

// 已引用动作排在最前且顺序即面板顺序；其余动作按全局库的顺序跟随其后。
- (void)rebuildDisplayRows {
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableSet *referenced = [NSMutableSet set];
    for (NSString *uuid in self.selectedIDs) {
        NSDictionary *action = [self availableActionWithID:uuid];
        if (!action) continue;
        if (![self matchesQueryForEntry:action[@"entry"]]) continue;
        [referenced addObject:uuid];
        [rows addObject:@{@"kind": @(MTClipboardActionRowKindAction), @"action": action}];
    }
    for (NSDictionary *action in self.availableActions) {
        NSString *uuid = action[@"id"];
        if ([referenced containsObject:uuid]) continue;
        if (![self matchesQueryForEntry:action[@"entry"]]) continue;
        [rows addObject:@{@"kind": @(MTClipboardActionRowKindAction), @"action": action}];
    }
    if (!rows.count) {
        [rows addObject:@{@"kind": @(MTClipboardActionRowKindEmpty)}];
    } else if (!self.query.length) {
        // 搜索态列表是纯过滤结果，不提供新建入口，避免「搜索里新建」的歧义。
        [rows addObject:@{@"kind": @(MTClipboardActionRowKindAdd)}];
    }
    self.displayRows = rows;
}

- (NSDictionary *)rowAtIndex:(NSInteger)index {
    return index >= 0 && index < (NSInteger)self.displayRows.count ? self.displayRows[index] : nil;
}

- (NSDictionary *)actionAtIndex:(NSInteger)index {
    NSDictionary *row = [self rowAtIndex:index];
    return [row[@"kind"] integerValue] == MTClipboardActionRowKindAction ? row[@"action"] : nil;
}

- (BOOL)isReferencedAction:(NSDictionary *)action {
    return action && [self.selectedIDs containsObject:action[@"id"]];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.query = searchController.searchBar.text ?: @"";
    [self rebuildDisplayRows];
    [self.tableView reloadData];
}

#pragma mark - Persistence

- (BOOL)saveReferences {
    NSError *error = nil;
    BOOL saved = [MTClipboardActionReferences setActionIDs:self.selectedIDs slot:[self.class referenceSlot]
        expectedRevision:[self.snapshot[@"revision"] unsignedLongLongValue] error:&error];
    if (!saved) [self showError:error];
    [self reloadReferences];
    return saved;
}

// The global library is owned by the legacy view: appending the definition to
// kLinkActionskey and writing through MTPrefsManager lets the bridge commit it
// to the shared resource store, which is also what makes it visible to the
// keyboard's own pickers.
- (BOOL)persistCustomActionDefinition:(NSDictionary *)definition {
    NSMutableDictionary *prefs = [[[MTPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSArray *stored = [prefs[kLinkActionskey] isKindOfClass:NSArray.class] ? prefs[kLinkActionskey] : @[];
    NSMutableArray *definitions = [NSMutableArray array];
    for (id raw in stored) {
        NSMutableDictionary *entry = [raw isKindOfClass:NSDictionary.class] ? [raw mutableCopy] : [NSMutableDictionary dictionary];
        if ([entry[@"selector"] isEqual:definition[@"selector"]]) continue;
        [definitions addObject:entry];
    }
    [definitions addObject:definition];
    prefs[kLinkActionskey] = definitions;

    NSString *group = MTActionGroupNormalizedName(definition[kCustomActionGroupKey]);
    if (group.length) {
        NSArray *storedGroups = [prefs[kLinkActionGroupsKey] isKindOfClass:NSArray.class] ? prefs[kLinkActionGroupsKey] : @[];
        NSMutableArray *groups = [storedGroups mutableCopy];
        if (![groups containsObject:group]) [groups addObject:group];
        prefs[kLinkActionGroupsKey] = groups;
    }
    [[MTPrefsManager sharedInstance] writePrefs:prefs];
    return YES;
}

// The bridge derives the store UUID deterministically from the legacy
// selector, so the freshly committed action is matched through legacyRef.
- (NSString *)storedActionIDForSelector:(NSString *)selector {
    if (!selector.length) return nil;
    NSDictionary *snapshot = [MTSharedResourceStore readSnapshot];
    for (NSDictionary *action in snapshot[@"actions"]) {
        NSDictionary *legacyRef = action[@"legacyRef"];
        if ([legacyRef isKindOfClass:NSDictionary.class] && [legacyRef[@"selector"] isEqual:selector]) return action[@"id"];
    }
    return nil;
}

- (void)referenceCreatedEntry:(NSDictionary *)entry {
    NSString *selector = entry[@"selector"];
    if (selector.length) [self persistCustomActionDefinition:entry];
    NSString *storedID = selector.length ? [self storedActionIDForSelector:selector] : nil;
    if (!storedID.length) {
        NSError *error = [NSError errorWithDomain:@"MetisClipboardReferences" code:2
            userInfo:@{NSLocalizedDescriptionKey: @"动作已保存，但未能写回引用，请返回后重试。"}];
        [self reloadReferences];
        [self showError:error];
        return;
    }
    if (self.usesSingleSelection) [self.selectedIDs removeAllObjects];
    if (![self.selectedIDs containsObject:storedID]) [self.selectedIDs addObject:storedID];
    [self saveReferences];
}

#pragma mark - Add flow

- (void)presentAddActionTypeChooser {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"选择动作类型"
        message:@"新建的动作保存在全局动作库中，键盘与其他入口同样可见。"
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSString *type in MTClipboardCreatableActionTypes()) {
        [menu addAction:[UIAlertAction actionWithTitle:[MTPLinkActionEditorController displayNameForType:type]
            style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [weakSelf startAddFlowForType:type];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)startAddFlowForType:(NSString *)type {
    // 防御：nil/未知类型直接拒绝——字典字面量插入 nil 值会抛异常，未知类型
    // 会产出编辑器无法识别的脏条目。
    if (![MTClipboardCreatableActionTypes() containsObject:type]) return;
    BOOL opensApplication = [type isEqualToString:kCustomActionTypeOpenApp];
    NSMutableDictionary *entry = [@{
        @"selector": [kLinkActionSelectorPrefix stringByAppendingString:NSUUID.UUID.UUIDString],
        @"name": opensApplication ? @"打开 App" : ([type isEqualToString:kCustomActionTypeShortcut] ? @"快捷指令" : @"新动作"),
        @"icon": opensApplication ? @"app" : ([type isEqualToString:kCustomActionTypeShortcut] ? @"bolt.fill" : @"link"),
        @"link": @"",
        kCustomActionTypeKey: type,
    } mutableCopy];
    if ([type isEqualToString:kCustomActionTypeSystem]) {
        entry[@"name"] = @"系统操作";
        entry[@"icon"] = @"gearshape";
        [entry removeObjectForKey:@"link"];
    }
    if (opensApplication || [type isEqualToString:kCustomActionTypeURLScheme]) entry[kCustomActionFloatingKey] = @YES;

    MTPLinkActionEditorController *editor = [[MTPLinkActionEditorController alloc] init];
    editor.entry = entry;
    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSDictionary *savedEntry) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf referenceCreatedEntry:savedEntry];
    };
    // PS 压栈链在剪切板子包里同样可用（rootController 由设置壳注入）；缺失时
    // 退回普通 UINavigationController 压栈，编辑器内部的子选择器同样生效。
    if ([self rootController]) {
        [editor setRootController:[self rootController]];
        [editor setParentController:self];
        [self pushController:editor];
        return;
    }
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)showError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"动作引用未保存"
        message:error.localizedDescription ?: @"全局动作暂不可用，请返回后重试。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.displayRows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"自定义动作";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.usesSingleSelection) return @"只能引用一个动作，轻点可切换。动作统一在“全局 → 自定义动作”中创建和编辑，也可以在本页底部新建。";
    return @"轻点勾选或取消引用，引用顺序即显示顺序；已引用动作长按可拖动排序。动作统一在“全局 → 自定义动作”中创建和编辑，也可以在本页底部新建。文本插入需要输入框；JavaScript 需使用剪切板输入和复制输出。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *row = [self rowAtIndex:path.row];
    MTClipboardActionRowKind kind = [row[@"kind"] integerValue];
    if (kind == MTClipboardActionRowKindAdd) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MTClipboardAuxiliaryReuseIdentifier forIndexPath:path];
        cell.textLabel.text = @"添加动作";
        cell.textLabel.textColor = UIColor.systemBlueColor;
        cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.imageView.tintColor = UIColor.systemGreenColor;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    if (kind == MTClipboardActionRowKindEmpty) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MTClipboardAuxiliaryReuseIdentifier forIndexPath:path];
        cell.textLabel.text = self.query.length ? @"无匹配的动作" : @"全局动作库中还没有可用动作";
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.imageView.image = nil;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MTClipboardActionReuseIdentifier forIndexPath:path];
    NSDictionary *entry = row[@"action"][@"entry"];
    NSDictionary *action = row[@"action"];
    cell.textLabel.text = MTClipboardActionName(entry);
    cell.textLabel.numberOfLines = 0;
    NSString *group = MTActionGroupNormalizedName(entry[kCustomActionGroupKey]);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", group.length ? group : @"未分组", MTClipboardActionTypeLabel(entry)];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.image = [MTHelper imageForCustomActionEntry:entry];
    cell.imageView.tintColor = UIColor.systemBlueColor;
    cell.accessoryView = nil;
    cell.accessoryType = [self isReferencedAction:action] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSDictionary *row = [self rowAtIndex:path.row];
    MTClipboardActionRowKind kind = [row[@"kind"] integerValue];
    if (kind == MTClipboardActionRowKindAdd) { [self presentAddActionTypeChooser]; return; }
    if (kind == MTClipboardActionRowKindEmpty) return;

    NSDictionary *action = row[@"action"];
    NSString *uuid = action[@"id"];
    if (!uuid.length) return;
    if ([self.selectedIDs containsObject:uuid]) {
        [self.selectedIDs removeObject:uuid];
    } else {
        if (self.usesSingleSelection) [self.selectedIDs removeAllObjects];
        [self.selectedIDs addObject:uuid];
    }
    [self saveReferences];
}

// Checkmark toggles re-render the whole list: referenced rows move to the top
// block, so partial reloads would leave stale ordering behind.

#pragma mark - Reordering (long-press drag, no edit mode)

// Only referenced rows participate, and only outside search: during search the
// on-screen order is a filtered view, not the reference order.
- (BOOL)canReorderRow:(NSInteger)row {
    if (self.query.length) return NO;
    NSDictionary *action = [self actionAtIndex:row];
    return [self isReferencedAction:action];
}

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
    if (![self canReorderRow:indexPath.row]) return @[];
    NSString *uuid = [self actionAtIndex:indexPath.row][@"id"];
    if (!uuid.length) return @[];
    NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:uuid];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];
    item.localObject = uuid;
    return @[item];
}

- (BOOL)tableView:(UITableView *)tableView canHandleDropSession:(id<UIDropSession>)session {
    return session.localDragSession != nil;
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
    if (!destinationIndexPath || ![self canReorderRow:destinationIndexPath.row]) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
    }
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
                                                            intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *source = coordinator.items.firstObject.sourceIndexPath;
    NSIndexPath *destination = coordinator.destinationIndexPath;
    if (!source || !destination || source.row == destination.row) return;
    NSString *movedID = [self actionAtIndex:source.row][@"id"];
    NSString *anchorID = [self actionAtIndex:destination.row][@"id"];
    NSInteger from = [self.selectedIDs indexOfObject:movedID];
    if (!movedID.length || !anchorID.length || from == NSNotFound) return;

    BOOL downward = source.row < destination.row;
    [self.selectedIDs removeObjectAtIndex:from];
    NSInteger anchorIndex = [self.selectedIDs indexOfObject:anchorID];
    if (anchorIndex == NSNotFound) {
        [self.selectedIDs addObject:movedID];
    } else {
        [self.selectedIDs insertObject:movedID atIndex:downward ? anchorIndex + 1 : anchorIndex];
    }
    [self saveReferences];
}

@end
