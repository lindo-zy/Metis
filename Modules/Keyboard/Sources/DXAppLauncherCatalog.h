#import "DXAppSearch.h"

// All public calls and completions are main-thread only. No SpringBoard singleton access.
@interface DXAppLauncherCatalog : NSObject
@property(nonatomic, copy) void (^didInvalidate)(void);
- (void)loadWithAliases:(NSDictionary *)aliases fallbackNames:(NSDictionary<NSString *, NSString *> *)names
    completion:(void (^)(NSArray<DXAppSearchEntry *> *entries, BOOL available))completion;
@end
