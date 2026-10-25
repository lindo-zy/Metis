#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface MTPAIScriptChatController : UIViewController
@property (nonatomic, copy) NSString *currentScript;
@property (nonatomic, copy, nullable) void (^completion)(NSString *script);
@end
NS_ASSUME_NONNULL_END
