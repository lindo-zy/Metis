#import "MTSettingsSpecifierBridge.h"

NSMutableArray<PSSpecifier *> *MTSettingsBuildSpecifiers(
    MTSettingsPageModel *model, id target, BOOL exposeIdentifiers,
    Class (^resolveDetail)(MTSettingsRow *row)) {
    NSMutableArray *specifiers = [NSMutableArray array];
    for (MTSettingsSection *section in model.sections) {
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:section.headerTitle];
        if (section.footerText) [group setProperty:section.footerText forKey:@"footerText"];
        [specifiers addObject:group];
        for (MTSettingsRow *row in section.rows) {
            Class detail = resolveDetail(row);
            PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:row.title target:target
                set:row.kind == MTSettingsRowKindToggle ? NSSelectorFromString(@"mtSetRowValue:specifier:") : NULL
                get:NSSelectorFromString(@"mtReadRowValue:") detail:detail
                cell:detail ? PSLinkCell : PSTitleValueCell edit:Nil];
            // 搜索结果的临时序号不是可重放路径，不暴露给路径查找工具。
            if (exposeIdentifiers) specifier.identifier = row.identifier;
            [specifiers addObject:specifier];
        }
    }
    return specifiers;
}
