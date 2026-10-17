#import "MTSettingsModels.h"

@implementation MTSettingsRow

+ (instancetype)linkRowWithIdentifier:(NSString *)identifier title:(NSString *)title {
    MTSettingsRow *row = [[self alloc] init];
    row.identifier = identifier;
    row.title = title;
    row.kind = MTSettingsRowKindLink;
    return row;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ id=%@ title=%@ route=%ld>",
            NSStringFromClass(self.class), self.identifier, self.title, (long)self.routeKind];
}

@end

@implementation MTSettingsSection

+ (instancetype)sectionWithRows:(NSArray<MTSettingsRow *> *)rows {
    MTSettingsSection *section = [[self alloc] init];
    section.rows = rows ?: @[];
    return section;
}

@end

@implementation MTSettingsPageModel

- (MTSettingsRow *)rowWithIdentifier:(NSString *)identifier {
    if (!identifier.length) return nil;
    for (MTSettingsSection *section in self.sections) {
        for (MTSettingsRow *row in section.rows) {
            if ([row.identifier isEqualToString:identifier]) return row;
        }
    }
    return nil;
}

@end
