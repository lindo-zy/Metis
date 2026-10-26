//
//  MTCaptureRulesController.h
//  Mt
//

#import <Preferences/PSViewController.h>

NS_ASSUME_NONNULL_BEGIN

// 剪切板规则管理：双击采集气泡 / 复制后自动执行时按 JS 规则分流动作。
// 规则存共享资源文档顶层键 clipboardRules，读写走 MTClipboardActionReferences。
@interface MTCaptureRulesController : PSViewController
@end

NS_ASSUME_NONNULL_END
