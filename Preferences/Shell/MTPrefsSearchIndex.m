#import "MTPrefsSearchIndex.h"
#import "MTPrefsRootModel.h"
#import "MTPrefsGlobalModel.h"
#import "MTSharedResourceStore.h"

// 动作类型字面量与显示名（store schema v1 校验过的六类型 + legacy url）。
// Shell 不链接键盘子包头文件，此处按 MTSharedResourceValidator 白名单固定。
static NSDictionary *MTSearchActionTypeLabels(void) {
    return @{
        @"urlscheme":  @"URL Scheme",
        @"url":        @"URL Scheme",
        @"text":       @"文本",
        @"openapp":    @"打开应用",
        @"shortcut":   @"应用快捷方式",
        @"system":     @"系统动作",
        @"javascript": @"JavaScript 脚本",
    };
}

@implementation MTSettingsSearchEntry
@end

@implementation MTPrefsSearchIndex

+ (NSArray<MTSettingsSearchEntry *> *)staticEntries {
    NSMutableArray<MTSettingsSearchEntry *> *entries = [NSMutableArray array];

    void (^add)(NSString *, NSString *, MTSettingsRow *) = ^(NSString *title, NSString *path, MTSettingsRow *target) {
        MTSettingsSearchEntry *entry = [[MTSettingsSearchEntry alloc] init];
        entry.title = title;
        entry.path = path;
        entry.target = target;
        [entries addObject:entry];
    };

    // 首页范围：命中项留在首页原地强调（InPage 路由携带目标行 identifier）。
    MTSettingsRow *toggle = [MTSettingsRow linkRowWithIdentifier:@"search-root-toggle" title:@"启用 Metis"];
    toggle.routeKind = MTSettingsRouteInPage;
    toggle.userInfo = @"global-enabled";
    add(@"启用 Metis", @"首页", toggle);

    for (MTSettingsRow *category in [MTPrefsRootModel categoryRows]) {
        MTSettingsRow *target = [MTSettingsRow linkRowWithIdentifier:category.identifier title:category.title];
        target.routeKind = MTSettingsRouteInPage;
        target.userInfo = category.identifier;
        add(category.title, @"首页", target);
    }

    // 「关于 Metis」页已移除（2026-10-17 需求），首页索引不再收录该条目。

    // 全局分类范围：压栈到全局页并强调目标行。
    for (MTSettingsSection *section in [MTPrefsGlobalModel globalPageModel].sections) {
        for (MTSettingsRow *row in section.rows) {
            MTSettingsRow *target = [MTSettingsRow linkRowWithIdentifier:row.identifier title:row.title];
            target.routeKind = MTSettingsRouteShellClass;
            target.className = @"MTPrefsGlobalController";
            target.userInfo = row.identifier; // 压栈后的强调目标
            add(row.title, @"全局", target);
        }
    }

    // 其他分类范围：压栈到「其他」页（PS 页不支持行级强调，只做页面直达）。
    NSArray *otherTitles = @[@"Dock 手势", @"状态栏手势", @"悬浮应用", @"AI 问答", @"短信验证码自动复制", @"浏览器重定向"];
    for (NSString *title in otherTitles) {
        MTSettingsRow *target = [MTSettingsRow linkRowWithIdentifier:title title:title];
        target.routeKind = MTSettingsRouteShellClass;
        target.className = @"MTPrefsOtherController";
        add(title, @"其他", target);
    }

    return entries;
}

// 资源条目：名称/类型 → 对应管理页（子包）。快照读取失败按「无资源」处理。
+ (NSArray<MTSettingsSearchEntry *> *)resourceEntries {
    NSDictionary *snapshot = [MTSharedResourceStore readSnapshot];
    if (!snapshot) return @[];

    NSMutableArray<MTSettingsSearchEntry *> *entries = [NSMutableArray array];
    NSDictionary *typeLabels = MTSearchActionTypeLabels();
    for (id raw in [snapshot[@"actions"] isKindOfClass:NSArray.class] ? snapshot[@"actions"] : @[]) {
        if (![raw isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *actionEntry = raw[@"entry"];
        if (![actionEntry isKindOfClass:NSDictionary.class]) continue;
        NSString *name = [actionEntry[@"name"] isKindOfClass:NSString.class] ? actionEntry[@"name"] : @"";
        if (!name.length) continue;
        NSString *type = [actionEntry[@"type"] isKindOfClass:NSString.class] ? actionEntry[@"type"] : @"";
        NSString *typeLabel = typeLabels[type] ?: @"";
        MTSettingsRow *target = [MTSettingsRow linkRowWithIdentifier:name title:name];
        target.routeKind = MTSettingsRouteSubbundle;
        target.subBundle = @"MetisKeyboardPrefs";
        target.className = @"MTPCustomActionsController";
        target.userInfo = typeLabel;
        MTSettingsSearchEntry *entry = [[MTSettingsSearchEntry alloc] init];
        entry.title = name;
        entry.path = typeLabel.length
            ? [NSString stringWithFormat:@"全局 · 自定义动作 · %@", typeLabel]
            : @"全局 · 自定义动作";
        entry.target = target;
        [entries addObject:entry];
    }
    for (id raw in [snapshot[@"panels"] isKindOfClass:NSArray.class] ? snapshot[@"panels"] : @[]) {
        if (![raw isKindOfClass:NSDictionary.class]) continue;
        NSString *name = [raw[@"name"] isKindOfClass:NSString.class] ? raw[@"name"] : @"";
        if (!name.length) continue;
        MTSettingsRow *target = [MTSettingsRow linkRowWithIdentifier:name title:name];
        target.routeKind = MTSettingsRouteSubbundle;
        target.subBundle = @"MetisKeyboardPrefs";
        target.className = @"MTPKeyboardPanelController";
        MTSettingsSearchEntry *entry = [[MTSettingsSearchEntry alloc] init];
        entry.title = name;
        entry.path = @"全局 · 面板管理";
        entry.target = target;
        [entries addObject:entry];
    }
    return entries;
}

+ (NSArray<MTSettingsSearchEntry *> *)entriesMatchingQuery:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return @[];
    NSMutableArray<MTSettingsSearchEntry *> *matches = [NSMutableArray array];
    for (MTSettingsSearchEntry *entry in [self staticEntries]) {
        if ([entry.title localizedCaseInsensitiveContainsString:trimmed] ||
            [entry.path localizedCaseInsensitiveContainsString:trimmed]) {
            [matches addObject:entry];
        }
    }
    for (MTSettingsSearchEntry *entry in [self resourceEntries]) {
        if ([entry.title localizedCaseInsensitiveContainsString:trimmed] ||
            [entry.path localizedCaseInsensitiveContainsString:trimmed]) {
            [matches addObject:entry];
        }
    }
    return matches;
}

@end
