#import "MTQuickAction.h"
#import "MTClipboardActionReferences.h"
#import "MTSharedResourceStore.h"
#import "MTGlobalActionExecutor.h"

@implementation MTQuickAction

+ (NSArray<NSDictionary<NSString *, id> *> *)actionsForKind:(MTQuickActionKind)kind {
    NSString *slot = kind == MTQuickActionKindImage ? @"image" :
        (kind == MTQuickActionKindImageDoubleTap ? @"image-double-tap" : @"text");
    return [MTClipboardActionReferences actionsInDocument:[MTSharedResourceStore readSnapshot] slot:slot];
}

+ (void)openAction:(NSDictionary<NSString *, id> *)action input:(NSString *)input
 completionHandler:(void (^)(BOOL success))completionHandler {
    // Resolve the UUID again at execution time so a stale menu cannot run a deleted payload.
    NSDictionary *currentEntry = nil;
    for (NSDictionary *resource in [MTSharedResourceStore readSnapshot][@"actions"]) {
        if ([resource[@"id"] isEqual:action[@"id"]]) { currentEntry = resource[@"entry"]; break; }
    }
    if (!currentEntry || ![MTClipboardActionReferences supportsEntry:currentEntry]) {
        if (completionHandler) completionHandler(NO);
        return;
    }
    NSMutableDictionary *entry = [currentEntry mutableCopy];
    NSString *type = entry[@"type"] ?: @"";
    // Clipboard-v1 placeholders retain their original percent-encoding semantics.
    if ([@[@"", @"url", @"urlscheme"] containsObject:type]) {
        NSString *link = [entry[@"link"] isKindOfClass:NSString.class] ? entry[@"link"] : @"";
        NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
        [allowed addCharactersInString:@"-._~"];
        NSString *encoded = [(input ?: @"") stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
        for (NSString *placeholder in @[@"$$$", @"@@@"]) link = [link stringByReplacingOccurrencesOfString:placeholder withString:encoded];
        entry[@"link"] = link;
    }
    MTExecuteGlobalCustomAction(entry, ^(MTSystemOpenResult result) {
        if (completionHandler) completionHandler(result == MTSystemOpenSucceeded);
    });
}
@end
