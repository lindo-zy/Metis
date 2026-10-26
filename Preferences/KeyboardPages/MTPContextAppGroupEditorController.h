#import <Preferences/PSViewController.h>

// 单个应用动作组：改名、换绑 App、增删与排序动作。
// 预留区格数只决定「显示几格」，多出来的动作保留但不显示。
@interface MTPContextAppGroupEditorController : PSViewController
- (instancetype)initWithGroupIdentifier:(NSString *)identifier;
@end
