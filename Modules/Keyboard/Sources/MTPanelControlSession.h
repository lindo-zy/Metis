#import "MTSystemOpenBroker.h"

typedef NSProgress *(^MTPanelControlRequester)(NSString *action, NSNumber *value, MTPanelSystemControlReply reply);
@interface MTPanelControlSession : NSObject
@property(nonatomic, readonly) BOOL busy;
- (instancetype)initWithRequester:(MTPanelControlRequester)requester validity:(BOOL (^)(void))validity
                           update:(void (^)(MTSystemOpenResult result, NSDictionary *state, BOOL busy, NSString *action))update;
- (void)enqueueAction:(NSString *)action value:(NSNumber *)value;
- (void)invalidate;
@end
