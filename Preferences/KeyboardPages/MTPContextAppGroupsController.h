#import <Preferences/PSViewController.h>

// 应用动作组列表：组名 + 绑定的 App + 动作数 + 启用开关。
// 每组一份动作序列，运行时占用底栏预留区；未绑定的 App 沿用原有动作组。
@interface MTPContextAppGroupsController : PSViewController
@end
