#import <Foundation/Foundation.h>

@interface DXServer : NSObject{
    CPDistributedMessagingCenter * _messagingCenter;
}
+ (instancetype)sharedInstance;
-(NSDictionary *)runCommand:(NSString *)name withUserInfo:(NSDictionary *)userInfo;
@end
