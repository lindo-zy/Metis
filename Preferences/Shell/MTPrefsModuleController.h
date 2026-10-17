// MTPrefsModuleController —— 模块标准页（02-settings-ux §3）：
// 启用与状态在前，详细设置入口在后。子包未编入时显示“此版本尚未提供”。
#import <Preferences/Preferences.h>
#import "MTPrefsRootController.h"

@interface MTPrefsModuleController : PSListController
- (instancetype)initWithModuleInfo:(MTPrefsModuleInfo *)info;
+ (Class)classForModule:(NSString *)moduleID;
@end

@interface MTPrefsCaptureModuleController : MTPrefsModuleController @end
@interface MTPrefsKeyboardModuleController : MTPrefsModuleController @end
@interface MTPrefsClipboardModuleController : MTPrefsModuleController @end
