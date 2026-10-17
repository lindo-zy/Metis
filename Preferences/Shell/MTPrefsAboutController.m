#import "MTPrefsAboutController.h"
#import "MTCore.h"

@implementation MTPrefsAboutController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *version = [PSSpecifier preferenceSpecifierNamed:@"版本"
            target:self
            set:@selector(mtNoop:forSpecifier:)
            get:@selector(mtVersionText:)
            detail:nil
            cell:PSTitleValueCell
            edit:nil];
        [specs addObject:version];

        PSSpecifier *modules = [PSSpecifier preferenceSpecifierNamed:@"内置模块"
            target:self
            set:@selector(mtNoop:forSpecifier:)
            get:@selector(mtModulesText:)
            detail:nil
            cell:PSTitleValueCell
            edit:nil];
        [specs addObject:modules];

        PSSpecifier *licenseGroup = [PSSpecifier groupSpecifierWithName:@"开源许可"];
        [specs addObject:licenseGroup];

        PSSpecifier *license = [PSSpecifier preferenceSpecifierNamed:@"许可来源"
            target:self
            set:@selector(mtNoop:forSpecifier:)
            get:@selector(mtLicenseText:)
            detail:nil
            cell:PSTitleValueCell
            edit:nil];
        [specs addObject:license];

        _specifiers = specs;
    }
    return _specifiers;
}

- (NSString *)mtVersionText:(PSSpecifier *)specifier {
    (void)specifier;
    return MTCoreVersionString;
}

- (NSString *)mtModulesText:(PSSpecifier *)specifier {
    (void)specifier;
    return @"截图与标注\n键盘与操作\n剪贴板";
}

- (NSString *)mtLicenseText:(PSSpecifier *)specifier {
    (void)specifier;
    return @"完整许可与来源清单见包内 /usr/share/doc/com.lindo.metis/LICENSE-NOTICE。";
}

- (void)mtNoop:(id)value forSpecifier:(PSSpecifier *)specifier {
    (void)value; (void)specifier;
}

@end
