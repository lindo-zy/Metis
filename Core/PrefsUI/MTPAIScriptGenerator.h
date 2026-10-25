#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface MTPAIScriptGenerator : NSObject
+ (NSString *)systemPrompt;
+ (NSArray<NSDictionary *> *)messagesForHistory:(NSArray<NSDictionary *> *)history
                                   requirement:(NSString *)requirement
                                 currentScript:(nullable NSString *)currentScript;
+ (NSString *)scriptFromReply:(NSString *)reply;
// Syntax and global async main declaration only; never evaluates the source.
+ (nullable NSString *)precheckErrorForScript:(NSString *)script;
@end
NS_ASSUME_NONNULL_END
