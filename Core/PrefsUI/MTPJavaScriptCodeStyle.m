#import "MTPJavaScriptCodeStyle.h"

static NSMutableParagraphStyle *MTPJSCodeParagraph(void) {
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.minimumLineHeight = 19.0;
    paragraph.maximumLineHeight = 19.0;
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    return paragraph;
}

@implementation MTPJavaScriptCodeStyle

+ (UIFont *)codeFont {
    return [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
}

+ (CGFloat)lineHeight { return 19.0; }

+ (NSDictionary<NSAttributedStringKey, id> *)baseAttributes {
    return @{NSFontAttributeName: [self codeFont],
             NSForegroundColorAttributeName: UIColor.labelColor,
             NSParagraphStyleAttributeName: MTPJSCodeParagraph()};
}

+ (UIColor *)colorForTokenType:(MTPJSTokenType)type {
    switch (type) {
        case MTPJSTokenTypeKeyword: return UIColor.systemPurpleColor;
        case MTPJSTokenTypeString: return UIColor.systemGreenColor;
        case MTPJSTokenTypeRegex: return UIColor.systemOrangeColor;
        case MTPJSTokenTypeNumber: return UIColor.systemTealColor;
        case MTPJSTokenTypeComment: return UIColor.secondaryLabelColor;
    }
    return UIColor.labelColor;
}

+ (void)applyToStorage:(NSMutableAttributedString *)storage {
    if (!storage) return;
    NSRange full = NSMakeRange(0, storage.length);
    if (!full.length) return;
    NSString *source = storage.string;
    [storage setAttributes:[self baseAttributes] range:full];
    for (NSDictionary *token in [MTPJavaScriptHighlighter tokensForSource:source]) {
        NSUInteger location = [token[MTPJSTokenLocationKey] unsignedIntegerValue];
        NSUInteger length = [token[MTPJSTokenLengthKey] unsignedIntegerValue];
        if (!length || NSMaxRange(NSMakeRange(location, length)) > source.length) continue;
        [storage addAttribute:NSForegroundColorAttributeName
                        value:[self colorForTokenType:(MTPJSTokenType)[token[MTPJSTokenTypeKey] integerValue]]
                        range:NSMakeRange(location, length)];
    }
}

+ (NSAttributedString *)attributedStringForSource:(NSString *)source {
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:source ?: @""
        attributes:[self baseAttributes]];
    [self applyToStorage:text];
    return text;
}

@end
