#import "DXAIMarkdown.h"

// 颜色派生：引用文字/分割线用主色降透明度，避免再传两个颜色参数。
#define DXMDFaded(color, alpha) [color colorWithAlphaComponent:(alpha)]

static UIFont *DXMDFontWithTraits(UIFont *font, UIFontDescriptorSymbolicTraits traits) {
    UIFontDescriptorSymbolicTraits combined = font.fontDescriptor.symbolicTraits | traits;
    UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorWithSymbolicTraits:combined];
    if (!descriptor) return font;
    UIFont *applied = [UIFont fontWithDescriptor:descriptor size:0];
    return applied ?: font;
}

static UIFont *DXMDCodeFont(UIFont *base) {
    UIFont *menlo = [UIFont fontWithName:@"Menlo-Regular" size:base.pointSize - 1.0];
    if (!menlo) menlo = [UIFont fontWithName:@"CourierNewPSMT" size:base.pointSize - 1.0];
    return menlo ?: base;
}

static NSParagraphStyle *DXMDStyle(CGFloat firstIndent, CGFloat headIndent,
                                   CGFloat spacingBefore, CGFloat spacingAfter) {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.firstLineHeadIndent = firstIndent;
    style.headIndent = headIndent;
    style.paragraphSpacingBefore = spacingBefore;
    style.paragraphSpacing = spacingAfter;
    style.lineSpacing = 2.0;
    return style;
}

#pragma mark - 行内格式

@implementation DXAIMarkdown

// 行内规则按"最早命中优先"扫描并对捕获内容递归（嵌套如 **粗中`码`** 自然成立）。
// 不支持 _单下划线斜体_：会误伤 snake_case 标识符，模型输出以 *斜体* 为主。
typedef NS_ENUM(NSInteger, DXMDRule) {
    DXMDRuleCode = 0,   // `x`
    DXMDRuleBold,       // **x** 或 __x__
    DXMDRuleItalic,     // *x*
    DXMDRuleStrike,     // ~~x~~
    DXMDRuleLink,       // [x](url)
    DXMDRuleCount,
};

+ (NSArray<NSRegularExpression *> *)inlineRegexes {
    static NSArray<NSRegularExpression *> *regexes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *patterns = @{
            @(DXMDRuleCode): @"`([^`\\n]+)`",
            @(DXMDRuleBold): @"\\*\\*(.+?)\\*\\*|__(.+?)__",
            @(DXMDRuleItalic): @"\\*([^*\\n]+)\\*",
            @(DXMDRuleStrike): @"~~(.+?)~~",
            @(DXMDRuleLink): @"\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)",
        };
        NSMutableArray *built = [NSMutableArray array];
        NSRegularExpressionOptions options = NSRegularExpressionDotMatchesLineSeparators;
        for (NSUInteger rule = 0; rule < DXMDRuleCount; rule++) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:patterns[@(rule)]
                                                                                   options:options error:nil];
            [built addObject:regex ?: [[NSRegularExpression alloc] init]];
        }
        regexes = built;
    });
    return regexes;
}

