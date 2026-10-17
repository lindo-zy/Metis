#import <UIKit/UIKit.h>

// 轻量 Markdown → NSAttributedString 渲染器（零依赖，供 AI 面板助手气泡用）。
// 支持：# 标题、- / 1. 列表（含两级缩进）、> 引用、--- 分割线、``` 围栏代码、
// 行内 `代码` / **粗体** / *斜体* / ~~删除线~~ / [文本](链接)。流式期间每次
// 全量重渲染，未闭合语法按原样显示（与网页渲染器行为一致）。
@interface DXAIMarkdown : NSObject
+ (NSAttributedString *)attributedStringWithMarkdown:(NSString *)markdown
                                                font:(UIFont *)font
                                           textColor:(UIColor *)textColor
                                         accentColor:(UIColor *)accentColor
                                     codeBackground:(UIColor *)codeBackground;
@end
