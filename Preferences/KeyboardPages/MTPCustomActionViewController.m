#import "MTBottomBarLayout.h"
#import "MTPCustomActionViewController.h"
#import "MTPActionGroups.h"
#import "MTPActionOrganizationController.h"
#import <objc/runtime.h>
#import "MTKeyboardPanelPreferences.h"
#import "MTPanelRegistry.h"
#import "MTStatusBarGesturePolicy.h"
#import "MTDockGesturePolicy.h"
#import "MTEdgeGesturePolicy.h"
#import "MTArcGesturePolicy.h"
#import "MTGlobalPanelPolicy.h"
#import "MTPSubActionPickerController.h"
#import "MTPLinkActionEditorController.h"
#import "MTHelper.h"
#import "MTShortcutsGenerator.h"
#import "common.h"

static NSBundle *mtpLocalBundle;

@interface MTPActionPickerCell : UITableViewCell
@end
@implementation MTPActionPickerCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
}
@end

@interface MTPCustomActionViewController () <UISearchResultsUpdating>
// Live multi-select state; only maintained while allowsMultipleSelection is on.
@property (nonatomic, strong) NSMutableSet<NSString *> *pickedSelectors;
// 内置动作的分组展示行（kind=group/action）；fullOrder 换引用时重建。
@property (nonatomic, strong) NSArray<NSDictionary *> *builtInDisplayRows;
@property (nonatomic, strong) NSArray *builtInDisplayRowsSource;
@property (nonatomic, copy) NSArray<NSDictionary *> *customDisplayRows;
@property (nonatomic, copy) NSString *pickerFilterSignature;
@end

@implementation MTPCustomActionViewController

#pragma mark - Storage

- (void)reloadPreferences {
    self.prefs = [[[MTPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    self.linkActions = [NSMutableArray array];
    id stored = self.prefs[kLinkActionskey];
    for (NSDictionary *entry in [stored isKindOfClass:NSArray.class] ? stored : @[]) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *selector = entry[@"selector"];
        if (!MTIsLinkActionSelector(selector)) continue;
        // Preserve the full definition store; context filters only the picker.
        if (!self.customActionsOnly && !(self.requiresGlobalExecution ? MTGlobalCustomActionSupported(entry) :
            MTPanelCustomActionSelectable(entry, self.actionContextKind ?: MTPanelKeyboardKind))) continue;
        [self.linkActions addObject:[entry mutableCopy]];
    }

    [self rebuildCustomActionRows];
    if (self.selectionManagedExternally) return;
    self.selectedSelector = nil;
    NSArray *entries = self.prefs[self.keyID];
    if (![entries isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"identifier"] isEqual:self.identifier]) continue;
        NSString *selector = entry[@"selector2"] ?: entry[@"selector"];
        if ([selector isKindOfClass:[NSString class]] && selector.length > 0) self.selectedSelector = selector;
        break;
    }
}

- (void)writePreferences {
    [[MTPrefsManager sharedInstance] writePrefs:self.prefs];
}

- (void)persistLinkActions {
    self.prefs = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *definitions = MTActionMutableDefinitions(self.prefs);
    NSMutableSet *replaced = [NSMutableSet set];
    for (NSUInteger index = 0; index < definitions.count; index++) {
        id stored = definitions[index];
        if (![stored isKindOfClass:NSDictionary.class]) continue;
        for (NSDictionary *updated in self.linkActions) if ([stored[@"selector"] isEqual:updated[@"selector"]]) {
            definitions[index] = [updated mutableCopy];
            [replaced addObject:updated[@"selector"]];
            break;
        }
    }
    NSMutableArray *groups = [MTActionGroupNames(self.prefs, definitions) mutableCopy];
    for (NSDictionary *updated in self.linkActions) {
        if (![replaced containsObject:updated[@"selector"]]) [definitions addObject:updated];
        NSString *group = MTActionGroupNormalizedName(updated[kCustomActionGroupKey]);
        if (group.length && ![groups containsObject:group]) [groups addObject:group];
    }
    self.prefs[kLinkActionGroupsKey] = groups;
    self.prefs[kLinkActionskey] = definitions;
    [self writePreferences];
}

// Rebuild derived rows before reload: editing can change group or search
// membership, so the original visible index path is no longer authoritative.
- (void)linkActionListDidChange {
    [self rebuildCustomActionRows];
    [self.tableView reloadData];
}

- (void)linkActionRowDidUpdate:(NSInteger)row {
    [self rebuildCustomActionRows];
    [self.tableView reloadData];
}