// 递归渲染行内片段：找到最早命中的规则，前缀原样输出，捕获内容带新属性递归，
// 余下部分继续扫描。
+ (void)dxRenderInline:(NSString *)text
                 attrs:(NSDictionary<NSAttributedStringKey, id> *)attrs
                accent:(UIColor *)accent
              codeBackground:(UIColor *)codeBackground
                    out:(NSMutableAttributedString *)out {
    if (text.length == 0) return;

    NSArray<NSRegularExpression *> *regexes = [self inlineRegexes];
    NSRange best = NSMakeRange(NSNotFound, 0);
    NSInteger bestRule = -1;
    for (NSUInteger rule = 0; rule < regexes.count; rule++) {
        NSTextCheckingResult *match = [regexes[rule] firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (!match) continue;
        NSRange range = match.range;
        if (best.location == NSNotFound || range.location < best.location ||
            (range.location == best.location && range.length > best.length)) {
            best = range;
            bestRule = rule;
        }
    }
    if (bestRule < 0) {
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attrs]];
        return;
    }

    NSTextCheckingResult *match = [regexes[bestRule] firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (match.range.location > 0) {
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:[text substringToIndex:match.range.location]
                                                                     attributes:attrs]];
    }

    NSMutableDictionary *inner = [attrs mutableCopy];
    NSString *content = nil;
    switch (bestRule) {
        case DXMDRuleCode: {
            content = [self dxGroup:match index:1 of:text];
            inner[NSFontAttributeName] = DXMDCodeFont(attrs[NSFontAttributeName]);
            inner[NSBackgroundColorAttributeName] = codeBackground;
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:content attributes:inner]];
            break;
        }
        case DXMDRuleBold: {
            content = [self dxGroup:match index:1 of:text] ?: [self dxGroup:match index:2 of:text];
            inner[NSFontAttributeName] = DXMDFontWithTraits(attrs[NSFontAttributeName], UIFontDescriptorTraitBold);
            [self dxRenderInline:content attrs:inner accent:accent codeBackground:codeBackground out:out];
            break;
        }
        case DXMDRuleItalic: {
            content = [self dxGroup:match index:1 of:text];
            inner[NSFontAttributeName] = DXMDFontWithTraits(attrs[NSFontAttributeName], UIFontDescriptorTraitItalic);
            [self dxRenderInline:content attrs:inner accent:accent codeBackground:codeBackground out:out];
            break;
        }
        case DXMDRuleStrike: {
            content = [self dxGroup:match index:1 of:text];
            inner[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
            [self dxRenderInline:content attrs:inner accent:accent codeBackground:codeBackground out:out];
            break;
        }
        case DXMDRuleLink: {
            content = [self dxGroup:match index:1 of:text];
            NSString *url = [self dxGroup:match index:2 of:text] ?: @"";
            inner[NSLinkAttributeName] = [NSURL URLWithString:url] ?: url;
            inner[NSForegroundColorAttributeName] = accent;
            inner[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
            [self dxRenderInline:content attrs:inner accent:accent codeBackground:codeBackground out:out];
            break;
        }
    }

    if (NSMaxRange(match.range) < text.length) {
        [self dxRenderInline:[text substringFromIndex:NSMaxRange(match.range)]
                       attrs:attrs accent:accent codeBackground:codeBackground out:out];
    }
}

+ (NSString *)dxGroup:(NSTextCheckingResult *)match index:(NSUInteger)index of:(NSString *)text {
    NSRange range = [match rangeAtIndex:index];
    if (range.location == NSNotFound || range.length == 0) return nil;
    return [text substringWithRange:range];
}

#pragma mark - 块级解析

// 标题字号按基准字号缩放（h1 1.3 → h6 0.95），粗体。
+ (NSAttributedString *)dxHeading:(NSString *)text
                            level:(NSUInteger)level
                             font:(UIFont *)font
                            color:(UIColor *)color
                           accent:(UIColor *)accent
                   codeBackground:(UIColor *)codeBackground {
    static const CGFloat scales[] = {1.3, 1.2, 1.1, 1.0, 0.98, 0.95};
    CGFloat scale = scales[MIN(level, 5)];
    UIFont *headingFont = DXMDFontWithTraits([UIFont systemFontOfSize:floor(font.pointSize * scale)],
                                             UIFontDescriptorTraitBold);
    NSMutableAttributedString *block = [[NSMutableAttributedString alloc] init];
    [self dxRenderInline:text
                   attrs:@{NSFontAttributeName: headingFont, NSForegroundColorAttributeName: color}
                  accent:accent
          codeBackground:codeBackground
                     out:block];
    return block;
}

