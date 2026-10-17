#import "DXSystemOpenBroker.h"

typedef NSProgress *(^DXPanelControlRequester)(NSString *action, NSNumber *value, DXPanelSystemControlReply reply);
@interface DXPanelControlSession : NSObject
@property(nonatomic, readonly) BOOL busy;
- (instancetype)initWithRequester:(DXPanelControlRequester)requester validity:(BOOL (^)(void))validity
                           update:(void (^)(DXSystemOpenResult result, NSDictionary *state, BOOL busy, NSString *action))update;
- (void)enqueueAction:(NSString *)action value:(NSNumber *)value;
- (void)invalidate;
@end
