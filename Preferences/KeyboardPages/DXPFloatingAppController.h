#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface DXPFloatingAppController : PSListController
// 把手面板应用列表（kbdhandleapps）AltList 多选页的 get/set：读取规整成
// bundleID 数组；写入过滤后走标准域写入（自带 prefschanged 广播）。
- (id)dxp_handleAppsRead:(PSSpecifier *)specifier;
- (void)dxp_handleAppsWrite:(id)value specifier:(PSSpecifier *)specifier;
@end
