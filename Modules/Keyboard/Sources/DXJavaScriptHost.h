#import <UIKit/UIKit.h>

// Host-facing adapter. All methods and callbacks run on main. A single active
// session per process prevents top/bottom toolbar requests racing each other.
@interface DXJavaScriptHost : NSObject
+ (void)cancelActive;
+ (void)startEntry:(NSDictionary *)entry sourceView:(UIView *)view
    inputProvider:(id (^)(void))provider
             open:(void (^)(NSString *type, NSString *content))open
            error:(void (^)(NSString *message))error;
@end
