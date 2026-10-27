#import "MTContextGroupEngine.h"
#import "MTContextGroupTypes.h"
#import "MTContextClassifier.h"

extern NSBundle *tweakBundle;

// 标题走键盘本地化包；缺键时回落到内置文案，避免底栏出现空按钮。
static NSString *MTContextLocalized(NSString *key, NSString *fallback) {
    NSBundle *bundle = tweakBundle ?: [NSBundle bundleWithIdentifier:@"com.lindo.metis.prefs.keyboard"];
    NSString *value = [bundle localizedStringForKey:key value:@"" table:nil];
    return value.length ? value : fallback;
}

static BOOL MTContextHasWhitespace(NSString *text) {
    static NSCharacterSet *whitespace;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet]; });
    return [text rangeOfCharacterFromSet:whitespace].location != NSNotFound;
}

static BOOL MTContextIsHostSafe(NSString *token) {
    if (!token.length || token.length > 63) return NO;
    for (NSUInteger index = 0; index < token.length; index++) {
        unichar c = [token characterAtIndex:index];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-')) return NO;
    }
    // 末段必须含字母：排除 3.14 这类纯数字被当成域名。
    for (NSUInteger index = 0; index < token.length; index++) {
        unichar c = [token characterAtIndex:index];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) return YES;
    }
    return NO;
}

NSURL *MTContextURLForText(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return nil;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 4 || trimmed.length > 2048 || MTContextHasWhitespace(trimmed)) return nil;

    NSURL *url = [NSURL URLWithString:trimmed];
    NSString *scheme = url.scheme.lowercaseString;
    if (url.host.length && ([scheme isEqual:@"http"] || [scheme isEqual:@"https"])) return url;
    NSURLComponents *components = [NSURLComponents componentsWithString:[@"https://" stringByAppendingString:trimmed]];
    NSString *host = components.host;
    if (!host.length || components.user.length || components.password.length) return nil;
    if ([host rangeOfString:@"^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$" options:NSRegularExpressionSearch].location != NSNotFound) {
        for (NSString *part in [host componentsSeparatedByString:@"."]) if (part.integerValue > 255) return nil;
        return components.URL;
    }
    NSArray *parts = [host componentsSeparatedByString:@"."];
    if (parts.count < 2 || parts.count > 8 || !MTContextIsHostSafe(parts.lastObject)) return nil;
    for (NSString *part in parts) if (!part.length || [part hasPrefix:@"-"] || [part hasSuffix:@"-"] || [part rangeOfString:@"^[A-Za-z0-9-]+$" options:NSRegularExpressionSearch].location == NSNotFound) return nil;
    return components.URL;
}

BOOL MTContextTextLooksLikePhone(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 5 || trimmed.length > 24) return NO;
    NSUInteger digits = 0;
    for (NSUInteger index = 0; index < trimmed.length; index++) {
        unichar c = [trimmed characterAtIndex:index];
        if (c >= '0' && c <= '9') { digits++; continue; }
        if (c == '+' || c == '-' || c == ' ' || c == '(' || c == ')' || c == 0x00A0) continue;
        return NO;
    }
    return digits >= 5;
}

BOOL MTContextTextLooksLikeCode(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length < 8) return NO;
    BOOL hasBrace = [text containsString:@"{"] && [text containsString:@"}"];
    if (hasBrace) return YES;
    return [text containsString:@";"] && [text containsString:@"="];
}

