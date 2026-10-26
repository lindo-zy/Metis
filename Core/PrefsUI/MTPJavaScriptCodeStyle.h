#import <UIKit/UIKit.h>
#import "MTPJavaScriptHighlighter.h"

NS_ASSUME_NONNULL_BEGIN

// JS 代码的统一着色样式：编辑器与预览卡共用，保证两处颜色和行高一致。
@interface MTPJavaScriptCodeStyle : NSObject

+ (UIFont *)codeFont;
+ (CGFloat)lineHeight;
+ (NSDictionary<NSAttributedStringKey, id> *)baseAttributes;
+ (UIColor *)colorForTokenType:(MTPJSTokenType)type;
// 供 UILabel（预览卡）直接使用。
+ (NSAttributedString *)attributedStringForSource:(NSString *)source;
// 供 UITextView 的 textStorage 原地重着色，不改变文本内容。
+ (void)applyToStorage:(NSMutableAttributedString *)storage;

@end

NS_ASSUME_NONNULL_END
