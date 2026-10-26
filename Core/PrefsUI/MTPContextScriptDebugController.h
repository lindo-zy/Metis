#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 底栏 JS 规则的沙盒调试台：样例文本 → 键盘进程同款分类器 → 命中结果 + console 日志。
// 与自定义动作的 MTPJavaScriptTestController 分开：那边的运行时是 MTJavaScriptEngine
// （可联网、可返回动作），这里的运行时是 MTContextClassifier（纯判定、50 ms 限时）。
@interface MTPContextScriptDebugController : UIViewController

@property (nonatomic, copy) NSString *source;
// 规则所属上下文组与类型标识；为空时隐藏「实际生效」区块。
@property (nonatomic, copy, nullable) NSString *groupKey;
@property (nonatomic, copy, nullable) NSString *typeID;
@property (nonatomic, copy, nullable) NSString *sampleText;

@end

NS_ASSUME_NONNULL_END
