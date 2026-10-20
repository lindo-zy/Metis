#import "MTDarwinOpenChannel.h"
#import <UIKit/UIKit.h>

FOUNDATION_EXPORT BOOL MTSystemExitActionAvailable(NSString *action);
FOUNDATION_EXPORT MTSystemOpenResult MTPerformSystemAction(NSString *action);
FOUNDATION_EXPORT void MTPerformSystemRecordingAction(NSString *action, MTSystemOpenReply reply);
// preferred 必须是调用方自己所在、且确定可交互的控制器（例如剪贴板浮窗里的 self）。
// 传 nil 表示调用方跨进程、无法指定宿主，由执行器自行挑选可承载模态的窗口。
FOUNDATION_EXPORT BOOL MTConfirmSystemExitActionFrom(NSString *action, NSProgress *operation,
                                                     UIViewController *preferred);
FOUNDATION_EXPORT BOOL MTConfirmSystemExitAction(NSString *action, NSProgress *operation);
FOUNDATION_EXPORT void MTCancelSystemActionConfirmation(void);
FOUNDATION_EXPORT NSDictionary *MTReadPanelSystemControlState(void);
FOUNDATION_EXPORT MTSystemOpenResult MTPerformPanelSystemControl(NSString *action, NSNumber *value);
