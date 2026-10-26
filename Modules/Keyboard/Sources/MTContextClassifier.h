#pragma once
#import "MTContextTypes.h"

FOUNDATION_EXPORT NSArray<NSString *> *MTContextBuiltinMatches(NSString *text, BOOL hasImage);
FOUNDATION_EXPORT NSString *MTContextInsertedText(NSString *before, NSString *after);
@interface MTContextClassifier : NSObject
+ (instancetype)sharedClassifier;
- (void)classifyText:(NSString *)text surface:(NSString *)surface flags:(NSDictionary *)flags
              group:(NSString *)group config:(MTContextGroupConfig *)config completion:(void (^)(NSDictionary *result))completion;
- (void)testRule:(NSString *)identifier source:(NSString *)source text:(NSString *)text completion:(void (^)(NSDictionary *result))completion;
// 调试台入口：captureLogs 为 YES 时把 console.log 收进 result[@"logs"]。
// 运行时判定路径仍走上面的方法，保证调试不改变缓存与失败计数语义。
- (void)testRule:(NSString *)identifier source:(NSString *)source text:(NSString *)text
     captureLogs:(BOOL)captureLogs completion:(void (^)(NSDictionary *result))completion;
- (void)invalidate;
@end