+ (NSAttributedString *)attributedStringWithMarkdown:(NSString *)markdown
                                                font:(UIFont *)font
                                           textColor:(UIColor *)textColor
                                         accentColor:(UIColor *)accentColor
                                     codeBackground:(UIColor *)codeBackground {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    if (markdown.length == 0) return out;

    NSArray<NSString *> *lines = [markdown componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSDictionary *bodyAttrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: textColor};
    NSMutableArray<NSString *> *fenceLines = nil;

    for (NSString *raw in lines) {
        NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        // ── 围栏代码 ──
        if ([trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"~~~"]) {
            if (!fenceLines) {
                fenceLines = [NSMutableArray array];
            } else {
                [out appendAttributedString:[self dxCodeBlock:fenceLines font:font color:textColor background:codeBackground]];
                fenceLines = nil;
            }
            continue;
        }
        if (fenceLines) {
            [fenceLines addObject:raw];
            continue;
        }

        if (trimmed.length == 0) continue;

        // ── 分割线 ──
        if ([self dxIsHorizontalRule:trimmed]) {
            NSMutableAttributedString *rule = [[NSMutableAttributedString alloc]
                initWithString:[@"─" stringByPaddingToLength:24 withString:@"─" startingAtIndex:0]
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:10.0],
                             NSForegroundColorAttributeName: DXMDFaded(textColor, 0.35),
                             NSParagraphStyleAttributeName: DXMDStyle(4, 4, 6, 6)}];
            [out appendAttributedString:rule];
            continue;
        }

        // ── 标题 ──
        static NSRegularExpression *headingRegex;
        static dispatch_once_t headingOnce;
        dispatch_once(&headingOnce, ^{
            headingRegex = [NSRegularExpression regularExpressionWithPattern:@"^(#{1,6})\\s+(.+)$" options:0 error:nil];
        });
        NSTextCheckingResult *heading = [headingRegex firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
        if (heading) {
            NSUInteger level = [trimmed substringWithRange:[heading rangeAtIndex:1]].length;
            NSString *content = [trimmed substringWithRange:[heading rangeAtIndex:2]];
            NSMutableAttributedString *block = [[NSMutableAttributedString alloc]
                initWithAttributedString:[self dxHeading:content level:level - 1 font:font color:textColor accent:accentColor codeBackground:codeBackground]];
            [block addAttributes:@{NSParagraphStyleAttributeName: DXMDStyle(0, 0, 10, 3)} range:NSMakeRange(0, block.length)];
            [out appendAttributedString:block];
            continue;
        }

        // ── 引用 ──（多级 > 一并剥掉，整段缩进+降透明度）
        if ([trimmed hasPrefix:@">"]) {
            NSString *content = trimmed;
            while ([content hasPrefix:@">"]) content = [content substringFromIndex:1];
            content = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (content.length == 0) continue;
            NSMutableAttributedString *block = [[NSMutableAttributedString alloc] init];
            NSDictionary *quoteAttrs = @{NSFontAttributeName: DXMDFontWithTraits(font, UIFontDescriptorTraitItalic),
                                         NSForegroundColorAttributeName: DXMDFaded(textColor, 0.72)};
            [self dxRenderInline:content attrs:quoteAttrs accent:accentColor codeBackground:codeBackground out:block];
            [block addAttributes:@{NSParagraphStyleAttributeName: DXMDStyle(12, 12, 4, 4)} range:NSMakeRange(0, block.length)];
            [out appendAttributedString:block];
            continue;
        }

        // ── 无序列表 ──（按前导空格分两级缩进）
        static NSRegularExpression *ulRegex;
        static dispatch_once_t ulOnce;
        dispatch_once(&ulOnce, ^{
            ulRegex = [NSRegularExpression regularExpressionWithPattern:@"^(\\s{0,4})[-*+]\\s+(.+)$" options:0 error:nil];
        });
        NSTextCheckingResult *ul = [ulRegex firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)];
        if (ul) {
            NSUInteger spaces = [raw substringWithRange:[ul rangeAtIndex:1]].length;
            NSUInteger level = spaces >= 2 ? 1 : 0;
            NSString *content = [raw substringWithRange:[ul rangeAtIndex:2]];
            NSString *bullet = level == 0 ? @"•  " : @"◦  ";
            CGFloat indent = 4.0 + level * 16.0;
            [out appendAttributedString:[self dxListItem:content prefix:bullet firstIndent:indent headIndent:indent + 14.0
                                                    font:font color:textColor accent:accentColor codeBackground:codeBackground]];
            continue;
        }

        // ── 有序列表 ──
        static NSRegularExpression *olRegex;
        static dispatch_once_t olOnce;
        dispatch_once(&olOnce, ^{
            olRegex = [NSRegularExpression regularExpressionWithPattern:@"^(\\s{0,4})(\\d{1,9})[.)]\\s+(.+)$" options:0 error:nil];
        });
        NSTextCheckingResult *ol = [olRegex firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)];
        if (ol) {
            NSUInteger spaces = [raw substringWithRange:[ol rangeAtIndex:1]].length;
            NSUInteger level = spaces >= 2 ? 1 : 0;
            NSString *number = [raw substringWithRange:[ol rangeAtIndex:2]];
            NSString *content = [raw substringWithRange:[ol rangeAtIndex:3]];
            CGFloat indent = 4.0 + level * 16.0;
            [out appendAttributedString:[self dxListItem:content
                                                  prefix:[NSString stringWithFormat:@"%@.  ", number]
                                             firstIndent:indent
                                              headIndent:indent + 20.0
                                                    font:font color:textColor accent:accentColor codeBackground:codeBackground]];
            continue;
        }

        // ── 普通段落 ──
        NSMutableAttributedString *block = [[NSMutableAttributedString alloc] init];
        [self dxRenderInline:trimmed attrs:bodyAttrs accent:accentColor codeBackground:codeBackground out:block];
        [block addAttributes:@{NSParagraphStyleAttributeName: DXMDStyle(0, 0, 2, 4)} range:NSMakeRange(0, block.length)];
        [out appendAttributedString:block];
    }

    // 流式中围栏未闭合：已收到的代码行先照常显示。
    if (fenceLines.count > 0) {
        [out appendAttributedString:[self dxCodeBlock:fenceLines font:font color:textColor background:codeBackground]];
    }
    return out;
}

