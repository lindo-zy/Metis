#import <Foundation/Foundation.h>

@interface MTServer : NSObject{
    CPDistributedMessagingCenter * _messagingCenter;
}
+ (instancetype)sharedInstance;
-(NSDictionary *)runCommand:(NSString *)name withUserInfo:(NSDictionary *)userInfo;
@end
