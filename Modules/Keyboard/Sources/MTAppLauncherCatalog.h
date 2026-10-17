#import "MTAppSearch.h"

// All public calls and completions are main-thread only. No SpringBoard singleton access.
@interface MTAppLauncherCatalog : NSObject
@property(nonatomic, copy) void (^didInvalidate)(void);
- (void)loadWithAliases:(NSDictionary *)aliases fallbackNames:(NSDictionary<NSString *, NSString *> *)names
    completion:(void (^)(NSArray<MTAppSearchEntry *> *entries, BOOL available))completion;
@end
