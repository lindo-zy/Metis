#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// One script session. Call public methods on the main thread. JS and network
// processing stay on a private queue; callbacks always arrive on main.
@interface DXJavaScriptEngine : NSObject
@property (nonatomic, copy, nullable) void (^actionHandler)(NSDictionary *action);
@property (nonatomic, copy, nullable) void (^logHandler)(NSString *message);
@property (nonatomic, copy, nullable) void (^resultHandler)(NSArray<NSDictionary *> * _Nullable actions, NSError * _Nullable error);
- (void)runSource:(NSString *)source input:(NSString *)input;
- (void)callFunction:(NSString *)name arguments:(NSArray *)arguments;
- (void)cancel;
// Shared by tests and the runner; validates the complete result before any
// returned action executes. nil/NSNull mean no action, not an empty insertion.
+ (nullable NSArray<NSDictionary *> *)actionsForResult:(nullable id)result error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
