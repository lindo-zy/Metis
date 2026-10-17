#import "MTPrefsDefaultsController.h"

@implementation MTPrefsDefaultsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"默认行为";
}

// 行元组：[类型, 标题, 说明]；group 行说明位为 NSNull（数组字面量不可含 nil）。
// 说明须与执行链路当前真实行为一致（02 §2/§7）。
- (NSArray *)mtDefaultRows {
    return @[
        @[@"group", @"共用呈现", NSNull.null],
        @[@"row",   @"动作与面板", @"所有入口打开同一份全局定义的内容与外观"],
        @[@"row",   @"面板与触发", @"面板内容由全局定义；触发位置属于入口绑定"],
        @[@"group", @"缺少上下文时", NSNull.null],
        @[@"row",   @"缺少可用文本", @"提示选择内容后重试，不自动改用其他来源"],
        @[@"row",   @"需要输入框", @"替换类操作直接失败并提示，不写入其他应用"],
        @[@"row",   @"服务不可用", @"显示原因并停留在当前界面，不留下空遮罩"],
        @[@"row",   @"删除的目标", @"显示「目标已删除」，可重选或清除，不指向同名新资源"],
        @[@"group", @"JavaScript 脚本", NSNull.null],
        @[@"row",   @"无输入框会话", @"按能力放行：剪切板文本输入，copy 模式输出"],
    ];
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *specs = [NSMutableArray array];
    for (NSArray *item in [self mtDefaultRows]) {
        if ([item[0] isEqual:@"group"]) {
            [specs addObject:[PSSpecifier groupSpecifierWithName:item[1]]];
        } else {
            PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:item[1]
                target:self
                set:@selector(mtNoopSetter:forSpecifier:)
                get:@selector(mtValueForSpecifier:)
                detail:nil
                cell:PSTitleValueCell
                edit:nil];
            [row setProperty:item[2] forKey:@"default"];
            [specs addObject:row];
        }
    }
    _specifiers = specs;
    return _specifiers;
}

- (NSString *)mtValueForSpecifier:(PSSpecifier *)specifier {
    return [specifier propertyForKey:@"default"];
}

- (void)mtNoopSetter:(id)value forSpecifier:(PSSpecifier *)specifier {
    (void)value; (void)specifier;
}

@end
