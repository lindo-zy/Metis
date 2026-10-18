#import "MTSharedResourceValidator.h"
#import "MTSharedResourceIDs.h"

NSString *const MTSharedResourceValidationErrorDomain = @"com.lindo.metis.shared-resources.validator";

// 容量上限：拒绝超大或非法结构（03 §4），避免一个坏快照拖垮运行端。
static NSUInteger const MTSharedLimitActions = 2000;
static NSUInteger const MTSharedLimitPanels = 500;
static NSUInteger const MTSharedLimitPanelItems = 200;
static NSUInteger const MTSharedLimitBindings = 200;
static NSUInteger const MTSharedLimitGroups = 200;
static NSUInteger const MTSharedLimitNestingDepth = 8;

static NSError *MTValidatorError(MTSharedResourceValidationCode code, NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    return [NSError errorWithDomain:MTSharedResourceValidationErrorDomain code:code
                            userInfo:@{NSLocalizedDescriptionKey : message ?: @"invalid shared resource document"}];
}

static NSString *MTVString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSArray *MTVArray(id value) {
    return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSDictionary *MTVDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

// DFS 染色：0=未访问，1=在栈（回边即环），2=完成。
static BOOL MTValidatorVisit(NSString *identifier,
                             NSDictionary<NSString *, NSSet<NSString *> *> *graph,
                             NSMutableDictionary<NSString *, NSNumber *> *state) {
    NSInteger mark = [state[identifier] integerValue];
    if (mark == 2) return YES;
    if (mark == 1) return NO; // back edge → cycle
    state[identifier] = @1;
    for (NSString *next in graph[identifier]) {
        if (!MTValidatorVisit(next, graph, state)) return NO;
    }
    state[identifier] = @2;
    return YES;
}

@implementation MTSharedResourceValidator

+ (NSError *)validateDocument:(NSDictionary *)document {
    if (!MTVDictionary(document)) return MTValidatorError(MTSharedResourceValidationNotDictionary, @"document is not a dictionary");
    if (![MTVString(document[@"format"]) isEqual:MTSharedResourceFormat])
        return MTValidatorError(MTSharedResourceValidationFormat, @"unexpected format");
    NSNumber *schema = [document[@"schemaVersion"] isKindOfClass:NSNumber.class] ? document[@"schemaVersion"] : nil;
    if (!schema) return MTValidatorError(MTSharedResourceValidationShape, @"missing schemaVersion");
    if (schema.unsignedIntegerValue > MTSharedResourceCurrentSchemaVersion.unsignedIntegerValue)
        return MTValidatorError(MTSharedResourceValidationSchemaFuture, @"future schema %@ is read-only", schema);
    return [self validatePayloadOfDocument:document];
}

+ (NSError *)validatePayloadOfDocument:(NSDictionary *)document {
    if (!MTVDictionary(document)) return MTValidatorError(MTSharedResourceValidationNotDictionary, @"document is not a dictionary");

    NSArray *actions = MTVArray(document[@"actions"]);
    NSArray *panels = MTVArray(document[@"panels"]);
    NSArray *bindings = MTVArray(document[@"bindings"]);
    NSArray *groups = MTVArray(document[@"groups"]);
    if (!actions || !panels || !bindings || !groups)
        return MTValidatorError(MTSharedResourceValidationShape, @"actions/panels/bindings/groups must be arrays");
    if (actions.count > MTSharedLimitActions || panels.count > MTSharedLimitPanels ||
        bindings.count > MTSharedLimitBindings || groups.count > MTSharedLimitGroups)
        return MTValidatorError(MTSharedResourceValidationLimit, @"resource count exceeds limit");

    NSMutableSet<NSString *> *actionIDs = [NSMutableSet set];
    for (id item in actions) {
        NSDictionary *action = MTVDictionary(item);
        NSString *identifier = MTVString(action[@"id"]);
        if (!action) return MTValidatorError(MTSharedResourceValidationActionEntry, @"action entry is not a dictionary");
        if (!identifier.length || !MTSharedIsValidUUIDString(identifier))
            return MTValidatorError(MTSharedResourceValidationInvalidID, @"action id is not a UUID");
        if (![actionIDs containsObject:identifier]) {
            [actionIDs addObject:identifier];
        } else {
            return MTValidatorError(MTSharedResourceValidationDuplicateID, @"duplicate action id %@", identifier);
        }
        if (!MTVDictionary(action[@"entry"]))
            return MTValidatorError(MTSharedResourceValidationActionEntry, @"action %@ lacks entry dictionary", identifier);
        NSString *type = MTVString(action[@"entry"][@"type"]);
        // 存量「无 type」记录合法（legacy url/无类型语义保留）。
        if (type.length && ![MTSharedResourceAllowedActionTypes() containsObject:type])
            return MTValidatorError(MTSharedResourceValidationActionEntry, @"action %@ has unknown type %@", identifier, type);
    }

    NSMutableSet<NSString *> *panelIDs = [NSMutableSet set];
    // 面板引用图：panel id → 直接引用的 panel id 集合（用于环与深度检查）。
    NSMutableDictionary<NSString *, NSSet<NSString *> *> *panelGraph = [NSMutableDictionary dictionary];
    for (id item in panels) {
        NSDictionary *panel = MTVDictionary(item);
        if (!panel) return MTValidatorError(MTSharedResourceValidationPanelShape, @"panel entry is not a dictionary");
        NSString *identifier = MTVString(panel[@"id"]);
        if (!identifier.length || !MTSharedIsValidUUIDString(identifier))
            return MTValidatorError(MTSharedResourceValidationInvalidID, @"panel id is not a UUID");
        if (![panelIDs containsObject:identifier]) {
            [panelIDs addObject:identifier];
        } else {
            return MTValidatorError(MTSharedResourceValidationDuplicateID, @"duplicate panel id %@", identifier);
        }
        if (!MTVString(panel[@"name"]).length)
            return MTValidatorError(MTSharedResourceValidationPanelShape, @"panel %@ lacks name", identifier);
        NSArray *items = MTVArray(panel[@"items"]);
        if (!items) return MTValidatorError(MTSharedResourceValidationPanelShape, @"panel %@ items is not an array", identifier);
        if (items.count > MTSharedLimitPanelItems)
            return MTValidatorError(MTSharedResourceValidationLimit, @"panel %@ exceeds item limit", identifier);
        NSMutableSet<NSString *> *referenced = [NSMutableSet set];
        NSMutableSet<NSString *> *itemIDs = [NSMutableSet set];
        for (id rawItem in items) {
            NSDictionary *entry = MTVDictionary(rawItem);
            if (!entry) return MTValidatorError(MTSharedResourceValidationPanelShape, @"panel %@ has malformed item", identifier);
            NSString *itemID = MTVString(entry[@"itemID"]);
            if (!itemID.length || !MTSharedIsValidUUIDString(itemID))
                return MTValidatorError(MTSharedResourceValidationInvalidID, @"panel %@ item id is not a UUID", identifier);
            if ([itemIDs containsObject:itemID]) return MTValidatorError(MTSharedResourceValidationDuplicateID, @"duplicate item id in panel %@", identifier);
            [itemIDs addObject:itemID];
            NSDictionary *target = MTVDictionary(entry[@"target"]);
            NSString *kind = MTVString(target[@"kind"]);
            NSString *targetID = MTVString(target[@"id"]);
            if ([kind isEqual:MTSharedTargetKindAction]) {
                if (![actionIDs containsObject:targetID])
                    return MTValidatorError(MTSharedResourceValidationTargetUnresolved, @"panel %@ references missing action %@", identifier, targetID);
            } else if ([kind isEqual:MTSharedTargetKindPanel]) {
                // 面板间允许前向引用：先记录，全部收齐后统一校验。
                [referenced addObject:targetID];
            } else if ([kind isEqual:MTSharedTargetKindBuiltin]) {
                if (!targetID.length) return MTValidatorError(MTSharedResourceValidationTargetUnresolved, @"panel %@ builtin item lacks id", identifier);
            } else {
                return MTValidatorError(MTSharedResourceValidationTargetUnresolved, @"panel %@ item has unknown target kind '%@'", identifier, kind);
            }
        }
        panelGraph[identifier] = referenced;
    }
    // 面板引用必须整体成图后再查（前向引用合法）。
    for (NSString *identifier in panelGraph.allKeys)
        for (NSString *referenced in panelGraph[identifier])
            if (![panelIDs containsObject:referenced])
                return MTValidatorError(MTSharedResourceValidationTargetUnresolved, @"panel %@ references missing panel %@", identifier, referenced);

    // 环与深度：DFS 染色。
    NSMutableDictionary<NSString *, NSNumber *> *state = [NSMutableDictionary dictionary];
    for (NSString *identifier in panelIDs) state[identifier] = @0;
    for (NSString *identifier in panelIDs)
        if (!MTValidatorVisit(identifier, panelGraph, state))
            return MTValidatorError(MTSharedResourceValidationCycle, @"panel reference cycle at %@", identifier);
    // 深度：迭代式最长引用链（避免递归 block）。
    NSMutableDictionary<NSString *, NSNumber *> *depth = [NSMutableDictionary dictionary];
    for (NSString *identifier in panelIDs) depth[identifier] = @1;
    BOOL changed = YES;
    while (changed) {
        changed = NO;
        for (NSString *identifier in panelIDs) {
            NSInteger best = [depth[identifier] integerValue];
            for (NSString *next in panelGraph[identifier]) {
                best = MAX(best, [depth[next] integerValue] + 1);
            }
            if (best > [depth[identifier] integerValue]) {
                depth[identifier] = @(best);
                changed = YES;
            }
        }
    }
    for (NSString *identifier in panelIDs) {
        NSInteger chain = [depth[identifier] integerValue];
        if (chain > (NSInteger)MTSharedLimitNestingDepth)
            return MTValidatorError(MTSharedResourceValidationNestingTooDeep, @"panel nesting exceeds %lu at %@", (unsigned long)MTSharedLimitNestingDepth, identifier);
    }

    NSArray *sources = @[MTSharedResourceSourceKeyboard, MTSharedResourceSourceGesture,
                         MTSharedResourceSourceClipboard, MTSharedResourceSourceCapture, MTSharedResourceSourceOther];
    NSMutableSet<NSString *> *bindingIDs = [NSMutableSet set];
    for (id item in bindings) {
        NSDictionary *binding = MTVDictionary(item);
        if (!binding) return MTValidatorError(MTSharedResourceValidationBindingShape, @"binding entry is not a dictionary");
        NSString *identifier = MTVString(binding[@"id"]);
        if (!identifier.length || identifier.length > 128) return MTValidatorError(MTSharedResourceValidationBindingShape, @"binding id invalid");
        if ([bindingIDs containsObject:identifier]) return MTValidatorError(MTSharedResourceValidationDuplicateID, @"duplicate binding id %@", identifier);
        [bindingIDs addObject:identifier];
        if (![sources containsObject:MTVString(binding[@"source"])])
            return MTValidatorError(MTSharedResourceValidationBindingShape, @"binding %@ has unknown source", identifier);
        NSDictionary *target = MTVDictionary(binding[@"target"]);
        NSString *kind = MTVString(target[@"kind"]);
        NSString *targetID = MTVString(target[@"id"]);
        if ([kind isEqual:MTSharedTargetKindAction]) {
            if (![actionIDs containsObject:targetID])
                return MTValidatorError(MTSharedResourceValidationTargetUnresolved, @"binding %@ references missing action %@", identifier, targetID);
        } else if ([kind isEqual:MTSharedTargetKindPanel]) {
            if (![panelIDs containsObject:targetID])
                return MTValidatorError(MTSharedResourceValidationTargetUnresolved, @"binding %@ references missing panel %@", identifier, targetID);
        } else if (![kind isEqual:MTSharedTargetKindBuiltin] && ![kind isEqual:MTSharedTargetKindNone]) {
            return MTValidatorError(MTSharedResourceValidationTargetUnresolved, @"binding %@ has unknown target kind", identifier);
        }
    }

    // 可选 UI 状态；旧快照缺省为展开，不能作为一个有名称的分组导入。
    if (document[@"ungroupedCollapsed"] && ![document[@"ungroupedCollapsed"] isKindOfClass:NSNumber.class])
        return MTValidatorError(MTSharedResourceValidationShape, @"ungroupedCollapsed must be a boolean");
    NSMutableSet<NSString *> *groupNames = [NSMutableSet set];
    for (id item in groups) {
        NSDictionary *group = MTVDictionary(item);
        if (!group) return MTValidatorError(MTSharedResourceValidationShape, @"group entry is not a dictionary");
        NSString *name = MTVString(group[@"name"]);
        if (!name.length) return MTValidatorError(MTSharedResourceValidationShape, @"group lacks name");
        if ([groupNames containsObject:name]) return MTValidatorError(MTSharedResourceValidationDuplicateID, @"duplicate group %@", name);
        [groupNames addObject:name];
    }
    return nil;
}

@end