- (void)persistSelectedSelector:(NSString *)selector {
    self.prefs = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (selector.length && !MTPanelItemAllowed(self.prefs, selector, self.actionContextKind ?: MTPanelKeyboardKind)) return;
    NSMutableArray *entries = [self.prefs[self.keyID] isKindOfClass:[NSArray class]]
        ? [self.prefs[self.keyID] mutableCopy] : [NSMutableArray array];
    NSUInteger found = NSNotFound;
    for (NSUInteger index = 0; index < entries.count; index++) {
        NSDictionary *candidate = entries[index];
        if ([candidate isKindOfClass:[NSDictionary class]] && [candidate[@"identifier"] isEqual:self.identifier]) {
            found = index;
            break;
        }
    }

    if (selector.length == 0) {
        if (found != NSNotFound) [entries removeObjectAtIndex:found];
    } else {
        NSMutableDictionary *entry = found != NSNotFound ? [entries[found] mutableCopy] : [NSMutableDictionary dictionary];
        entry[@"identifier"] = self.identifier;
        entry[@"selector"] = selector;
        [entry removeObjectForKey:@"selector2"];
        if (found != NSNotFound) entries[found] = entry;
        else [entries addObject:entry];
    }

    self.selectedSelector = selector.length ? selector : nil;
    self.prefs[self.keyID] = entries;
    [self writePreferences];
}

// A deleted definition must not remain selected by another button or gesture.
- (void)removeReferencesToSelector:(NSString *)selector fromPreferences:(NSMutableDictionary *)preferences {
    if (preferences[kBottomBarLayoutKey]) {
        NSMutableDictionary *layout = [MTBottomBarLayout(preferences) mutableCopy];
        for (NSString *segment in @[@"left", @"right"]) {
            NSMutableArray *entries = [NSMutableArray array];
            for (NSDictionary *entry in layout[segment])
                if (!([entry[@"kind"] isEqual:@"action"] && [entry[@"value"] isEqual:selector])) [entries addObject:entry];
            layout[segment] = entries;
        }
        preferences[kBottomBarLayoutKey] = layout;
    }
    id groupStored = preferences[kContextActionsKey];
    if ([groupStored isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *groups = [groupStored mutableCopy];
        for (NSString *key in [groups allKeys]) {
            if (![groups[key] isKindOfClass:NSArray.class]) continue;
            NSMutableArray *items = [groups[key] mutableCopy];
            [items removeObject:selector]; groups[key] = items;
        }
        preferences[kContextActionsKey] = groups;
    }
    MTPanelRemoveReferences(preferences, selector);
    MTStatusBarRemoveActionReferences(preferences, selector);
    MTDockGestureRemoveActionReferences(preferences, selector);
    MTEdgeGestureRemoveActionReferences(preferences, selector);
    MTArcGestureRemoveActionReferences(preferences, selector);
    NSMutableSet<NSString *> *keys = [NSMutableSet set];
    for (NSString *configuration in @[@"bottom", @"top"]) {
        for (NSInteger gesture = MTShortcutGestureLongPress; gesture <= MTShortcutGestureTap; gesture++) {
            [keys addObject:MTCustomActionsKeyForGesture((int)gesture, configuration)];
        }
        [keys addObject:MTScopedPreferenceKey(kSubActionskey, configuration)];
    }

    [keys addObjectsFromArray:@[kMTPanelLeftItems, kMTPanelRightItems, kMTPanelCommonItems]];

    for (NSString *key in keys) {
        NSArray *stored = preferences[key];
        if (![stored isKindOfClass:[NSArray class]]) continue;
        NSMutableArray *updated = [NSMutableArray array];
        for (NSDictionary *value in stored) {
            if (![value isKindOfClass:[NSDictionary class]]) {
                [updated addObject:value];
                continue;
            }
            if ([value[@"selectors"] isKindOfClass:[NSArray class]]) {
                NSMutableDictionary *entry = [value mutableCopy];
                NSMutableArray *selectors = [value[@"selectors"] mutableCopy];
                [selectors removeObject:selector];
                entry[@"selectors"] = selectors;
                // Preserve an empty envelope: deleting the last definition
                // must not restore this gesture's legacy configuration.
                [updated addObject:entry];
                continue;
            }
            BOOL selected = [value[@"selector"] isEqual:selector] || [value[@"selector2"] isEqual:selector];
            if (!selected) [updated addObject:value];
        }
        preferences[key] = updated;
    }
}

#pragma mark - Action editor

// 「新建动作」页可选六类型（与 MTPNewActionTypeController 固定顺序一致）；
// legacy url 类型仅用于既有条目兼容，不在新建流程内。
static BOOL MTIsCreatableActionType(NSString *type) {
    static NSSet<NSString *> *creatableTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        creatableTypes = [NSSet setWithObjects:kCustomActionTypeURLScheme, kCustomActionTypeText,
            kCustomActionTypeOpenApp, kCustomActionTypeShortcut, kCustomActionTypeSystem,
            kCustomActionTypeAI, kCustomActionTypeJavaScript, nil];
    });
    return [creatableTypes containsObject:type];
}

