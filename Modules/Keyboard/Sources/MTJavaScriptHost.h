#import <UIKit/UIKit.h>

// Host-facing adapter. All methods and callbacks run on main. A single active
// session per process prevents top/bottom toolbar requests racing each other.
@interface MTJavaScriptHost : NSObject
+ (void)cancelActive;
+ (void)startEntry:(NSDictionary *)entry sourceView:(UIView *)view
    inputProvider:(id (^)(void))provider
             open:(void (^)(NSString *type, NSString *content))open
            error:(void (^)(NSString *message))error;
// 无输入框入口（全局面板/手势）：jsInput=clipboard + jsOutput=copy 专用；
// 输入来自系统剪切板并受 changeCount 保护，输出 copy 不需要输入会话。
+ (void)startSessionlessEntry:(NSDictionary *)entry
                         open:(void (^)(NSString *type, NSString *content))open
                        error:(void (^)(NSString *message))error;
@end
