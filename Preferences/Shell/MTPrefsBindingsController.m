#import "MTPrefsBindingsController.h"
#import "MTPrefsSubbundleLoader.h"
#import "MTSharedResourceStore.h"
#import "MTSharedResourceIDs.h"
#import "MTLog.h"

static NSString *MTBindingsString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSDictionary *MTBindingsDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

@implementation MTPrefsBindingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"入口绑定";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 资源可能刚在编辑页被修改：重进总览时刷新（02 §7 重新校验）。
    @try {
        [self reloadSpecifiers];
    } @catch (__unused NSException *exception) {
    }
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *specs = [NSMutableArray array];

    NSDictionary *snapshot = [MTSharedResourceStore readSnapshot];
    // id → 显示名（动作名 / 面板名）。
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
    for (id raw in [snapshot[@"actions"] isKindOfClass:NSArray.class] ? snapshot[@"actions"] : @[]) {
        NSDictionary *action = MTBindingsDictionary(raw);
        NSString *uuid = MTBindingsString(action[@"id"]);
        NSString *name = MTBindingsString(MTBindingsDictionary(action[@"entry"])[@"name"]);
        if (uuid.length) names[uuid] = name.length ? name : @"未命名动作";
    }
    for (id raw in [snapshot[@"panels"] isKindOfClass:NSArray.class] ? snapshot[@"panels"] : @[]) {
        NSDictionary *panel = MTBindingsDictionary(raw);
        NSString *uuid = MTBindingsString(panel[@"id"]);
        NSString *name = MTBindingsString(panel[@"name"]);
        if (uuid.length) names[uuid] = name.length ? name : @"未命名面板";
    }

    NSArray *bindings = [snapshot[@"bindings"] isKindOfClass:NSArray.class] ? snapshot[@"bindings"] : @[];
    // 按 source 分组：keyboard / gesture / 其他来源各自成组。
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *groups = [NSMutableDictionary dictionary];
    for (id raw in bindings) {
        NSDictionary *binding = MTBindingsDictionary(raw);
        if (!binding) continue;
        NSString *source = MTBindingsString(binding[@"source"]);
        if (!source.length) continue;
        if (!groups[source]) groups[source] = [NSMutableArray array];
        [groups[source] addObject:binding];
    }

    NSDictionary<NSString *, NSString *> *sourceTitles = @{
        @"keyboard": @"键盘", @"gesture": @"全局手势", @"clipboard": @"剪切板",
        @"capture": @"截图", @"other": @"其他",
    };
    for (NSString *source in @[@"keyboard", @"gesture", @"clipboard", @"capture", @"other"]) {
        NSArray *rows = groups[source];
        if (!rows.count) continue;
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:sourceTitles[source] ?: source];
        [specs addObject:group];
        for (NSDictionary *binding in rows) {
            NSDictionary *target = MTBindingsDictionary(binding[@"target"]);
            NSString *kind = MTBindingsString(target[@"kind"]);
            NSString *targetName;
            if ([kind isEqual:MTSharedTargetKindAction] || [kind isEqual:MTSharedTargetKindPanel]) {
                targetName = names[MTBindingsString(target[@"id"])] ?: @"目标已删除";
            } else if ([kind isEqual:MTSharedTargetKindBuiltin]) {
                targetName = @"内置能力";
            } else {
                targetName = @"未绑定";
            }
            // 绑定编辑入口：键盘槽位 → 键盘子包手势/工具栏页；手势槽位 → Dock/状态栏页。
            PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:MTBindingsString(binding[@"id"])
                target:self
                set:@selector(mtNoopSetter:forSpecifier:)
                get:@selector(mtTargetName:)
                detail:nil
                cell:PSLinkCell
                edit:nil];
            [row setProperty:targetName forKey:@"metis-target-name"];
            [row setProperty:[self mtEditorForBindingID:MTBindingsString(binding[@"id"])]
                      forKey:@"metis-editor"];
            row->action = @selector(openEditor:);
            [specs addObject:row];
        }
    }

    if (!specs.count) {
        PSSpecifier *empty = [PSSpecifier groupSpecifierWithName:nil];
        [empty setProperty:@"还没有入口绑定。在键盘或手势设置中选择动作或面板后，会在这里显示。" forKey:@"footerText"];
        [specs addObject:empty];
    } else {
        PSSpecifier *footer = [PSSpecifier groupSpecifierWithName:nil];
        [footer setProperty:@"绑定在各自分类页面编辑；这里与那些页面读写同一份配置。" forKey:@"footerText"];
        [specs addObject:footer];
    }
    _specifiers = specs;
    return _specifiers;
}

// 已知槽位 → 编辑页（子包内控制器）。新增入口时在此登记。
- (NSDictionary *)mtEditorForBindingID:(NSString *)bindingID {
    if ([bindingID hasPrefix:@"keyboard.toolbar."]) {
        return @{@"bundle": @"MetisKeyboardPrefs", @"class": @"MTPGestureSettingsController"};
    }
    if ([bindingID hasPrefix:@"gesture.dock."]) {
        return @{@"bundle": @"MetisKeyboardPrefs", @"class": @"MTPDockGestureController"};
    }
    if ([bindingID hasPrefix:@"gesture.statusbar."]) {
        return @{@"bundle": @"MetisKeyboardPrefs", @"class": @"MTPStatusBarGestureController"};
    }
    return @{};
}

- (NSString *)mtTargetName:(PSSpecifier *)specifier {
    return [specifier propertyForKey:@"metis-target-name"];
}

- (void)mtNoopSetter:(id)value forSpecifier:(PSSpecifier *)specifier {
    (void)value; (void)specifier;
}

- (void)openEditor:(PSSpecifier *)specifier {
    NSDictionary *editor = [specifier propertyForKey:@"metis-editor"];
    NSString *bundleName = MTBindingsString(editor[@"bundle"]);
    NSString *className = MTBindingsString(editor[@"class"]);
    if (!bundleName.length) return; // 该入口暂无独立编辑页（总览只读）。
    NSError *error = nil;
    Class controllerClass = [MTPrefsSubbundleLoader loadControllerClassFromBundle:bundleName
                                                                       classNamed:className
                                                                            error:&error];
    if (!controllerClass) {
        MTLogError(MTLogModulePrefs, @"state=binding-editor-load-failed bundle=%@ error=%@",
                   bundleName, error.localizedDescription);
        return;
    }
    id controller = [[controllerClass alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