- (void)startAddFlowForType:(NSString *)type {
    // 防御：nil/未知类型直接拒绝——字典字面量插入 nil 值会抛异常，未知类型
    // 会产出编辑器无法识别的脏条目。
    if (!MTIsCreatableActionType(type)) {
        NSLog(@"[MetisKeyboard][CustomActions] add flow rejected: unknown type '%@'", type ?: @"<nil>");
        return;
    }
    BOOL opensApplication = [type isEqualToString:kCustomActionTypeOpenApp];
    NSMutableDictionary *entry = [@{
        @"selector": [kLinkActionSelectorPrefix stringByAppendingString:NSUUID.UUID.UUIDString],
        @"name": opensApplication ? LOCALIZED(@"OPEN_APP") : LOCALIZED(@"DEFAULT_BUTTON_NAME"),
        @"icon": opensApplication ? @"app" : ([type isEqualToString:kCustomActionTypeShortcut] ? @"bolt.fill" : @"link"),
        @"link": @"",
        kCustomActionTypeKey: type,
    } mutableCopy];
    if ([type isEqualToString:kCustomActionTypeSystem]) {
        entry[@"name"] = LOCALIZED(@"ACTION_TYPE_SYSTEM");
        entry[@"icon"] = @"gearshape";
        [entry removeObjectForKey:@"link"];
    }
    if ([type isEqualToString:kCustomActionTypeText]) {
        entry[@"icon"] = @"doc.text";
        entry[kCustomActionTextRecordsKey] = @[@""];
        [entry removeObjectForKey:@"link"];
    }
    if ([type isEqualToString:kCustomActionTypeAI]) {
        entry[@"name"] = LOCALIZED(@"ACTION_TYPE_AI");
        entry[@"icon"] = @"sparkles";
        [entry removeObjectForKey:@"link"];
    }
    if (opensApplication || [type isEqualToString:kCustomActionTypeURLScheme]) entry[kCustomActionFloatingKey] = @YES;
    if ([type isEqualToString:kCustomActionTypeJavaScript]) {
        entry[@"icon"] = @"curlybraces";
        entry[@"script"] = @"async function main(str) {\n    return str.toUpperCase();\n}\n";
        entry[@"jsInput"] = @"auto";
        entry[@"jsOutput"] = @"replace";
    }

    MTPLinkActionEditorController *editor = [[MTPLinkActionEditorController alloc] init];
    if (self.defaultActionGroup.length) entry[kCustomActionGroupKey] = self.defaultActionGroup;
    editor.entry = entry;
    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSDictionary *savedEntry) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf reloadPreferences];
        for (NSDictionary *existing in strongSelf.linkActions)
            if ([existing[@"selector"] isEqual:savedEntry[@"selector"]]) return;
        [strongSelf.linkActions addObject:[savedEntry mutableCopy]];
        [strongSelf persistLinkActions];
        [strongSelf linkActionListDidChange];
        // Hosts that allow in-place creation fold the new selector into their
        // pending selection here (both paths: an empty starting list returns
        // early above).
        [strongSelf customActionWasCreated:savedEntry[@"selector"]];
    };
    [editor setRootController:[self rootController]];
    [editor setParentController:[self parentController]];
    // PS 压栈链依赖 rootController：缺失时编辑器不会出现（点击「添加」无响应
    // 的已知故障形态）。此处记录现场，便于宿主日志定位。
    if (!editor.rootController) {
        NSLog(@"[MetisKeyboard][CustomActions] editor push degraded: missing PS root controller");
    }
    [self pushController:editor];
}

// 添加 flow: the type is chosen first (URL Scheme preselected as the first
// entry of the chooser), then startAddFlowForType: runs the pending-entry
// editor. Nothing touches the store here — the action joins the list (and the
// prefs) only when the editor's 保存 reports the finished entry, so backing out
// of the editor never leaves a half-configured row behind.
- (void)presentAddActionTypeChooser {
    __weak typeof(self) weakSelf = self;
    if ([self.actionContextKind isEqual:MTPanelGestureKind]) {
        UIAlertController *menu = [UIAlertController alertControllerWithTitle:LOCALIZED(@"ADD") message:nil preferredStyle:UIAlertControllerStyleAlert];
        for (NSString *type in @[kCustomActionTypeURLScheme, kCustomActionTypeOpenApp, kCustomActionTypeShortcut, kCustomActionTypeSystem])
            [menu addAction:[UIAlertAction actionWithTitle:[MTPLinkActionEditorController displayNameForType:type] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf startAddFlowForType:type]; }]];
        [menu addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:menu animated:YES completion:nil];
        return;
    }
    [MTPLinkActionEditorController presentTypeChooserFromController:self
                                                        currentType:kCustomActionTypeURLScheme
                                                         completion:^(NSString *type) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || type.length == 0) return;
        [strongSelf startAddFlowForType:type];
    }];
}

