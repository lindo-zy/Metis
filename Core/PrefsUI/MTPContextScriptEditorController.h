#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 底栏 JS 规则的全屏脚本编辑器：行号、实时着色、字节预算、语法状态、符号工具条。
// 保存是显式事务——只有「完成」才回调；校验失败不清空、也不自动停用规则。
@interface MTPContextScriptEditorController : UIViewController

@property (nonatomic, copy) NSString *source;
// 规则所属上下文组与类型标识，仅用于把 AI 页的调试台接到同一条判定链路上。
@property (nonatomic, copy, nullable) NSString *groupKey;
@property (nonatomic, copy, nullable) NSString *typeID;
@property (nonatomic, copy, nullable) void (^completion)(NSString *source);

@end

NS_ASSUME_NONNULL_END
