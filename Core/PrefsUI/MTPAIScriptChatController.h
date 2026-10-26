#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MTPAIScriptProfile;

@interface MTPAIScriptChatController : UIViewController
@property (nonatomic, copy) NSString *currentScript;
// 目标脚本契约：决定 system prompt、预检规则与「直接调试」跳转到哪个调试台。
// 缺省为自定义动作的 main(str) 契约。
@property (nonatomic, strong, nullable) MTPAIScriptProfile *profile;
// 底栏规则才有：传给调试台，用来显示「实际生效」的判定结果。
@property (nonatomic, copy, nullable) NSString *groupKey;
@property (nonatomic, copy, nullable) NSString *typeID;
@property (nonatomic, copy, nullable) void (^completion)(NSString *script);
@end
NS_ASSUME_NONNULL_END