// Keep custom actions first in both management and selection pages.
- (NSInteger)customActionsSection {
    return 0;
}

- (void)pushEditorForCustomRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.linkActions.count) return;
    MTPLinkActionEditorController *editor = [[MTPLinkActionEditorController alloc] init];
    editor.entry = [self.linkActions[row] mutableCopy];
    NSString *selector = [editor.entry[@"selector"] copy];

    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSDictionary *entry) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![entry[@"selector"] isEqual:selector]) return;
        [strongSelf reloadPreferences];
        for (NSUInteger index = 0; index < strongSelf.linkActions.count; index++)
            if ([strongSelf.linkActions[index][@"selector"] isEqual:selector]) {
                strongSelf.linkActions[index] = [entry mutableCopy];
                [strongSelf persistLinkActions];
                [strongSelf linkActionRowDidUpdate:index];
                break;
            }
    };
    [editor setRootController:[self rootController]];
    [editor setParentController:[self parentController]];
    [self pushController:editor];
}

- (void)infoTapped:(UIButton *)sender {
    UIView *view = sender;
    while (view && ![view isKindOfClass:[UITableViewCell class]]) view = view.superview;
    NSIndexPath *indexPath = [self.tableView indexPathForCell:(UITableViewCell *)view];
    if (self.customActionsOnly && indexPath.section == self.customActionsSection) [self pushEditorForCustomRow:indexPath.row];
}

#pragma mark - Table view

// Selection pages show custom actions, optional keyboard operations and
// panels of the allowed type. Management keeps its existing custom-only layout.
- (BOOL)showsBuiltInActionsSection { return ![self.actionContextKind isEqual:MTPanelGestureKind]; }
- (NSInteger)panelsSection { return self.customActionsOnly ? -1 : (self.showsBuiltInActionsSection ? 2 : 1); }
- (NSArray *)panelCandidates {
    if (self.actionTypeFilter.length) return @[];
    NSArray *panels = MTPanelDefinitions(self.prefs, self.actionContextKind ?: MTPanelKeyboardKind);
    if (!self.actionQuery.length) return panels;
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *panel in panels)
        if ([MTPanelString(panel[@"name"]) localizedCaseInsensitiveContainsString:self.actionQuery]) [result addObject:panel];
    return result;
}
- (NSDictionary *)panelAtRow:(NSInteger)row {
    NSArray *panels = [self panelCandidates];
    return row >= 0 && row < (NSInteger)panels.count ? panels[row] : nil;
}
- (NSString *)selectionAtIndexPath:(NSIndexPath *)path {
    if (path.section == [self panelsSection]) return MTPanelSelector([self panelAtRow:path.row][@"id"]);
    if (path.section == self.customActionsSection) {
        NSInteger global = [self customGlobalIndexAtPath:path];
        return global == NSNotFound ? nil : self.linkActions[global][@"selector"];
    }
    return [self selectorForBuiltInRow:path.row indexOut:NULL];
}
- (NSInteger)builtInSection {
    return (self.customActionsOnly || !self.showsBuiltInActionsSection) ? -1 : 1;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.customActionsOnly) return 1;
    return 2 + (self.showsBuiltInActionsSection ? 1 : 0);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == [self panelsSection]) return LOCALIZED([self.actionContextKind isEqual:MTPanelGestureKind] ? @"PANEL_KIND_GESTURE" : @"PANEL_KIND_KEYBOARD");
    if (section == self.builtInSection) return LOCALIZED(@"BASIC_ACTIONS");
    if (section == self.customActionsSection) {
        // Picker modes hide the whole group when there is nothing to select; the
        // sub-action picker keeps it visible so its 添加 row is always reachable.
        if (!self.customActionsOnly && self.linkActions.count == 0 && !self.allowsCreatingCustomActions) return nil;
        return LOCALIZED(@"CUSTOM_ACTIONS");
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == [self panelsSection]) return [self panelCandidates].count;
    if (section == self.builtInSection) return self.builtInDisplayRows.count;
    // The trailing "添加" row belongs to the management page and the sub-action
    // picker (in-place creation); plain selection pickers stay read-only.
    return self.customDisplayRows.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == self.builtInSection && indexPath.row < (NSInteger)self.builtInDisplayRows.count &&
        [self.builtInDisplayRows[indexPath.row][@"kind"] isEqual:@"group"]) return 30;
    return 44;
}

#pragma mark - Built-in action grouping

