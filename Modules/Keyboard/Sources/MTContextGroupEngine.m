#import "MTContextGroupEngine.h"
#import "MTContextGroupTypes.h"

extern NSBundle *tweakBundle;

// 标题走键盘本地化包；缺键时回落到内置文案，避免底栏出现空按钮。
static NSString *MTContextLocalized(NSString *key, NSString *fallback) {
    NSString *value = tweakBundle ? [tweakBundle localizedStringForKey:key value:@"" table:nil] : nil;
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
    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@"."];
    if (parts.count < 2 || parts.count > 8) return nil;
    for (NSString *part in parts) if (!part.length) return nil;
    if (!MTContextIsHostSafe(parts.lastObject)) return nil;
    if (!MTContextIsHostSafe(parts.firstObject)) return nil;
    return [NSURL URLWithString:[@"https://" stringByAppendingString:trimmed]];
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

@implementation MTContextGroupEngine

+ (MTContextDecision *)defaultDecision {
    return [MTContextDecision decisionWithGroup:MTContextGroupDefault reason:@"no-signal" actions:@[] ttl:0];
}

#pragma mark - G1 选区

+ (MTContextDecision *)selectionDecision:(MTContextSnapshot *)snapshot {
    NSString *text = snapshot.selectionText;
    // 选区长度已知但文本取不到（自定义 inputView / 安全输入）：不猜内容，只给通用动作。
    if (!text.length) {
        return [MTContextDecision decisionWithGroup:MTContextGroupSelection reason:@"selection"
            actions:@[[MTContextAction actionWithIdentifier:@"selector:copyAction:"
                title:MTContextLocalized(@"CONTEXT_GROUP_COPY", @"复制")
                symbol:@"doc.on.doc" payloadKind:MTContextPayloadSelector payload:@"copyAction:"]]
            ttl:0];
    }
    NSURL *url = MTContextURLForText(text);
    if (url) {
        return [MTContextDecision decisionWithGroup:MTContextGroupSelection reason:@"selection-url"
            actions:@[[MTContextAction actionWithIdentifier:@"url:open"
                          title:MTContextLocalized(@"CONTEXT_GROUP_OPEN_LINK", @"打开链接")
                         symbol:@"link" payloadKind:MTContextPayloadURL payload:url.absoluteString],
                      [MTContextAction actionWithIdentifier:@"url:search"
                          title:MTContextLocalized(@"CONTEXT_GROUP_SEARCH", @"搜索")
                         symbol:@"magnifyingglass" payloadKind:MTContextPayloadURL
                          payload:MTContextSearchURLString(text)],
                      [MTContextAction actionWithIdentifier:@"ai:selection"
                          title:MTContextLocalized(@"CONTEXT_GROUP_ASK_AI", @"问 AI")
                         symbol:@"sparkles" payloadKind:MTContextPayloadAISeed payload:text]]
            ttl:0];
    }
    if (MTContextTextLooksLikePhone(text)) {
        NSString *digits = [[text componentsSeparatedByCharactersInSet:
            [[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
        if (digits.length >= 5) {
            return [MTContextDecision decisionWithGroup:MTContextGroupSelection reason:@"selection-phone"
                actions:@[[MTContextAction actionWithIdentifier:@"url:tel"
                              title:MTContextLocalized(@"CONTEXT_GROUP_CALL", @"拨打")
                             symbol:@"phone.fill" payloadKind:MTContextPayloadURL
                              payload:[@"tel://" stringByAppendingString:digits]],
                          [MTContextAction actionWithIdentifier:@"selector:copyAction:"
                              title:MTContextLocalized(@"CONTEXT_GROUP_COPY", @"复制")
                             symbol:@"doc.on.doc" payloadKind:MTContextPayloadSelector payload:@"copyAction:"],
                          [MTContextAction actionWithIdentifier:@"ai:selection"
                              title:MTContextLocalized(@"CONTEXT_GROUP_ASK_AI", @"问 AI")
                             symbol:@"sparkles" payloadKind:MTContextPayloadAISeed payload:text]]
                ttl:0];
        }
    }
    return [MTContextDecision decisionWithGroup:MTContextGroupSelection reason:@"selection-text"
        actions:@[[MTContextAction actionWithIdentifier:@"url:search"
                      title:MTContextLocalized(@"CONTEXT_GROUP_SEARCH", @"搜索")
                     symbol:@"magnifyingglass" payloadKind:MTContextPayloadURL
                      payload:MTContextSearchURLString(text)],
                  [MTContextAction actionWithIdentifier:@"selector:copyAction:"
                      title:MTContextLocalized(@"CONTEXT_GROUP_COPY", @"复制")
                     symbol:@"doc.on.doc" payloadKind:MTContextPayloadSelector payload:@"copyAction:"],
                  [MTContextAction actionWithIdentifier:@"ai:selection"
                      title:MTContextLocalized(@"CONTEXT_GROUP_ASK_AI", @"问 AI")
                     symbol:@"sparkles" payloadKind:MTContextPayloadAISeed payload:text]]
        ttl:0];
}

#pragma mark - G2 剪贴板

+ (MTContextDecision *)clipboardDecision:(MTContextSnapshot *)snapshot settings:(MTContextGroupSettings *)settings {
    NSTimeInterval ttl = settings.clipboardFreshness - snapshot.clipboardAge;
    NSString *text = snapshot.clipboardText;
    MTContextAction *paste = [MTContextAction actionWithIdentifier:@"selector:pasteAction:"
        title:MTContextLocalized(@"CONTEXT_GROUP_PASTE", @"粘贴")
        symbol:@"doc.on.clipboard" payloadKind:MTContextPayloadSelector payload:@"pasteAction:"];
    if (!text.length) {
        // 剪贴板在别的进程被写入：内容未知，只给粘贴，绝不为此去读剪贴板（会触发系统粘贴横幅）。
        return [MTContextDecision decisionWithGroup:MTContextGroupClipboard reason:@"clipboard-external"
            actions:@[paste] ttl:ttl];
    }
    NSURL *url = MTContextURLForText(text);
    if (url) {
        return [MTContextDecision decisionWithGroup:MTContextGroupClipboard reason:@"clipboard-url"
            actions:@[[MTContextAction actionWithIdentifier:@"url:open"
                          title:MTContextLocalized(@"CONTEXT_GROUP_OPEN_LINK", @"打开链接")
                         symbol:@"link" payloadKind:MTContextPayloadURL payload:url.absoluteString],
                      paste,
                      [MTContextAction actionWithIdentifier:@"ai:clipboard"
                          title:MTContextLocalized(@"CONTEXT_GROUP_ASK_AI", @"问 AI")
                         symbol:@"sparkles" payloadKind:MTContextPayloadAISeed payload:text]]
            ttl:ttl];
    }
    return [MTContextDecision decisionWithGroup:MTContextGroupClipboard reason:@"clipboard-text"
        actions:@[paste,
                  [MTContextAction actionWithIdentifier:@"ai:clipboard"
                      title:MTContextLocalized(@"CONTEXT_GROUP_ASK_AI", @"问 AI")
                     symbol:@"sparkles" payloadKind:MTContextPayloadAISeed payload:text],
                  [MTContextAction actionWithIdentifier:@"url:search"
                      title:MTContextLocalized(@"CONTEXT_GROUP_SEARCH", @"搜索")
                     symbol:@"magnifyingglass" payloadKind:MTContextPayloadURL
                      payload:MTContextSearchURLString(text)]]
        ttl:ttl];
}

#pragma mark - G3 粘贴后

+ (MTContextDecision *)pasteDecision:(MTContextSnapshot *)snapshot settings:(MTContextGroupSettings *)settings {
    // 刚粘完的下一个动作是「发现不对」：撤销优先，其次是把内容拿去处理。
    NSMutableArray *actions = [NSMutableArray array];
    [actions addObject:[MTContextAction actionWithIdentifier:@"selector:undoAction:"
        title:MTContextLocalized(@"CONTEXT_GROUP_UNDO_PASTE", @"撤销粘贴")
        symbol:@"arrow.uturn.backward" payloadKind:MTContextPayloadSelector payload:@"undoAction:"]];
    NSString *text = snapshot.clipboardText ?: snapshot.selectionText;
    if (text.length) {
        [actions addObject:[MTContextAction actionWithIdentifier:@"ai:paste"
            title:MTContextLocalized(@"CONTEXT_GROUP_ASK_AI", @"问 AI")
            symbol:@"sparkles" payloadKind:MTContextPayloadAISeed payload:text]];
    }
    return [MTContextDecision decisionWithGroup:MTContextGroupPaste reason:@"paste-inserted"
        actions:actions ttl:settings.pasteFreshness - snapshot.pasteAge];
}

#pragma mark - G4 输入类型

+ (MTContextDecision *)inputDecision:(MTContextSnapshot *)snapshot settings:(MTContextGroupSettings *)settings {
    NSString *type = snapshot.contentType.lowercaseString;
    BOOL oneTimeCode = [type isEqual:@"onetimecode"];
    BOOL urlField = [type isEqual:@"url"] || [type isEqual:@"emailaddress"] ||
        snapshot.keyboardType == 3 /* UIKeyboardTypeURL */ || snapshot.keyboardType == 7 /* WebSearch */;
    // 安全输入框一律不主动出动作：任何基于内容的判断都可能泄露密码长度/内容。
    if (snapshot.secureInput) return nil;

    if (oneTimeCode) {
        // 验证码通常已在剪贴板（短信自动化写入，180 秒有效）。这里只给粘贴，不读内容；
        // 剪贴板没有新鲜信号时不出这组，免得把链接/正文粘进验证码框。
        if (!snapshot.clipboardAvailable) return nil;
        return [MTContextDecision decisionWithGroup:MTContextGroupInput reason:@"input-otp"
            actions:@[[MTContextAction actionWithIdentifier:@"selector:pasteAction:"
                          title:MTContextLocalized(@"CONTEXT_GROUP_PASTE_CODE", @"粘贴验证码")
                         symbol:@"number.square" payloadKind:MTContextPayloadSelector payload:@"pasteAction:"]]
            ttl:0];
    }
    if (urlField) {
        NSURL *clipboardURL = MTContextURLForText(snapshot.clipboardText);
        NSMutableArray *actions = [NSMutableArray array];
        if (clipboardURL && snapshot.clipboardAvailable &&
            snapshot.clipboardAge <= settings.clipboardFreshness) {
            [actions addObject:[MTContextAction actionWithIdentifier:@"url:open"
                title:MTContextLocalized(@"CONTEXT_GROUP_OPEN_CLIPBOARD_LINK", @"打开剪贴板链接")
                symbol:@"link" payloadKind:MTContextPayloadURL payload:clipboardURL.absoluteString]];
        }
        if (snapshot.clipboardAvailable) {
            [actions addObject:[MTContextAction actionWithIdentifier:@"selector:pasteAction:"
                title:MTContextLocalized(@"CONTEXT_GROUP_PASTE", @"粘贴")
                symbol:@"doc.on.clipboard" payloadKind:MTContextPayloadSelector payload:@"pasteAction:"]];
        }
        if (!actions.count) return nil;
        return [MTContextDecision decisionWithGroup:MTContextGroupInput reason:@"input-url"
            actions:actions ttl:0];
    }
    return nil;
}

#pragma mark - 入口

+ (MTContextDecision *)decisionForSnapshot:(MTContextSnapshot *)snapshot settings:(MTContextGroupSettings *)settings {
    if (!snapshot || !settings || !settings.enabled) {
        return [MTContextDecision decisionWithGroup:MTContextGroupDefault reason:@"disabled" actions:@[] ttl:0];
    }
    // G3 是短时覆盖层，必须先判：刚粘完时选区已被折叠，若等 G1 判就永远亮不起来。
    if (settings.pasteEnabled && snapshot.pastedLength >= settings.pasteMinLength &&
        snapshot.pasteAge >= 0 && snapshot.pasteAge <= settings.pasteFreshness) {
        return [self pasteDecision:snapshot settings:settings];
    }

    BOOL clipboardFresh = snapshot.clipboardAvailable &&
        snapshot.clipboardAge >= 0 && snapshot.clipboardAge <= settings.clipboardFreshness;
    BOOL hasSelection = snapshot.selectionLength > 0;
    // 「刚复制」与「刚选中」谁更新就显示谁：
    // - 选中文字后按复制：选区时间更早、剪贴板时间更晚 → 显示粘贴（这正是用户下一步要做的）；
    // - 复制完又去拖选另一段：选区更晚 → 显示选区动作，不被旧剪贴板霸占。
    BOOL clipboardPreferred = clipboardFresh && snapshot.clipboardAge < snapshot.selectionAge;

    if (settings.clipboardEnabled && clipboardPreferred) {
        return [self clipboardDecision:snapshot settings:settings];
    }
    if (settings.selectionEnabled && hasSelection) {
        return [self selectionDecision:snapshot];
    }
    if (settings.clipboardEnabled && clipboardFresh) {
        return [self clipboardDecision:snapshot settings:settings];
    }
    if (settings.inputEnabled) {
        MTContextDecision *decision = [self inputDecision:snapshot settings:settings];
        if (decision) return decision;
    }
    return [self defaultDecision];
}

@end
