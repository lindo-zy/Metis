#import "MTPJavaScriptHighlighter.h"

NSString * const MTPJSTokenTypeKey = @"type";
NSString * const MTPJSTokenLocationKey = @"location";
NSString * const MTPJSTokenLengthKey = @"length";

static NSDictionary *MTPJSToken(MTPJSTokenType type, NSUInteger location, NSUInteger length) {
    return @{MTPJSTokenTypeKey: @(type), MTPJSTokenLocationKey: @(location), MTPJSTokenLengthKey: @(length)};
}

static BOOL MTPJSIsDigit(unichar c) { return c >= '0' && c <= '9'; }
static BOOL MTPJSIsAlpha(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$';
}
static BOOL MTPJSIsWord(unichar c) { return MTPJSIsAlpha(c) || MTPJSIsDigit(c); }

static NSSet<NSString *> *MTPJSKeywords(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"async", @"await", @"break", @"case", @"catch", @"class", @"const",
            @"continue", @"debugger", @"default", @"delete", @"do", @"else", @"export", @"extends", @"false",
            @"finally", @"for", @"function", @"get", @"if", @"import", @"in", @"instanceof", @"let", @"new",
            @"null", @"of", @"return", @"set", @"static", @"super", @"switch", @"this", @"throw", @"true",
            @"try", @"typeof", @"undefined", @"var", @"void", @"while", @"with", @"yield"]];
    });
    return set;
}

// 关键字之后、以及表达式起始位置的 `/` 是正则；右括号或标识符之后是除法。
static BOOL MTPJSRegexCanStart(NSInteger previousCharacter, NSString *previousWord) {
    if (previousCharacter == -1) return YES; // 行首或文件头
    if (previousWord.length) {
        static NSSet *bridges;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            bridges = [NSSet setWithArray:@[@"return", @"typeof", @"instanceof", @"case", @"delete", @"in",
                @"of", @"new", @"void", @"do", @"else", @"yield", @"await", @"throw"]];
        });
        return [bridges containsObject:previousWord];
    }
    switch (previousCharacter) {
        case '(': case ',': case '=': case ':': case '[': case '!': case '&': case '|': case '?':
        case '{': case '}': case ';': case '+': case '-': case '*': case '%': case '<': case '>':
        case '~': case '^':
            return YES;
        default:
            return NO;
    }
}

@implementation MTPJavaScriptHighlighter

+ (NSArray<NSDictionary<NSString *, id> *> *)tokensForSource:(NSString *)source {
    NSMutableArray<NSDictionary<NSString *, id> *> *tokens = [NSMutableArray array];
    if (![source isKindOfClass:NSString.class] || !source.length) return tokens;

    NSUInteger length = source.length;
    NSUInteger index = 0;
    NSInteger previousCharacter = -1;
    NSString *previousWord = nil;

    while (index < length) {
        unichar c = [source characterAtIndex:index];

        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            if (c == '\n') { previousCharacter = -1; previousWord = nil; }
            index++;
            continue;
        }

        // 行注释：止于换行，不吞掉换行本身。
        if (c == '/' && index + 1 < length && [source characterAtIndex:index + 1] == '/') {
            NSUInteger end = index + 2;
            while (end < length && [source characterAtIndex:end] != '\n') end++;
            [tokens addObject:MTPJSToken(MTPJSTokenTypeComment, index, end - index)];
            index = end;
            continue;
        }

        // 块注释：未闭合时着色到末尾，避免把半个脚本染成普通文本。
        if (c == '/' && index + 1 < length && [source characterAtIndex:index + 1] == '*') {
            NSUInteger scan = index + 2;
            while (scan + 1 < length &&
                   !([source characterAtIndex:scan] == '*' && [source characterAtIndex:scan + 1] == '/')) scan++;
            NSUInteger end = (scan + 1 < length) ? scan + 2 : length;
            [tokens addObject:MTPJSToken(MTPJSTokenTypeComment, index, end - index)];
            index = end;
            continue;
        }

        if (c == '"' || c == '\'' || c == '`') {
            unichar quote = c;
            NSUInteger end = index + 1;
            while (end < length) {
                unichar d = [source characterAtIndex:end];
                if (d == '\\') { end += 2; continue; }
                if (d == quote) { end++; break; }
                // 单双引号字符串不跨行；模板字符串允许换行。
                if (d == '\n' && quote != '`') break;
                end++;
            }
            if (end > length) end = length;
            [tokens addObject:MTPJSToken(MTPJSTokenTypeString, index, end - index)];
            previousCharacter = quote;
            previousWord = nil;
            index = end;
            continue;
        }

        if (c == '/' && MTPJSRegexCanStart(previousCharacter, previousWord)) {
            NSUInteger end = index + 1;
            BOOL inClass = NO;
            BOOL closed = NO;
            while (end < length) {
                unichar d = [source characterAtIndex:end];
                if (d == '\\') { end += 2; continue; }
                if (d == '\n') break;
                if (d == '[') inClass = YES;
                else if (d == ']') inClass = NO;
                else if (d == '/' && !inClass) { end++; closed = YES; break; }
                end++;
            }
            if (closed) {
                while (end < length) {
                    unichar flag = [source characterAtIndex:end];
                    if ((flag >= 'a' && flag <= 'z') || (flag >= 'A' && flag <= 'Z')) end++;
                    else break;
                }
            }
            if (end > length) end = length;
            [tokens addObject:MTPJSToken(MTPJSTokenTypeRegex, index, end - index)];
            previousCharacter = '/';
            previousWord = nil;
            index = end;
            continue;
        }

        if (MTPJSIsDigit(c) || (c == '.' && index + 1 < length && MTPJSIsDigit([source characterAtIndex:index + 1]))) {
            NSUInteger end = index;
            while (end < length) {
                unichar d = [source characterAtIndex:end];
                if (MTPJSIsWord(d) || d == '.') { end++; continue; }
                if ((d == '+' || d == '-') && end > index) {
                    unichar previous = [source characterAtIndex:end - 1];
                    if (previous == 'e' || previous == 'E') { end++; continue; }
                }
                break;
            }
            [tokens addObject:MTPJSToken(MTPJSTokenTypeNumber, index, end - index)];
            previousCharacter = '0';
            previousWord = nil;
            index = end;
            continue;
        }

        if (MTPJSIsAlpha(c)) {
            NSUInteger end = index;
            while (end < length && MTPJSIsWord([source characterAtIndex:end])) end++;
            NSString *word = [source substringWithRange:NSMakeRange(index, end - index)];
            if ([MTPJSKeywords() containsObject:word]) {
                [tokens addObject:MTPJSToken(MTPJSTokenTypeKeyword, index, end - index)];
            }
            previousCharacter = 0;
            previousWord = word;
            index = end;
            continue;
        }

        previousCharacter = (NSInteger)c;
        previousWord = nil;
        index++;
    }
    return tokens;
}

@end