// 分组行模型：group 行带 @"key"，action 行带 @"selector" 与 @"index"
// （fullOrder 原始下标）。组内保持 fullOrder 顺序，空组不渲染。
- (NSArray<NSDictionary *> *)builtInDisplayRows {
    if (self.actionTypeFilter.length) return @[];
    if (_builtInDisplayRows && _builtInDisplayRowsSource == self.fullOrder) return _builtInDisplayRows;
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (NSString *group in [MTShortcutsGenerator builtInActionGroupOrder]) {
        NSMutableArray<NSDictionary *> *actions = [NSMutableArray array];
        for (NSUInteger index = 0; index < self.fullOrder.count; index++) {
            NSString *selector = [MTHelper actionNameFromArray:self.fullOrder atIndex:index];
            if (!selector.length) continue;
            if (self.actionQuery.length && ![selector localizedCaseInsensitiveContainsString:self.actionQuery] &&
                ![[MTHelper localizedStringForActionNamed:selector shortName:NO bundle:mtpLocalBundle] localizedCaseInsensitiveContainsString:self.actionQuery]) continue;
            if (![group isEqualToString:[MTShortcutsGenerator builtInActionGroupForSelector:selector]]) continue;
            [actions addObject:@{@"kind": @"action", @"selector": selector, @"index": @(index)}];
        }
        if (!actions.count) continue;
        [rows addObject:@{@"kind": @"group", @"key": group}];
        [rows addObjectsFromArray:actions];
    }
    _builtInDisplayRowsSource = self.fullOrder;
    _builtInDisplayRows = rows;
    return rows;
}

// action 行返回其 selector 并带出 fullOrder 下标；group 行返回 nil。
- (NSString *)selectorForBuiltInRow:(NSInteger)row indexOut:(NSUInteger *)indexOut {
    if (row < 0 || row >= (NSInteger)self.builtInDisplayRows.count) return nil;
    NSDictionary *model = self.builtInDisplayRows[row];
    if (![model[@"kind"] isEqual:@"action"]) return nil;
    if (indexOut) *indexOut = [model[@"index"] unsignedIntegerValue];
    return model[@"selector"];
}

