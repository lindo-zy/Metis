// MTPrefsBindingsController —— 入口绑定总览（02-settings-ux §2/§5）。
// 展示共享 store 中各入口当前绑定的动作/面板；编辑仍在各分类原页面进行，
// 两处编辑的是同一份 binding（store 唯一权威）。
#import <Preferences/Preferences.h>

@interface MTPrefsBindingsController : PSListController
@end
