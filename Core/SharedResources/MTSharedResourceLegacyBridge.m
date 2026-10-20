#import "MTSharedResourceLegacyBridge.h"
#import "MTSharedResourceIDs.h"
#import "MTSharedResourceStore.h"
#import "MTSharedResourceValidator.h"
#import "MTLog.h"

// —— legacy 常量（与 Modules/Keyboard/Sources/common.h、MTPanelRegistry.h、
// MTKeyboardPanelPreferences.h 保持一致；此处本地重复以便主机测试只依赖
// Foundation。改动来源常量时必须同步这里）。——
static NSString *const MTLegacyLinkActionsKey = @"linkactions";
static NSString *const MTLegacyGroupsKey = @"linkactiongroups";
static NSString *const MTLegacyCollapsedGroupsKey = @"linkactioncollapsedgroups";
static NSString *const MTLegacyPanelsKey = @"panels";
static NSString *const MTLegacyToolbarBindingsKey = @"toolbarpanelbindings";
static NSString *const MTLegacyDockBindingsKey = @"dockgesturebindings";
static NSString *const MTLegacyStatusBarBindingsKey = @"statusbargesturebindings";
static NSString *const MTLegacyEdgeBindingsKey = @"screenedgegesturebindings";
static NSString *const MTLegacyLinkSelectorPrefix = @"__typex_link_action_";
static NSString *const MTLegacyPanelSelectorPrefix = @"__typex_panel_";
static NSString *const MTLegacyPanelKindKeyboard = @"keyboard";
static NSString *const MTLegacyPanelKindGesture = @"gesture";
static NSArray<NSString *> *MTLegacyPanelStyleKeys(void) {
    return @[@"keyboardpanelcolumns", @"keyboardpanelscale",
             @"keyboardpanelsystemtogglesBOOL", @"keyboardpanelsystemslidersBOOL"];
}