- (UITableViewCell *)builtInCellForIndexPath:(NSIndexPath *)indexPath {
    NSUInteger actionIndex = 0;
    NSString *selector = [self selectorForBuiltInRow:indexPath.row indexOut:&actionIndex];
    UITableViewCell *cell;
    if (!selector) {
        cell = [self.tableView dequeueReusableCellWithIdentifier:@"MTPActionGroupCell" forIndexPath:indexPath];
        NSString *group = self.builtInDisplayRows[indexPath.row][@"key"];
        cell.textLabel.text = LOCALIZED([@"ACTION_GROUP_" stringByAppendingString:group.uppercaseString]);
        cell.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    cell = [self.tableView dequeueReusableCellWithIdentifier:@"TypeXLPItemCell" forIndexPath:indexPath];
    BOOL checked = self.allowsMultipleSelection
        ? [self.pickedSelectors containsObject:selector]
        : [self.selectedSelector isEqualToString:selector];
    cell.accessoryType = checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.editingAccessoryView = nil;
    cell.textLabel.text = [MTHelper localizedStringForActionNamed:selector shortName:NO bundle:mtpLocalBundle];
    cell.imageView.image = [MTHelper imageFromArray:self.fullOrder atIndex:actionIndex withSystemColor:YES completion:nil];
    return cell;
}

- (UITableViewCell *)customCellForIndexPath:(NSIndexPath *)indexPath table:(UITableView *)table {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"TypeXCustomLinkActionCell" forIndexPath:indexPath];
    NSInteger global = [self customGlobalIndexAtPath:indexPath];
    NSDictionary *entry = self.linkActions[global];
    NSString *selector = entry[@"selector"];
    NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
    cell.textLabel.text = name.length ? name : LOCALIZED(@"DEFAULT_BUTTON_NAME");
    NSString *group = MTActionGroupNormalizedName(entry[kCustomActionGroupKey]);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", group.length ? group : LOCALIZED(@"UNGROUPED"),
        [MTPLinkActionEditorController displayNameForType:MTActionDisplayType(entry)]];
    cell.imageView.image = [MTHelper imageForCustomActionEntry:entry];
    // 与 MTPCustomActionsController 的显式蓝一致：符号统一蓝、App 图标 AlwaysOriginal 不受影响。
    cell.imageView.tintColor = [UIColor systemBlueColor];
    BOOL checked = self.allowsMultipleSelection
        ? [self.pickedSelectors containsObject:selector]
        : [self.selectedSelector isEqualToString:selector];
    cell.accessoryType = checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.editingAccessoryView = nil;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    [self configureActionTableView:tableView];
    if (indexPath.section == [self panelsSection]) {
        NSDictionary *panel = [self panelAtRow:indexPath.row];
        NSString *selector = MTPanelSelector(panel[@"id"]);
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TypeXCustomLinkActionCell" forIndexPath:indexPath];
        cell.textLabel.text = MTPanelString(panel[@"name"]);
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [MTHelper imageForIconConfig:MTPanelDefaultIconName(panel[@"kind"]) defaultSymbolName:@"square.grid.2x2"];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        BOOL selected = self.allowsMultipleSelection ? [self.pickedSelectors containsObject:selector] : [self.selectedSelector isEqual:selector];
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.textLabel.textColor = UIColor.labelColor;
        return cell;
    }
    if (indexPath.section == self.builtInSection) return [self builtInCellForIndexPath:indexPath];
    NSDictionary *row = [self customRowAtPath:indexPath];
    if ([row[@"kind"] isEqual:@"add"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MTPActionAddCell" forIndexPath:indexPath];
        cell.textLabel.text = LOCALIZED(@"ADD");
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.imageView.tintColor = [UIColor systemGreenColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    if ([row[@"kind"] isEqual:@"group"] || [row[@"kind"] isEqual:@"empty"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MTPActionGroupCell" forIndexPath:indexPath];
        NSString *group = row[@"group"];
        cell.textLabel.text = [row[@"kind"] isEqual:@"empty"] ? LOCALIZED((self.actionQuery.length || self.actionTypeFilter.length) ? @"SEARCH_NO_MATCH" : @"NO_CUSTOM_ACTIONS") :
            [NSString stringWithFormat:@"%@ %@ · %@", [row[@"collapsed"] boolValue] ? @"▸" : @"▾",
                group.length ? group : LOCALIZED(@"UNGROUPED"), row[@"count"]];
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    if ([self customGlobalIndexAtPath:indexPath] == NSNotFound) return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    return [self customCellForIndexPath:indexPath table:tableView];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    // The management page and the sub-action picker carry the "添加" row;
    // plain selection pickers never render it (row count stays at list size).
    if (indexPath.section == self.customActionsSection) {
        NSDictionary *row = [self customRowAtPath:indexPath];
        if ([row[@"kind"] isEqual:@"group"]) { [self toggleActionGroup:row[@"group"]]; return; }
        if ([row[@"kind"] isEqual:@"add"]) { [self presentAddActionTypeChooser]; return; }
        if ([self customGlobalIndexAtPath:indexPath] == NSNotFound) return;
    }

    // Management page: tapping a custom action edits it instead of selecting.
    if (self.customActionsOnly) {
        [self pushEditorForCustomRow:[self customGlobalIndexAtPath:indexPath]];
        return;
    }

    if (self.allowsMultipleSelection) {
        NSString *selector = [self selectionAtIndexPath:indexPath];
        if (!selector.length) return; // 分组标题行不参与选择
        if ([self.pickedSelectors containsObject:selector]) {
            [self.pickedSelectors removeObject:selector];
        } else {
            [self.pickedSelectors addObject:selector];
        }
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }

    NSString *selector = [self selectionAtIndexPath:indexPath];
    if (!selector.length) return; // 分组标题行不参与选择
    NSString *oldSelector = self.selectedSelector;

    NSDictionary *live = [MTPrefsManager.sharedInstance readPrefs];
    BOOL allowed = self.requiresGlobalExecution
        ? (MTPanelAllowed(live, selector, MTPanelGestureKind) || MTGlobalCustomActionSupported(MTPanelActionDefinition(live, selector)))
        : MTPanelItemAllowed(live, selector, self.actionContextKind ?: MTPanelKeyboardKind);
    if (!allowed) { [self reloadPreferences]; [tableView reloadData]; return; }
    if (self.selectionManagedExternally) {
        self.selectedSelector = selector;
        NSMutableArray *paths = [NSMutableArray arrayWithObject:indexPath];
        NSIndexPath *oldPath = [self indexPathForSelector:oldSelector];
        if (oldPath && ![oldPath isEqual:indexPath]) [paths addObject:oldPath];
        [tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationAutomatic];
        if (self.completion) self.completion(selector);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    [self persistSelectedSelector:[oldSelector isEqualToString:selector] ? nil : selector];

    NSMutableArray *paths = [NSMutableArray arrayWithObject:indexPath];
    NSIndexPath *oldPath = [self indexPathForSelector:oldSelector];
    if (oldPath && ![oldPath isEqual:indexPath]) [paths addObject:oldPath];
    [tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (NSIndexPath *)indexPathForSelector:(NSString *)selector {
    if (selector.length == 0) return nil;
    NSUInteger panelRow = 0;
    for (NSDictionary *panel in [self panelCandidates]) {
        if ([MTPanelSelector(panel[@"id"]) isEqual:selector] && [self panelsSection] >= 0) return [NSIndexPath indexPathForRow:panelRow inSection:[self panelsSection]];
        panelRow++;
    }
    if (self.builtInSection >= 0) {
        for (NSUInteger row = 0; row < self.builtInDisplayRows.count; row++) {
            NSDictionary *model = self.builtInDisplayRows[row];
            if ([model[@"kind"] isEqual:@"action"] && [model[@"selector"] isEqualToString:selector]) {
                return [NSIndexPath indexPathForRow:row inSection:self.builtInSection];
            }
        }
    }
    for (NSUInteger row = 0; row < self.customDisplayRows.count; row++) {
        NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:self.customActionsSection];
        NSInteger global = [self customGlobalIndexAtPath:path];
        if (global != NSNotFound && [self.linkActions[global][@"selector"] isEqual:selector]) return path;
    }
    return nil;
}

- (void)customActionWasCreated:(NSString *)selector {
}

- (void)markSelectorPicked:(NSString *)selector {
    if (selector.length == 0) return;
    [self.pickedSelectors addObject:selector];
}

#pragma mark - Multi-select (batch pick)

// Report picks in on-screen order (custom actions, then built-ins) so a batch
// append lands in the order the user saw.
- (NSArray<NSString *> *)orderedPickedSelectors {
    NSMutableArray<NSString *> *ordered = [NSMutableArray array];
    for (NSArray *indexes in MTActionGroupSectionIndexes(self.linkActions, MTActionGroupNames(self.prefs, self.linkActions)))
        for (NSNumber *index in indexes) {
            NSString *selector = self.linkActions[index.unsignedIntegerValue][@"selector"];
            if ([self.pickedSelectors containsObject:selector]) [ordered addObject:selector];
        }
    for (NSUInteger row = 0; row < self.fullOrder.count; row++) {
        NSString *selector = [MTHelper actionNameFromArray:self.fullOrder atIndex:row];
        if ([self.pickedSelectors containsObject:selector]) [ordered addObject:selector];
    }
    for (NSDictionary *panel in [self panelCandidates]) {
        NSString *selector = MTPanelSelector(panel[@"id"]);
        if ([self.pickedSelectors containsObject:selector]) [ordered addObject:selector];
    }
    return ordered;
}

- (void)confirmMultiSelection {
    NSDictionary *live = [MTPrefsManager.sharedInstance readPrefs];
    NSMutableArray *selectors = [NSMutableArray array];
    for (NSString *selector in [self orderedPickedSelectors])
        if (MTPanelItemAllowed(live, selector, self.actionContextKind ?: MTPanelKeyboardKind)) [selectors addObject:selector];
    if (self.multiSelectionCompletion) self.multiSelectionCompletion(selectors);
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Edit and delete

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return (self.customActionsOnly || self.allowsDeletingCustomActions) && [self customGlobalIndexAtPath:indexPath] != NSNotFound;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView canEditRowAtIndexPath:indexPath]
        ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || ![self tableView:tableView canEditRowAtIndexPath:indexPath]) return;
    NSString *selector = [self selectionAtIndexPath:indexPath];
    if (!selector.length) return;
    [self reloadPreferences];
    NSMutableArray *definitions = [NSMutableArray array];
    for (id entry in MTActionMutableDefinitions(self.prefs))
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"selector"] isEqual:selector]) [definitions addObject:entry];
    self.prefs[kLinkActionskey] = definitions;
    [self removeReferencesToSelector:selector fromPreferences:self.prefs];
    if ([self.selectedSelector isEqualToString:selector]) self.selectedSelector = nil;
    [self.pickedSelectors removeObject:selector];
    [self writePreferences];
    [self reloadPreferences];
    [tableView reloadData];
}

// Delete is available in normal browsing, without an edit/sort mode. Capture
// the stable selector so reloads cannot turn an old swipe into another deletion.
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self tableView:tableView canEditRowAtIndexPath:indexPath]) return nil;
    NSString *selector = [self selectionAtIndexPath:indexPath];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:LOCALIZED(@"DELETE")
                                                                       handler:^(__unused UIContextualAction *action,
                                                                                 __unused UIView *sourceView,
                                                                                 void (^completionHandler)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSIndexPath *currentPath = [strongSelf indexPathForSelector:selector];
        BOOL canDelete = strongSelf && currentPath && [strongSelf tableView:strongSelf.tableView canEditRowAtIndexPath:currentPath];
        if (canDelete) [strongSelf tableView:strongSelf.tableView
            commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:currentPath];
        completionHandler(canDelete);
    }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[delete]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

