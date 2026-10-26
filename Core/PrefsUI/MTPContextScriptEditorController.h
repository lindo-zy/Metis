#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MTPAIScriptProfile;

// JS 规则与自定义动作共用的全屏编辑器：行号、着色、容量、语法状态、沙盒调试入口。
// 保存是显式事务——只有「保存」才回调；校验失败不清空、也不自动停用规则。
@interface MTPContextScriptEditorController : UIViewController

@property (nonatomic, copy) NSString *source;
// 未指定时沿用 JS 规则契约；自定义动作传 actionProfile。
@property (nonatomic, strong, nullable) MTPAIScriptProfile *profile;
// 规则所属上下文组与类型标识，仅用于把 AI 页的调试台接到同一条判定链路上。
@property (nonatomic, copy, nullable) NSString *groupKey;
@property (nonatomic, copy, nullable) NSString *typeID;
@property (nonatomic, copy, nullable) void (^completion)(NSString *source);

@end

NS_ASSUME_NONNULL_END