static NSString *MTBridgeString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSArray *MTBridgeArray(id value) {
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSDictionary *MTBridgeDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSString *MTBridgeActionSelectorForUUID(NSString *uuid) {
    NSString *suffix = uuid.length >= 8 ? [uuid substringToIndex:8] : uuid;
    return [MTLegacyLinkSelectorPrefix stringByAppendingString:suffix];
}

static NSString *MTBridgePanelLegacyIDForUUID(NSString *uuid) {
    NSString *suffix = uuid.length >= 8 ? [uuid substringToIndex:8] : uuid;
    return [@"shared-" stringByAppendingString:suffix];
}

static NSDictionary *MTBridgeTargetFromSelector(NSString *selector,
                                                NSDictionary<NSString *, NSString *> *actionsBySelector,
                                                NSDictionary<NSString *, NSString *> *panelsBySelector,
                                                NSMutableArray<NSDictionary *> *unresolved) {
    if (!selector.length) return @{ @"kind": MTSharedTargetKindNone };
    if ([selector hasPrefix:MTLegacyLinkSelectorPrefix] && selector.length > MTLegacyLinkSelectorPrefix.length) {
        NSString *uuid = actionsBySelector[selector];
        if (!uuid) {
            [unresolved addObject:@{@"selector": selector, @"reason": @"missing-action"}];
            return @{ @"kind": MTSharedTargetKindNone };
        }
        return @{ @"kind": MTSharedTargetKindAction, @"id": uuid };
    }
    if ([selector hasPrefix:MTLegacyPanelSelectorPrefix] && selector.length > MTLegacyPanelSelectorPrefix.length) {
        NSString *uuid = panelsBySelector[selector];
        if (!uuid) {
            [unresolved addObject:@{@"selector": selector, @"reason": @"missing-panel"}];
            return @{ @"kind": MTSharedTargetKindNone };
        }
        return @{ @"kind": MTSharedTargetKindPanel, @"id": uuid };
    }
    return @{ @"kind": MTSharedTargetKindBuiltin, @"id": selector };
}

@implementation MTSharedResourceLegacyBridge

+ (NSArray<NSString *> *)bridgedResourceKeys {
    return @[MTLegacyLinkActionsKey, MTLegacyPanelsKey, MTLegacyGroupsKey,
             MTLegacyCollapsedGroupsKey, MTLegacyToolbarBindingsKey,
             MTLegacyDockBindingsKey, MTLegacyStatusBarBindingsKey, MTLegacyEdgeBindingsKey];
}

#pragma mark - Import (legacy → store)

+ (NSDictionary *)documentByImportingLegacyPreferences:(NSDictionary *)legacyPreferences
                                           intoDocument:(NSDictionary *)base {
    NSDictionary *baseDocument = base ?: [MTSharedResourceStore emptyDocument];
    NSMutableDictionary *result = [baseDocument mutableCopy];

    NSArray *legacyActions = MTBridgeArray(legacyPreferences[MTLegacyLinkActionsKey]);
    NSArray *legacyPanels = MTBridgeArray(legacyPreferences[MTLegacyPanelsKey]);
    NSMutableArray<NSDictionary *> *unresolved = [NSMutableArray array];

    // 1. 动作：按 selector 确定性分配 UUID；同名不去重（不同 entry 可能
    //    有不同 URL/脚本/输入模式，05 §3）。
    NSMutableArray<NSDictionary *> *importedActions = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSString *> *actionsBySelector = [NSMutableDictionary dictionary];
    for (id raw in legacyActions) {
        NSDictionary *entry = MTBridgeDictionary(raw);
        if (!entry) continue;
        NSString *selector = MTBridgeString(entry[@"selector"]);
        if (!selector.length) continue;
        NSMutableDictionary *payload = [entry mutableCopy];
        [payload removeObjectForKey:@"selector"];
        NSString *uuid = MTSharedDeterministicUUID(
            [NSString stringWithFormat:@"keyboard|action|%@", selector]);
        if (!uuid) continue;
        [importedActions addObject:@{
            @"id": uuid,
            @"entry": [payload copy],
            @"legacyRef": @{ @"source": MTSharedResourceSourceKeyboard, @"selector": selector },
        }];
        if (!actionsBySelector[selector]) actionsBySelector[selector] = uuid;
    }

    // 2. 面板：先建 legacyPanelID → UUID 映射（允许面板间前向引用），
    //    items 的 selector 引用映射到稳定 UUID，保持原相对顺序。
    NSMutableDictionary<NSString *, NSString *> *panelsBySelector = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *panelRows = [NSMutableArray array];
    NSMutableSet<NSString *> *seenPanelIDs = [NSMutableSet set];
    for (id raw in legacyPanels) {
        NSDictionary *panel = MTBridgeDictionary(raw);
        if (!panel) continue;
        NSString *panelID = MTBridgeString(panel[@"id"]);
        if (!panelID.length || panelID.length > 128 || [seenPanelIDs containsObject:panelID]) continue;
        [seenPanelIDs addObject:panelID];
        panelsBySelector[[MTLegacyPanelSelectorPrefix stringByAppendingString:panelID]] =
            MTSharedDeterministicUUID([NSString stringWithFormat:@"keyboard|panel|%@", panelID]);
    }
    for (id raw in legacyPanels) {
        NSDictionary *panel = MTBridgeDictionary(raw);
        if (!panel) continue;
        NSString *panelID = MTBridgeString(panel[@"id"]);
        NSString *uuid = panelsBySelector[[MTLegacyPanelSelectorPrefix stringByAppendingString:panelID]];
        if (!uuid) continue;
        NSString *kind = MTBridgeString(panel[@"kind"]);
        if (![kind isEqual:MTLegacyPanelKindKeyboard] && ![kind isEqual:MTLegacyPanelKindGesture]) {
            kind = MTLegacyPanelKindGesture;
        }
        NSString *name = MTBridgeString(panel[@"name"]);
        if (!name.length) name = @"Panel";
        NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
        NSArray *legacyItems = MTBridgeArray(panel[@"items"]);
        for (NSUInteger index = 0; index < legacyItems.count; index++) {
            NSDictionary *item = MTBridgeDictionary(legacyItems[index]);
            if (!item) continue;
            NSString *selector = MTBridgeString(item[@"selector"]);
            if (!selector.length) continue;
            NSDictionary *target = MTBridgeTargetFromSelector(selector, actionsBySelector, panelsBySelector, unresolved);
            NSString *legacyItemID = MTBridgeString(item[@"id"]);
            NSString *itemUUID = MTSharedIsValidUUIDString(legacyItemID) ? legacyItemID : MTSharedDeterministicUUID(
                legacyItemID.length ? [NSString stringWithFormat:@"keyboard|item|%@|%@", panelID, legacyItemID] :
                [NSString stringWithFormat:@"keyboard|item|%@|%lu|%@", panelID, (unsigned long)index, selector]);
            if (!itemUUID) continue;
            NSMutableDictionary *row = [@{ @"itemID": itemUUID, @"target": target } mutableCopy];
            if (legacyItemID.length && ![legacyItemID isEqual:itemUUID]) row[@"legacyItemID"] = legacyItemID;
            if ([item[@"name"] isKindOfClass:NSString.class]) row[@"name"] = item[@"name"];
            [items addObject:row];
        }
        NSMutableDictionary *style = [NSMutableDictionary dictionary];
        NSDictionary *preferences = MTBridgeDictionary(panel[@"preferences"]);
        if (preferences) {
            for (NSString *key in MTLegacyPanelStyleKeys())
                if (preferences[key] != nil) style[key] = preferences[key];
        }
        [panelRows addObject:@{
            @"id": uuid,
            @"name": name,
            @"icon": MTBridgeString(panel[@"icon"]),
            @"legacyKind": kind,
            @"legacyPanelID": panelID,
            @"legacyRef": @{ @"source": MTSharedResourceSourceKeyboard },
            @"style": [style copy],
            @"items": [items copy],
        }];
    }

    // 3. 分组：名称、排序与折叠状态完整迁移（05 §3）。
    NSMutableArray<NSDictionary *> *groups = [NSMutableArray array];
    NSMutableSet<NSString *> *collapsed = [NSMutableSet set];
    for (id name in MTBridgeArray(legacyPreferences[MTLegacyCollapsedGroupsKey])) {
        // 空字符串是“未分组”的稳定标识，也需要保存折叠状态。
        if ([name isKindOfClass:NSString.class]) [collapsed addObject:name];
    }
    for (id name in MTBridgeArray(legacyPreferences[MTLegacyGroupsKey])) {
        NSString *string = MTBridgeString(name);
        if (!string.length) continue;
        NSString *uuid = MTSharedDeterministicUUID([NSString stringWithFormat:@"keyboard|group|%@", string]);
        if (!uuid) continue;
        [groups addObject:@{
            @"id": uuid,
            @"name": string,
            @"order": @(groups.count),
            @"collapsed": @([collapsed containsObject:string]),
        }];
    }

    // 4. 绑定：工具栏四槽 / Dock 三向 / 状态栏各槽 → 稳定入口 ID。
    NSMutableArray<NSDictionary *> *bindings = [NSMutableArray array];
    // Clipboard bindings are independent of the keyboard/gesture editor projection.
    for (NSDictionary *binding in MTBridgeArray(baseDocument[@"bindings"])) {
        NSString *identifier = MTBridgeString(binding[@"id"]);
        if (![identifier hasPrefix:@"keyboard.toolbar."] && ![identifier hasPrefix:@"gesture.dock."] &&
            ![identifier hasPrefix:@"gesture.statusbar."] && ![identifier hasPrefix:@"gesture.screenedge."]) [bindings addObject:binding];
    }
    void (^bind)(NSString *, NSString *, NSString *, id) = ^(NSString *bindingID, NSString *source, NSString *placement, id rawTarget) {
        NSString *selector = nil;
        NSDictionary *options = nil;
        if ([rawTarget isKindOfClass:NSString.class]) {
            selector = MTBridgeString(rawTarget);
        } else {
            NSDictionary *binding = MTBridgeDictionary(rawTarget);
            selector = MTBridgeString(binding[@"selector"]);
            NSMutableDictionary *mutableOptions = [binding mutableCopy];
            [mutableOptions removeObjectForKey:@"selector"];
            if (mutableOptions.count) options = [mutableOptions copy];
        }
        NSDictionary *target = MTBridgeTargetFromSelector(selector, actionsBySelector, panelsBySelector, unresolved);
        NSMutableDictionary *row = [@{
            @"id": bindingID,
            @"source": source,
            @"target": target,
            @"presentation": @{ @"preferredPlacement": placement },
            @"inputPolicy": @"source",
        } mutableCopy];
        if (options.count) row[@"options"] = options;
        [bindings addObject:row];
    };
    NSDictionary *toolbar = MTBridgeDictionary(legacyPreferences[MTLegacyToolbarBindingsKey]) ?: @{};
    for (NSString *slot in @[@"top.left", @"top.right", @"bottom.left", @"bottom.right"]) {
        bind([NSString stringWithFormat:@"keyboard.toolbar.%@", slot], MTSharedResourceSourceKeyboard,
             @"keyboardAnchor", toolbar[slot] ?: @"");
    }
    NSDictionary *dock = MTBridgeDictionary(legacyPreferences[MTLegacyDockBindingsKey]) ?: @{};
    for (NSString *direction in @[@"up", @"left", @"right"]) {
        bind([NSString stringWithFormat:@"gesture.dock.%@", direction], MTSharedResourceSourceGesture,
             @"sourceAnchor", dock[direction] ?: @"");
    }
    NSDictionary *statusBar = MTBridgeDictionary(legacyPreferences[MTLegacyStatusBarBindingsKey]) ?: @{};
    for (NSString *slot in statusBar.allKeys) {
        if (![slot isKindOfClass:NSString.class] || !slot.length || slot.length > 64) continue;
        bind([NSString stringWithFormat:@"gesture.statusbar.%@", slot], MTSharedResourceSourceGesture,
             @"sourceAnchor", statusBar[slot]);
    }
    NSDictionary *edges = MTBridgeDictionary(legacyPreferences[MTLegacyEdgeBindingsKey]) ?: @{};
    for (NSString *slot in @[@"left", @"right", @"left2", @"right2"]) {
        if (!MTBridgeDictionary(edges[slot])) continue;
        bind([NSString stringWithFormat:@"gesture.screenedge.%@", slot], MTSharedResourceSourceGesture,
             @"sourceAnchor", edges[slot]);
    }

    // 5. 合并：只替换来源为 keyboard 的资源；其他来源（后续接入的剪切板等）保留。
    NSMutableArray *mergedActions = [NSMutableArray array];
    NSMutableArray *mergedPanels = [NSMutableArray array];
    for (id raw in MTBridgeArray(baseDocument[@"actions"])) {
        NSDictionary *action = MTBridgeDictionary(raw);
        if (action && ![MTBridgeString(MTBridgeDictionary(action[@"legacyRef"])[@"source"])
                isEqual:MTSharedResourceSourceKeyboard]) [mergedActions addObject:action];
    }
    [mergedActions addObjectsFromArray:importedActions];
    for (id raw in MTBridgeArray(baseDocument[@"panels"])) {
        NSDictionary *panel = MTBridgeDictionary(raw);
        // Older imports only stored legacyPanelID. They are keyboard-owned
        // too: retaining them duplicates IDs and rejects every subsequent save.
        NSString *source = MTBridgeString(MTBridgeDictionary(panel[@"legacyRef"])[@"source"]);
        BOOL keyboardPanel = [source isEqual:MTSharedResourceSourceKeyboard] ||
            (!source.length && MTBridgeString(panel[@"legacyPanelID"]).length);
        if (panel && !keyboardPanel) [mergedPanels addObject:panel];
    }
    [mergedPanels addObjectsFromArray:panelRows];

    result[@"actions"] = [mergedActions copy];
    result[@"panels"] = [mergedPanels copy];
    // Deleting a global action also removes its clipboard references atomically.
    NSMutableSet *liveActionIDs = [NSMutableSet set];
    for (NSDictionary *action in mergedActions) [liveActionIDs addObject:action[@"id"]];
    NSIndexSet *removedBindings = [bindings indexesOfObjectsPassingTest:^BOOL(NSDictionary *binding, NSUInteger idx, BOOL *stop) {
        return [binding[@"source"] isEqual:MTSharedResourceSourceClipboard] &&
            [binding[@"target"][@"kind"] isEqual:MTSharedTargetKindAction] &&
            ![liveActionIDs containsObject:binding[@"target"][@"id"]];
    }];
    [bindings removeObjectsAtIndexes:removedBindings];
    result[@"bindings"] = [bindings copy];
    result[@"groups"] = [groups copy];
    result[@"ungroupedCollapsed"] = @([collapsed containsObject:@""]);
    NSMutableDictionary *migration = [(MTBridgeDictionary(baseDocument[@"migration"]) ?: @{}) mutableCopy];
    migration[@"version"] = @1;
    migration[@"state"] = @"complete";
    migration[@"unresolved"] = [unresolved copy];
    result[@"migration"] = [migration copy];
    return result;
}

#pragma mark - Export (store → legacy)

+ (void)applyStoreSnapshot:(NSDictionary *)snapshot toLegacyPreferences:(NSMutableDictionary *)legacyPrefs {
    // store 不可读（首装未初始化 / IO 失败 / 权限）时保留 legacyPrefs 中的
    // 资源键：写入端在 store 提交失败时会把它们回退写进域与 plist，读侧若无
    // 条件清删，设置端保存的自定义动作会整份消失（保存无效）。store 可用时
    // 仍以它为唯一权威，先清后导。
    if (!MTBridgeDictionary(snapshot)) return;
    for (NSString *key in [self bridgedResourceKeys]) [legacyPrefs removeObjectForKey:key];

    // id → 导出用的稳定 selector / legacyPanelID。
    NSMutableDictionary<NSString *, NSString *> *actionSelectors = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *panelLegacyIDs = [NSMutableDictionary dictionary];
    for (id raw in MTBridgeArray(snapshot[@"actions"])) {
        NSDictionary *action = MTBridgeDictionary(raw);
        NSString *uuid = MTBridgeString(action[@"id"]);
        if (!MTSharedIsValidUUIDString(uuid)) continue;
        NSString *selector = MTBridgeString(MTBridgeDictionary(action[@"legacyRef"])[@"selector"]);
        actionSelectors[uuid] = selector.length ? selector : MTBridgeActionSelectorForUUID(uuid);
    }
    for (id raw in MTBridgeArray(snapshot[@"panels"])) {
        NSDictionary *panel = MTBridgeDictionary(raw);
        NSString *uuid = MTBridgeString(panel[@"id"]);
        if (!MTSharedIsValidUUIDString(uuid)) continue;
        NSString *panelID = MTBridgeString(panel[@"legacyPanelID"]);
        panelLegacyIDs[uuid] = panelID.length ? panelID : MTBridgePanelLegacyIDForUUID(uuid);
    }

    NSString * (^selectorForTarget)(NSDictionary *) = ^NSString *(NSDictionary *target) {
        NSString *kind = MTBridgeString(target[@"kind"]);
        NSString *id = MTBridgeString(target[@"id"]);
        if ([kind isEqual:MTSharedTargetKindAction]) return actionSelectors[id] ?: @"";
        if ([kind isEqual:MTSharedTargetKindPanel]) {
            NSString *panelID = panelLegacyIDs[id];
            return panelID.length ? [MTLegacyPanelSelectorPrefix stringByAppendingString:panelID] : @"";
        }
        if ([kind isEqual:MTSharedTargetKindBuiltin]) return id;
        return @"";
    };

    // 键盘域的 linkactions 顺序 = store 中 keyboard 来源动作的顺序。
    NSMutableArray<NSDictionary *> *linkActions = [NSMutableArray array];
    for (id raw in MTBridgeArray(snapshot[@"actions"])) {
        NSDictionary *action = MTBridgeDictionary(raw);
        NSString *uuid = MTBridgeString(action[@"id"]);
        NSString *selector = actionSelectors[uuid];
        NSDictionary *entry = MTBridgeDictionary(action[@"entry"]);
        if (!selector || !entry) continue;
        NSMutableDictionary *legacy = [entry mutableCopy];
        legacy[@"selector"] = selector;
        [linkActions addObject:[legacy copy]];
    }

    NSMutableArray<NSDictionary *> *panels = [NSMutableArray array];
    for (id raw in MTBridgeArray(snapshot[@"panels"])) {
        NSDictionary *panel = MTBridgeDictionary(raw);
        NSString *uuid = MTBridgeString(panel[@"id"]);
        NSString *panelID = panelLegacyIDs[uuid];
        if (!panelID) continue;
        NSString *kind = MTBridgeString(panel[@"legacyKind"]);
        if (![kind isEqual:MTLegacyPanelKindKeyboard] && ![kind isEqual:MTLegacyPanelKindGesture]) {
            kind = MTLegacyPanelKindGesture;
        }
        NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
        for (id rawItem in MTBridgeArray(panel[@"items"])) {
            NSDictionary *item = MTBridgeDictionary(rawItem);
            if (!item) continue;
            NSString *selector = selectorForTarget(MTBridgeDictionary(item[@"target"]));
            if (!selector.length) continue;
            NSMutableDictionary *legacyItem = [@{ @"selector": selector } mutableCopy];
            NSString *itemID = MTBridgeString(item[@"legacyItemID"]);
            if (!itemID.length) itemID = MTBridgeString(item[@"itemID"]);
            if (itemID.length) legacyItem[@"id"] = itemID;
            if ([item[@"name"] isKindOfClass:NSString.class]) legacyItem[@"name"] = item[@"name"];
            [items addObject:legacyItem];
        }
        [panels addObject:@{
            @"id": panelID,
            @"kind": kind,
            @"name": MTBridgeString(panel[@"name"]),
            @"icon": MTBridgeString(panel[@"icon"]),
            @"items": [items copy],
            @"preferences": [MTBridgeDictionary(panel[@"style"]) ?: @{} copy],
        }];
    }

    NSMutableArray<NSString *> *groupNames = [NSMutableArray array];
    NSMutableArray<NSString *> *collapsedNames = [NSMutableArray array];
    id ungroupedCollapsed = snapshot[@"ungroupedCollapsed"];
    if ([ungroupedCollapsed isKindOfClass:NSNumber.class] && [ungroupedCollapsed boolValue])
        [collapsedNames addObject:@""];
    NSArray *groupRows = [MTBridgeArray(snapshot[@"groups"]) sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        NSNumber *left = [a isKindOfClass:NSDictionary.class] ? a[@"order"] : nil;
        NSNumber *right = [b isKindOfClass:NSDictionary.class] ? b[@"order"] : nil;
        return [@(left ? left.integerValue : 0) compare:@(right ? right.integerValue : 0)];
    }];
    for (id raw in groupRows) {
        NSDictionary *group = MTBridgeDictionary(raw);
        if (!group) continue;
        NSString *name = MTBridgeString(group[@"name"]);
        if (!name.length) continue;
        [groupNames addObject:name];
        if ([group[@"collapsed"] boolValue]) [collapsedNames addObject:name];
    }

    NSMutableDictionary *toolbar = [NSMutableDictionary dictionary];
    NSMutableDictionary *dock = [NSMutableDictionary dictionary];
    NSMutableDictionary *edges = [NSMutableDictionary dictionary];
    NSMutableDictionary *statusBar = [NSMutableDictionary dictionary];
    for (id raw in MTBridgeArray(snapshot[@"bindings"])) {
        NSDictionary *binding = MTBridgeDictionary(raw);
        NSString *bindingID = MTBridgeString(binding[@"id"]);
        if (!bindingID.length) continue;
        NSDictionary *target = MTBridgeDictionary(binding[@"target"]);
        if ([bindingID hasPrefix:@"keyboard.toolbar."] && bindingID.length > @"keyboard.toolbar.".length) {
            toolbar[[bindingID substringFromIndex:@"keyboard.toolbar.".length]] = selectorForTarget(target);
        } else if ([bindingID hasPrefix:@"gesture.dock."] && bindingID.length > @"gesture.dock.".length) {
            dock[[bindingID substringFromIndex:@"gesture.dock.".length]] = selectorForTarget(target);
        } else if ([bindingID hasPrefix:@"gesture.statusbar."] && bindingID.length > @"gesture.statusbar.".length) {
            NSMutableDictionary *legacy = [@{ @"selector": selectorForTarget(target) } mutableCopy];
            for (NSString *key in MTBridgeDictionary(binding[@"options"]).allKeys) legacy[key] = binding[@"options"][key];
            statusBar[[bindingID substringFromIndex:@"gesture.statusbar.".length]] = [legacy copy];
        } else if ([bindingID hasPrefix:@"gesture.screenedge."]) {
            NSString *slot = [bindingID substringFromIndex:@"gesture.screenedge.".length];
            if (![@[@"left", @"right", @"left2", @"right2"] containsObject:slot]) continue;
            NSMutableDictionary *legacy = [MTBridgeDictionary(binding[@"options"]) mutableCopy] ?: [NSMutableDictionary dictionary];
            legacy[@"selector"] = selectorForTarget(target);
            edges[slot] = [legacy copy];
        }
    }

    legacyPrefs[MTLegacyLinkActionsKey] = [linkActions copy];
    legacyPrefs[MTLegacyPanelsKey] = [panels copy];
    legacyPrefs[MTLegacyGroupsKey] = [groupNames copy];
    legacyPrefs[MTLegacyCollapsedGroupsKey] = [collapsedNames copy];
    legacyPrefs[MTLegacyToolbarBindingsKey] = [toolbar copy];
    legacyPrefs[MTLegacyDockBindingsKey] = [dock copy];
    legacyPrefs[MTLegacyStatusBarBindingsKey] = [statusBar copy];
    legacyPrefs[MTLegacyEdgeBindingsKey] = [edges copy];
}