#pragma mark - Lifecycle

- (void)rebuildCustomActionRows {
    self.customDisplayRows = MTActionPickerRows(self.linkActions, self.prefs, self.actionQuery, self.actionTypeFilter,
        ^NSString *(NSDictionary *entry) { return [MTPLinkActionEditorController displayNameForType:MTActionDisplayType(entry)]; },
        self.customActionsOnly || self.allowsCreatingCustomActions);
}
- (NSDictionary *)customRowAtPath:(NSIndexPath *)path {
    return path && path.section == self.customActionsSection && path.row >= 0 && path.row < (NSInteger)self.customDisplayRows.count
        ? self.customDisplayRows[path.row] : nil;
}
- (NSInteger)customGlobalIndexAtPath:(NSIndexPath *)path {
    NSDictionary *row = [self customRowAtPath:path];
    if (![row[@"kind"] isEqual:@"action"]) return NSNotFound;
    NSInteger index = [row[@"index"] integerValue];
    return index >= 0 && index < (NSInteger)self.linkActions.count ? index : NSNotFound;
}
- (void)configureActionSearch {
    self.actionSearchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.actionSearchController.searchResultsUpdater = self;
    self.actionSearchController.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = self.actionSearchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = controller.searchBar.text ?: @"";
    if (![query isEqual:self.actionQuery ?: @""]) [self.pickedSelectors removeAllObjects];
    self.actionQuery = query;
    [self actionFilterDidChange];
}
- (void)actionFilterDidChange {
    NSString *signature = [NSString stringWithFormat:@"%@|%@", self.actionQuery ?: @"", self.actionTypeFilter ?: @""];
    if (![signature isEqual:self.pickerFilterSignature]) [self.pickedSelectors removeAllObjects];
    self.pickerFilterSignature = signature;
    self.builtInDisplayRows = nil;
    [self rebuildCustomActionRows];
    [self.tableView reloadData];
    [self updateActionPickerToolbar];
}
- (void)updateActionPickerToolbar {
    NSString *type = self.actionTypeFilter.length ? [MTPLinkActionEditorController displayNameForType:self.actionTypeFilter] : LOCALIZED(@"ACTION_ALL_TYPES");
    self.toolbarItems = @[[[UIBarButtonItem alloc] initWithTitle:[NSString stringWithFormat:@"%@: %@", LOCALIZED(@"ACTION_TYPE_FILTER"), type]
        style:UIBarButtonItemStylePlain target:self action:@selector(showActionTypeFilter)]];
}
- (void)showActionTypeFilter {
    __weak typeof(self) weakSelf = self;
    MTPPresentActionTypeFilter(self, self.actionTypeFilter, ^(NSString *type) {
        __strong typeof(weakSelf) owner = weakSelf;
        if (!owner) return;
        if (![type isEqual:owner.actionTypeFilter ?: @""]) [owner.pickedSelectors removeAllObjects];
        owner.actionTypeFilter = type;
        [owner actionFilterDidChange];
    });
}
- (void)toggleActionGroup:(NSString *)group {
    NSMutableDictionary *prefs = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableSet *collapsed = [MTActionCollapsedGroups(prefs) mutableCopy];
    if ([collapsed containsObject:group]) [collapsed removeObject:group]; else [collapsed addObject:group];
    prefs[kLinkActionCollapsedGroupsKey] = collapsed.allObjects;
    [MTPrefsManager.sharedInstance writePrefs:prefs];
    [self reloadPreferences];
    [self.tableView reloadData];
}

