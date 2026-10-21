#import <Foundation/Foundation.h>
#include <math.h>
#import "MTSystemActionCatalog.h"

static inline NSString *MTGlobalPanelString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}
static inline NSString *MTGlobalPanelNormalizedPayload(id value) {
    NSString *payload = [MTGlobalPanelString(value) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [payload.lowercaseString hasPrefix:@"www."] ? [@"https://" stringByAppendingString:payload] : payload;
}

// Accept the full Dock background, including gaps at icon height, plus the
// strip below it. Visible icon images are excluded by the touch-view policy.
static inline BOOL MTDockPanelOriginAllowed(double x, double y, double width, double height, double below) {
    return isfinite(x) && isfinite(y) && isfinite(width) && isfinite(height) && isfinite(below) &&
        width > 0 && height > 0 && below >= 0 && x >= 0 && x <= width &&
        y >= 0 && y <= height + below;
}
static inline BOOL MTDockPanelSwipeCompletes(double dx, double dy) {
    return isfinite(dx) && isfinite(dy) && dy <= -48 && -dy >= fabs(dx) * 1.5;
}

// SpringBoard cannot address another process's editor. Never silently replace
// its text parameter with an empty string or execute against a stale responder.
// jsInput=clipboard 的 JavaScript 输入来自系统剪切板，不算「需要输入框」
//（docs/development/03 §6：明确的 clipboard 输入可从手势运行）。
static inline BOOL MTGlobalPanelActionNeedsInput(NSDictionary *entry) {
    NSString *type = [entry[@"type"] isKindOfClass:NSString.class] ? entry[@"type"] : @"";
    NSString *link = [entry[@"link"] isKindOfClass:NSString.class] ? entry[@"link"] : @"";
    if ([type isEqual:@"javascript"]) {
        id inputMode = entry[@"jsInput"] ?: @"auto";
        return ![inputMode isEqual:@"clipboard"];
    }
    return [type isEqual:@"text"] || [link containsString:@"@@@"];
}

static inline BOOL MTGlobalCustomActionSupported(id entry) {
    if (![entry isKindOfClass:NSDictionary.class] || MTGlobalPanelActionNeedsInput(entry)) return NO;
    NSString *type = MTGlobalPanelString(entry[@"type"]);
    if ([type isEqual:@"system"]) return MTSystemActionDefinition(entry[@"systemaction"]) != nil;
    // AI 动作：桌面全局面板没有输入框，点击只打开 AI 面板（不带问题、不自动
    // 发送），所以不要求 link 载荷。
    if ([type isEqual:@"ai"]) return YES;
    // 无输入框 JS：jsInput=clipboard + jsOutput=copy 走无会话宿主执行。
    if ([type isEqual:@"javascript"]) {
        id inputMode = entry[@"jsInput"] ?: @"auto";
        id outputMode = entry[@"jsOutput"] ?: @"replace";
        return [inputMode isEqual:@"clipboard"] && [outputMode isEqual:@"copy"];
    }
    NSString *payload = MTGlobalPanelNormalizedPayload(entry[@"link"]);
    if (!payload.length) return NO;
    if ([type isEqual:@"shortcut"]) return [MTGlobalPanelString(entry[@"shortcuttype"]) length] > 0;
    return !type.length || [@[@"openapp", @"urlscheme", @"url"] containsObject:type];
}