#pragma mark - Apply (legacy write → store commit)

+ (BOOL)applyLegacyPreferences:(NSDictionary *)legacyPreferences error:(NSError **)error {
    NSDictionary *current = [MTSharedResourceStore readSnapshot];
    uint64_t revision = current ? ((NSNumber *)current[@"revision"]).unsignedLongLongValue : 0;
    NSDictionary *next = [self documentByImportingLegacyPreferences:legacyPreferences intoDocument:current];
    NSArray *keys = @[@"actions", @"panels", @"bindings", @"groups"];
    for (NSString *key in keys) {
        if (![next[key] isEqual:current[key]]) {
            return [MTSharedResourceStore commitSnapshot:next expectedRevision:revision error:error];
        }
    }
    if ([next[@"ungroupedCollapsed"] boolValue] != [current[@"ungroupedCollapsed"] boolValue])
        return [MTSharedResourceStore commitSnapshot:next expectedRevision:revision error:error];
    return YES; // 内容未变化：不递增 revision、不重复发布。
}

+ (NSDictionary<NSString *, NSDictionary *> *)knownBindingSlots {
    static NSDictionary *slots = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *registry = [NSMutableDictionary dictionary];
        void (^add)(NSString *, NSString *, NSString *, NSString *) = ^(NSString *bindingID, NSString *legacyKey, NSString *slot, NSString *title) {
            registry[bindingID] = @{ @"legacyKey": legacyKey, @"slot": slot, @"title": title,
                                     @"source": MTSharedResourceSourceKeyboard };
        };
        add(@"keyboard.toolbar.top.left", MTLegacyToolbarBindingsKey, @"top.left", @"键盘 · 顶部工具栏左滑");
        add(@"keyboard.toolbar.top.right", MTLegacyToolbarBindingsKey, @"top.right", @"键盘 · 顶部工具栏右滑");
        add(@"keyboard.toolbar.bottom.left", MTLegacyToolbarBindingsKey, @"bottom.left", @"键盘 · 底部工具栏左滑");
        add(@"keyboard.toolbar.bottom.right", MTLegacyToolbarBindingsKey, @"bottom.right", @"键盘 · 底部工具栏右滑");
        void (^addGesture)(NSString *, NSString *, NSString *, NSString *) = ^(NSString *bindingID, NSString *legacyKey, NSString *slot, NSString *title) {
            registry[bindingID] = @{ @"legacyKey": legacyKey, @"slot": slot, @"title": title,
                                     @"source": MTSharedResourceSourceGesture };
        };
        addGesture(@"gesture.dock.up", MTLegacyDockBindingsKey, @"up", @"全局 · Dock 上滑");
        addGesture(@"gesture.dock.left", MTLegacyDockBindingsKey, @"left", @"全局 · Dock 左滑");
        addGesture(@"gesture.dock.right", MTLegacyDockBindingsKey, @"right", @"全局 · Dock 右滑");
        addGesture(@"gesture.screenedge.left", MTLegacyEdgeBindingsKey, @"left", @"全局 · 从左侧滑入");
        addGesture(@"gesture.screenedge.right", MTLegacyEdgeBindingsKey, @"right", @"全局 · 从右侧滑入");
        addGesture(@"gesture.screenedge.left2", MTLegacyEdgeBindingsKey, @"left2", @"全局 · 双指从左侧滑入");
        addGesture(@"gesture.screenedge.right2", MTLegacyEdgeBindingsKey, @"right2", @"全局 · 双指从右侧滑入");
        slots = [registry copy];
    });
    return slots;
}

@end