+ (BOOL)dxIsHorizontalRule:(NSString *)line {
    if (line.length < 3) return NO;
    unichar marker = 0;
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (c == ' ') continue;
        if (c != '-' && c != '*' && c != '_') return NO;
        if (marker == 0) marker = c;
        else if (marker != c) return NO;
    }
    return marker != 0;
}

+ (NSAttributedString *)dxCodeBlock:(NSArray<NSString *> *)lines
                               font:(UIFont *)font
                              color:(UIColor *)color
                         background:(UIColor *)background {
    NSString *code = [lines componentsJoinedByString:@"\n"];
    return [[NSAttributedString alloc] initWithString:code
                                           attributes:@{NSFontAttributeName: DXMDCodeFont(font),
                                                        NSForegroundColorAttributeName: color,
                                                        NSBackgroundColorAttributeName: background,
                                                        NSParagraphStyleAttributeName: DXMDStyle(8, 8, 6, 6)}];
}

+ (NSAttributedString *)dxListItem:(NSString *)content
                            prefix:(NSString *)prefix
                       firstIndent:(CGFloat)firstIndent
                        headIndent:(CGFloat)headIndent
                              font:(UIFont *)font
                             color:(UIColor *)color
                            accent:(UIColor *)accent
                    codeBackground:(UIColor *)codeBackground {
    NSMutableAttributedString *block = [[NSMutableAttributedString alloc] init];
    [block appendAttributedString:[[NSAttributedString alloc] initWithString:prefix
                                                                  attributes:@{NSFontAttributeName: font,
                                                                               NSForegroundColorAttributeName: color}]];
    [self dxRenderInline:content
                   attrs:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}
                  accent:accent
          codeBackground:codeBackground
                     out:block];
    [block addAttributes:@{NSParagraphStyleAttributeName: DXMDStyle(firstIndent, headIndent, 3, 3)} range:NSMakeRange(0, block.length)];
    return block;
}

@end