static NSString *MTContextSearchURLString(NSString *text) {
    // 中文环境用百度、其余用 Bing：搜索是「选中即走」的动作，不该再让用户选引擎。
    NSString *language = [NSLocale.preferredLanguages.firstObject lowercaseString] ?: @"";
    NSString *base = [language hasPrefix:@"zh"] ? @"https://www.baidu.com/s?wd=" : @"https://www.bing.com/search?q=";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *escaped = [text stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
    return [base stringByAppendingString:escaped];
}

// slots 由调用方给出：普通判定用「本组自己的格数」，应用组预留期间用「剩余格数」——
// 后者是共享池，绑定格布局下补位组不会因为自己只有一格而补不满。
static BOOL MTContextGroupActiveWithSlots(MTContextSnapshot *s, MTContextGroupConfig *config,
                                          MTContextGroupSettings *settings, MTContextGroup group, NSUInteger slots) {
    if (!s || s.secureInput || !settings.enabled || !slots) return NO;
    // App bindings depend on the host, including custom editors with no readable UITextInput.
    if (group == MTContextGroupApp) {
        id appSwitch = config.preferences[kContextAppGroupKey];
        if ([appSwitch isKindOfClass:NSNumber.class] && ![appSwitch boolValue]) return NO;
        MTContextAppGroup *app = [MTContextAppGroup groupForBundleID:s.hostBundleID inGroups:config.appGroups];
        return app.enabled && app.actions.count > 0;
    }
    if (!s.inputAvailable) return NO;
    switch (group) {
        case MTContextGroupDelete: return ![config.preferences[kContextDeleteGroupKey] isEqual:@NO] && s.deletedLength > 0 && s.deleteAge >= 0.3 && s.deleteAge < 3 && s.canUndo;
        case MTContextGroupSelection: return settings.selectionEnabled && s.selectionLength > 0;
        case MTContextGroupCopy: return settings.clipboardEnabled && s.clipboardAvailable && s.clipboardAge >= 0 && s.clipboardAge < settings.clipboardFreshness;
        case MTContextGroupPaste: return settings.pasteEnabled && s.pastedLength >= settings.pasteMinLength && s.pasteAge >= 0 && s.pasteAge < settings.pasteFreshness;
        case MTContextGroupTyping: return settings.inputEnabled && s.inputLength > 0;
        case MTContextGroupIdle: return settings.idleEnabled && s.inputLength == 0;
        default: return NO;
    }
}

BOOL MTContextGroupIsActive(MTContextSnapshot *s, MTContextGroupConfig *config, MTContextGroup group) {
    MTContextGroupSettings *settings = [MTContextGroupSettings settingsFromPreferences:config.preferences];
    // 应用组的格位按「全部上下文格」算，命中时可覆盖绑定格；其余组只看自己的格位。
    NSUInteger slots = group == MTContextGroupApp ? [config contextSlotCount] : [config slotsForGroup:MTContextGroupKey(group)];
    return MTContextGroupActiveWithSlots(s, config, settings, group, slots);
}

// 选择器 → 可执行动作。URL/AI 这类需要文本的动作在缺文本时留空占位，保证后续
// 槽位不前移（不拿第 N+1 个动作补第 N 格）。
static MTContextAction *MTContextActionForSelector(NSString *selector, NSString *text) {
    if (![selector isKindOfClass:NSString.class] || !selector.length) return nil;
    if ([selector isEqual:@"url:open"]) {
        NSURL *url = MTContextURLForText(text);
        if (!url) return nil;
        return [MTContextAction actionWithIdentifier:selector title:MTContextLocalized(@"CONTEXT_GROUP_OPEN_LINK", @"打开链接")
                                             symbol:@"link" payloadKind:MTContextPayloadURL payload:url.absoluteString];
    }
    if ([selector isEqual:@"url:search"]) {
        if (!text.length) return nil;
        return [MTContextAction actionWithIdentifier:selector title:MTContextLocalized(@"CONTEXT_GROUP_SEARCH", @"搜索")
                                             symbol:@"magnifyingglass" payloadKind:MTContextPayloadURL payload:MTContextSearchURLString(text)];
    }
    if ([selector isEqual:@"ai:seed"]) {
        if (!text.length) return nil;
        return [MTContextAction actionWithIdentifier:selector title:MTContextLocalized(@"CONTEXT_GROUP_ASK_AI", @"问 AI")
                                             symbol:@"sparkles" payloadKind:MTContextPayloadAISeed payload:text];
    }
    return [MTContextAction actionWithIdentifier:[@"configured:" stringByAppendingString:selector] title:selector
                                         symbol:@"bolt" payloadKind:MTContextPayloadSelector payload:selector];
}

// 切片发生在前、解析发生在后：第 N 格失败不能由第 N+1 个动作顶上。
static NSArray<MTContextAction *> *MTContextActionsForSelectors(NSArray *selectors, NSString *text,
                                                               NSUInteger slots, BOOL *usable) {
    NSMutableArray *actions = [NSMutableArray array];
    BOOL any = NO;
    for (NSUInteger index = 0; index < MIN(slots, selectors.count); index++) {
        MTContextAction *action = MTContextActionForSelector(selectors[index], text);
        if (action) any = YES;
        else action = [MTContextAction actionWithIdentifier:[NSString stringWithFormat:@"unavailable:%lu", (unsigned long)index]
                                                      title:@"" symbol:@"" payloadKind:MTContextPayloadUnavailable payload:@""];
        [actions addObject:action];
    }
    if (usable) *usable = any;
    return actions;
}

@implementation MTContextGroupEngine
+ (MTContextDecision *)decisionForSnapshot:(MTContextSnapshot *)snapshot settings:(MTContextGroupSettings *)settings {
    // Compatibility for callers compiled against v1; production passes the full config.
    NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
    prefs[kContextGroupsEnabledKey] = @(settings.enabled);
    prefs[kContextSelectionGroupKey] = @(settings.selectionEnabled);
    prefs[kContextClipboardGroupKey] = @(settings.clipboardEnabled);
    prefs[kContextPasteGroupKey] = @(settings.pasteEnabled);
    prefs[kContextInputGroupKey] = @(settings.inputEnabled);
    prefs[kContextIdleGroupKey] = @(settings.idleEnabled);
    prefs[kContextActionsKey] = settings.configuredActions ?: @{};
    prefs[kContextClipboardFreshnessKey] = @(settings.clipboardFreshness);
    prefs[kContextPasteFreshnessKey] = @(settings.pasteFreshness);
    prefs[kContextPasteMinLengthKey] = @(settings.pasteMinLength);
    return [self decisionForSnapshot:snapshot config:[MTContextGroupConfig configFromPreferences:prefs]];
}
+ (MTContextDecision *)decisionForSnapshot:(MTContextSnapshot *)snapshot config:(MTContextGroupConfig *)config {
    MTContextGroupSettings *settings = [MTContextGroupSettings settingsFromPreferences:config.preferences];
    if (!snapshot || !settings.enabled || snapshot.secureInput)
        return [MTContextDecision decisionWithGroup:MTContextGroupDefault reason:@"inactive" actions:@[] ttl:0];
    NSTimeInterval ttl = 0;
    BOOL copy = settings.clipboardEnabled && snapshot.clipboardAvailable && snapshot.clipboardAge >= 0 && snapshot.clipboardAge < settings.clipboardFreshness;
    BOOL paste = settings.pasteEnabled && snapshot.pastedLength >= settings.pasteMinLength && snapshot.pasteAge >= 0 && snapshot.pasteAge < settings.pasteFreshness;
    BOOL deletion = ![config.preferences[kContextDeleteGroupKey] isEqual:@NO] && snapshot.deletedLength > 0 && snapshot.deleteAge >= 0.3 && snapshot.deleteAge < 3 && snapshot.canUndo;
    if (copy) ttl = settings.clipboardFreshness - snapshot.clipboardAge;
    if (paste) ttl = ttl > 0 ? MIN(ttl, settings.pasteFreshness - snapshot.pasteAge) : settings.pasteFreshness - snapshot.pasteAge;
    if (deletion) ttl = ttl > 0 ? MIN(ttl, 3 - snapshot.deleteAge) : 3 - snapshot.deleteAge;
    // 应用动作组最高优先：命中宿主即占据预留区前 N 格（N = 组内动作数，上限为槽位数），
    // 其余格子仍由后续组按优先级补齐；其他组再活跃也不能把已配置的应用按钮挤掉。
    // 预留区按「全部上下文格」计算：格子绑定到具体组时同样让位给应用动作，
    // 未命中宿主时绑定语义保持原样（渲染端只在应用组获胜时放宽格数）。
    NSMutableArray *combined = [NSMutableArray array];
    NSString *appReason = nil;
    NSUInteger appSlots = [config contextSlotCount];
    if (snapshot.hostBundleID.length && appSlots) {
        id appSwitch = config.preferences[kContextAppGroupKey];
        if (![appSwitch isKindOfClass:NSNumber.class] || [appSwitch boolValue]) {
            MTContextAppGroup *match = [MTContextAppGroup groupForBundleID:snapshot.hostBundleID inGroups:config.appGroups];
            if (match.enabled && match.actions.count) {
                BOOL appUsable = NO;
                NSArray *appActions = MTContextActionsForSelectors(match.actions, snapshot.inputAvailable ? snapshot.inputText : nil,
                                                                   MIN(appSlots, (NSUInteger)match.actions.count), &appUsable);
                if (appUsable) {
                    [combined addObjectsFromArray:appActions];
                    appReason = [NSString stringWithFormat:@"app-%@", snapshot.hostBundleID];
                }
            }
        }
    }
    // 预留之后剩下的格数：只在应用组命中时收紧，未命中保持各组的原槽位数（兼容旧语义）。
    NSUInteger reserved = combined.count;
    NSUInteger remaining = reserved ? appSlots - reserved : 0;

    // Missing input must only disable text-dependent groups, never configured App buttons.
    // Do not consume clipboard/selection signals or run text rules without an input session.
    if (!snapshot.inputAvailable) {
        return reserved
            ? [MTContextDecision decisionWithGroup:MTContextGroupApp reason:appReason actions:combined ttl:0]
            : [MTContextDecision decisionWithGroup:MTContextGroupDefault reason:@"no-input" actions:@[] ttl:0];
    }

    for (NSNumber *number in MTContextPriority(config.preferences)) {
        MTContextGroup group = number.integerValue;
        NSString *key = MTContextGroupKey(group);
        if (group == MTContextGroupApp) continue; // 已在上方预留，不再参与竞争。
        // 应用组已预留时，剩余格是一个共享池：活跃判断与补位上限都用剩余格数，
        // 这样绑定格布局下补位组也能把剩余格补满；未预留时保持各组原槽位数。
        NSUInteger slots = reserved ? remaining : [config slotsForGroup:key];
        BOOL active = reserved ? MTContextGroupActiveWithSlots(snapshot, config, settings, group, slots)
                               : MTContextGroupIsActive(snapshot, config, group);
        if (!active || !slots) continue;
        if (group == MTContextGroupIdle) {
            // Idle 组不产动作：应用组已预留时返回应用决策（剩余格维持占位），否则按原样兜底。
            return reserved
                ? [MTContextDecision decisionWithGroup:MTContextGroupApp reason:appReason actions:combined ttl:ttl]
                : [MTContextDecision decisionWithGroup:group reason:@"idle-apps" actions:@[] ttl:ttl];
        }
        NSString *text = group == MTContextGroupSelection ? snapshot.selectionText : (group == MTContextGroupCopy ? snapshot.clipboardText : (group == MTContextGroupPaste ? snapshot.pastedText : snapshot.inputText));
        NSDictionary *classification = snapshot.classification[key];
        NSArray *builtin = classification[@"builtin"] ?: MTContextBuiltinMatches(text, snapshot.hasImage && (group == MTContextGroupCopy || group == MTContextGroupPaste));
        NSArray *js = classification[@"js"] ?: @[];
        MTContextType *chosen = nil, *fallback = nil;
        for (MTContextType *type in [config typesForGroup:key]) {
            if (!type.enabled || !type.actions.count) continue;
            if ([type.kind isEqual:@"builtin"] && ([type.identifier isEqual:@"fallback"] || ([type.identifier isEqual:@"text"] && !text.length))) { if (!fallback) fallback = type; continue; }
            BOOL match = [type.kind isEqual:@"js"] ? [js containsObject:type.identifier] : [builtin containsObject:type.identifier];
            if (match) { chosen = type; break; }
        }
        chosen = chosen ?: fallback;
        if (!chosen) continue;
        BOOL usable = NO;
        NSArray *actions = MTContextActionsForSelectors(chosen.actions, text, slots, &usable);
        if (!usable) continue;
        if (reserved) {
            [combined addObjectsFromArray:actions];
            return [MTContextDecision decisionWithGroup:MTContextGroupApp
                                                reason:[NSString stringWithFormat:@"%@+%@-%@", appReason, key, chosen.identifier]
                                               actions:combined ttl:ttl];
        }
        NSString *reason = [NSString stringWithFormat:@"%@-%@%@", key, chosen.identifier, [classification[@"pending"] boolValue] ? @"-pending" : @""];
        return [MTContextDecision decisionWithGroup:group reason:reason actions:actions ttl:ttl];
    }
    if (reserved) return [MTContextDecision decisionWithGroup:MTContextGroupApp reason:appReason actions:combined ttl:ttl];
    return [MTContextDecision decisionWithGroup:MTContextGroupDefault reason:@"no-signal" actions:@[] ttl:ttl];
}
@end
