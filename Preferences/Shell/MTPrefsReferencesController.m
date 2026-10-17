#import "MTPrefsReferencesController.h"
#import "MTSharedResourceStore.h"
#import "MTSharedResourceIDs.h"

static NSString *MTReferencesString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSDictionary *MTReferencesDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

@implementation MTPrefsReferencesController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"引用管理";
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *specs = [NSMutableArray array];

    NSDictionary *snapshot = [MTSharedResourceStore readSnapshot];
    NSArray *actions = [snapshot[@"actions"] isKindOfClass:NSArray.class] ? snapshot[@"actions"] : @[];
    NSArray *panels = [snapshot[@"panels"] isKindOfClass:NSArray.class] ? snapshot[@"panels"] : @[];
    NSArray *bindings = [snapshot[@"bindings"] isKindOfClass:NSArray.class] ? snapshot[@"bindings"] : @[];

    // 资源 UUID → 引用位置列表（绑定 + 面板内条目）。
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *references = [NSMutableDictionary dictionary];
    for (NSDictionary *binding in bindings) {
        NSDictionary *target = MTReferencesDictionary(binding[@"target"]);
        NSString *kind = MTReferencesString(target[@"kind"]);
        if (![kind isEqual:MTSharedTargetKindAction] && ![kind isEqual:MTSharedTargetKindPanel]) continue;
        NSString *uuid = MTReferencesString(target[@"id"]);
        if (!uuid.length) continue;
        if (!references[uuid]) references[uuid] = [NSMutableArray array];
        [references[uuid] addObject:[NSString stringWithFormat:@"入口 · %@", MTReferencesString(binding[@"id"])]];
    }
    for (NSDictionary *panel in panels) {
        NSString *panelUUID = MTReferencesString(panel[@"id"]);
        NSString *panelName = MTReferencesString(panel[@"name"]);
        NSArray *items = [panel[@"items"] isKindOfClass:NSArray.class] ? panel[@"items"] : @[];
        for (NSDictionary *item in items) {
            NSDictionary *target = MTReferencesDictionary(item[@"target"]);
            NSString *kind = MTReferencesString(target[@"kind"]);
            if (![kind isEqual:MTSharedTargetKindAction] && ![kind isEqual:MTSharedTargetKindPanel]) continue;
            NSString *uuid = MTReferencesString(target[@"id"]);
            if (!uuid.length) continue;
            if (!references[uuid]) references[uuid] = [NSMutableArray array];
            [references[uuid] addObject:[NSString stringWithFormat:@"面板 · %@", panelName.length ? panelName : panelUUID]];
        }
    }

    void (^emit)(NSArray *, NSString *) = ^(NSArray *resources, NSString *kindTitle) {
        for (NSDictionary *resource in resources) {
            NSString *uuid = MTReferencesString(resource[@"id"]);
            if (!uuid.length) continue;
            NSString *name;
            if ([kindTitle isEqual:@"动作"]) {
                name = MTReferencesString(MTReferencesDictionary(resource[@"entry"])[@"name"]);
            } else {
                name = MTReferencesString(resource[@"name"]);
            }
            if (!name.length) name = @"未命名";
            PSSpecifier *group = [PSSpecifier groupSpecifierWithName:
                [NSString stringWithFormat:@"%@ · %@", kindTitle, name]];
            NSArray *locations = references[uuid];
            if (!locations.count) {
                PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:@"未被引用"
                    target:self set:nil get:nil detail:nil cell:PSTitleValueCell edit:nil];
                [group setProperty:@"未被引用的动作可以安全删除。" forKey:@"footerText"];
                [specs addObject:group];
                [specs addObject:row];
            } else {
                [group setProperty:[NSString stringWithFormat:@"被 %lu 处引用：%@",
                    (unsigned long)locations.count, [locations componentsJoinedByString:@"、"]]
                    forKey:@"footerText"];
                [specs addObject:group];
                for (NSString *location in locations) {
                    PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:location
                        target:self set:nil get:nil detail:nil cell:PSTitleValueCell edit:nil];
                    [specs addObject:row];
                }
            }
        }
    };
    emit(actions, @"动作");
    emit(panels, @"面板");

    if (!specs.count) {
        PSSpecifier *empty = [PSSpecifier groupSpecifierWithName:nil];
        [empty setProperty:@"共享库里还没有动作或面板。在全局分类里创建后，这里会显示反向引用。" forKey:@"footerText"];
        [specs addObject:empty];
    }
    _specifiers = specs;
    return _specifiers;
}

@end
