#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MTPAIScriptProfile;

@interface MTPAIScriptGenerator : NSObject
+ (NSString *)systemPrompt;
+ (NSArray<NSDictionary *> *)messagesForHistory:(NSArray<NSDictionary *> *)history
                                   requirement:(NSString *)requirement
                                 currentScript:(nullable NSString *)currentScript;
// 按目标契约构造对话；profile 决定 system prompt，其余装配规则共用。
+ (NSArray<NSDictionary *> *)messagesForHistory:(NSArray<NSDictionary *> *)history
                                   requirement:(NSString *)requirement
                                 currentScript:(nullable NSString *)currentScript
                                       profile:(MTPAIScriptProfile *)profile;
+ (NSString *)scriptFromReply:(NSString *)reply;
// Syntax and global entry declaration only; never evaluates the source.
+ (nullable NSString *)precheckErrorForScript:(NSString *)script;
@end
NS_ASSUME_NONNULL_END
