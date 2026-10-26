#import "MTPAIScriptGenerator.h"
#import "MTPAIScriptProfile.h"

// 兼容层：实际实现已收敛到 MTPAIScriptProfile（按运行契约分派）。
// 这里保留旧类方法，供既有调用点与剪贴板子包继续使用 main(str) 契约。
@implementation MTPAIScriptGenerator

+ (NSString *)systemPrompt {
    return [[MTPAIScriptProfile actionProfile] systemPrompt];
}

+ (NSArray<NSDictionary *> *)messagesForHistory:(NSArray<NSDictionary *> *)history
                                   requirement:(NSString *)requirement
                                 currentScript:(NSString *)currentScript {
    return [self messagesForHistory:history requirement:requirement
                      currentScript:currentScript profile:[MTPAIScriptProfile actionProfile]];
}

+ (NSArray<NSDictionary *> *)messagesForHistory:(NSArray<NSDictionary *> *)history
                                   requirement:(NSString *)requirement
                                 currentScript:(NSString *)currentScript
                                       profile:(MTPAIScriptProfile *)profile {
    MTPAIScriptProfile *target = profile ?: [MTPAIScriptProfile actionProfile];
    NSMutableArray *messages = [NSMutableArray arrayWithObject:@{@"role": @"system", @"content": [target systemPrompt]}];
    // Keep complete user/assistant pairs; never carry arbitrary roles into the request.
    NSMutableArray *rounds = [NSMutableArray array];
    for (NSUInteger i = 0; i + 1 < history.count; i++) {
        NSDictionary *user = history[i], *assistant = history[i + 1];
        if (![user isKindOfClass:NSDictionary.class] || ![assistant isKindOfClass:NSDictionary.class]) continue;
        if (![user[@"role"] isEqual:@"user"] || ![assistant[@"role"] isEqual:@"assistant"] ||
            ![user[@"content"] isKindOfClass:NSString.class] || ![assistant[@"content"] isKindOfClass:NSString.class]) continue;
        [rounds addObjectsFromArray:@[user, assistant]];
        i++;
    }
    if (!rounds.count && currentScript.length) {
        [messages addObject:@{@"role": @"user", @"content": [NSString stringWithFormat:
            @"【当前脚本】（用户正在编辑的版本，仅作参考基线，与需求无关可忽略）\n%@", currentScript]}];
    }
    NSUInteger start = rounds.count > 20 ? rounds.count - 20 : 0;
    [messages addObjectsFromArray:[rounds subarrayWithRange:NSMakeRange(start, rounds.count - start)]];
    if (requirement.length) [messages addObject:@{@"role": @"user", @"content": requirement}];
    return messages;
}

+ (NSString *)scriptFromReply:(NSString *)reply {
    return [[MTPAIScriptProfile actionProfile] scriptFromReply:reply];
}

+ (NSString *)precheckErrorForScript:(NSString *)script {
    return [[MTPAIScriptProfile actionProfile] precheckErrorForScript:script];
}

@end
