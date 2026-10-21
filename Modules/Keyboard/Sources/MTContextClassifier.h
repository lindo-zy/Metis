#pragma once
#import "MTContextTypes.h"

FOUNDATION_EXPORT NSArray<NSString *> *MTContextBuiltinMatches(NSString *text, BOOL hasImage);
FOUNDATION_EXPORT NSString *MTContextInsertedText(NSString *before, NSString *after);
@interface MTContextClassifier : NSObject
+ (instancetype)sharedClassifier;
- (void)classifyText:(NSString *)text surface:(NSString *)surface flags:(NSDictionary *)flags
              group:(NSString *)group config:(MTContextGroupConfig *)config completion:(void (^)(NSDictionary *result))completion;
- (void)testRule:(NSString *)identifier source:(NSString *)source text:(NSString *)text completion:(void (^)(NSDictionary *result))completion;
- (void)invalidate;
@end