- (void)resetToDefault {
    if (self.selectionManagedExternally) return;
    [self persistSelectedSelector:nil];
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadPreferences];
    [self.tableView reloadData];
    if (!self.customActionsOnly) {
        [self updateActionPickerToolbar];
        [self.navigationController setToolbarHidden:NO animated:animated];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setToolbarHidden:YES animated:animated];
}

- (void)configureActionTableView:(UITableView *)tableView {
    static char registered;
    if (objc_getAssociatedObject(tableView, &registered)) return;
    [tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TypeXLPItemCell"];
    [tableView registerClass:[MTPActionPickerCell class] forCellReuseIdentifier:@"TypeXCustomLinkActionCell"];
    [tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"MTPActionAddCell"];
    [tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"MTPActionGroupCell"];
    objc_setAssociatedObject(tableView, &registered, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)viewDidLoad {
    mtpLocalBundle = [NSBundle bundleWithPath:bundlePath];
    [mtpLocalBundle load];
    [super viewDidLoad];
    [self reloadPreferences];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self configureActionTableView:self.tableView];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.view = self.tableView;
    self.pickerFilterSignature = [NSString stringWithFormat:@"%@|%@", self.actionQuery ?: @"", self.actionTypeFilter ?: @""];
    if (!self.customActionsOnly) [self configureActionSearch];

    if (!self.selectionManagedExternally) {
        self.defaultBtn = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"DEFAULT")
                                                           style:UIBarButtonItemStylePlain
                                                          target:self
                                                          action:@selector(resetToDefault)];
        self.navigationItem.rightBarButtonItem = self.defaultBtn;
    }

    if (self.allowsMultipleSelection) {
        self.pickedSelectors = [NSMutableSet set];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"DONE")
                                                                                  style:UIBarButtonItemStyleDone
                                                                                 target:self
                                                                                 action:@selector(confirmMultiSelection)];
    }
}

@end
