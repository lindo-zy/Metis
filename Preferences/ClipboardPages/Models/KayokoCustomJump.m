//
//  KayokoCustomJump.m
//  Kayoko
//

#import "KayokoCustomJump.h"

NSString *const kKayokoCustomJumpDictionaryKeyUUID = @"uuid";
NSString *const kKayokoCustomJumpDictionaryKeyTitle = @"title";
NSString *const kKayokoCustomJumpDictionaryKeyLink = @"link";
NSString *const kKayokoCustomJumpDictionaryKeyIcon = @"icon";
NSString *const kKayokoCustomJumpDictionaryKeyType = @"type";
NSString *const kKayokoCustomJumpDictionaryKeyShortcutType = @"shortcuttype";
NSString *const kKayokoCustomJumpDefaultIconName = @"link";

NSString *const kKayokoCustomJumpTypeURLScheme = @"urlscheme";
NSString *const kKayokoCustomJumpTypeOpenApp = @"openapp";
NSString *const kKayokoCustomJumpTypeShortcut = @"shortcut";

@implementation KayokoCustomJump

- (instancetype)initWithUUID:(NSString *)uuid
                        title:(NSString *)title
                         link:(NSString *)link
                         icon:(NSString *)icon {
    return [self initWithUUID:uuid title:title link:link icon:icon type:nil shortcutType:nil];
}

- (instancetype)initWithUUID:(NSString *)uuid
                        title:(NSString *)title
                         link:(NSString *)link
                         icon:(NSString *)icon
                         type:(NSString *)type
                 shortcutType:(NSString *)shortcutType {
    self = [super init];
    if (self) {
        _uuid = [([uuid length] > 0 ? uuid : [[NSUUID UUID] UUIDString]) copy];
        _title = [(title ?: @"") copy];
        _link = [(link ?: @"") copy];
        _icon = [([icon length] > 0 ? icon : kKayokoCustomJumpDefaultIconName) copy];
        _type = [([type length] > 0 ? type : nil) copy];
        _shortcutType = [([shortcutType length] > 0 ? shortcutType : nil) copy];
    }
    return self;
}

- (instancetype)initWithUUID:(NSString *)uuid title:(NSString *)title link:(NSString *)link {
    return [self initWithUUID:uuid title:title link:link icon:nil];
}

+ (instancetype)jumpWithTitle:(NSString *)title link:(NSString *)link {
    return [[self alloc] initWithUUID:[[NSUUID UUID] UUIDString] title:title link:link];
}

+ (instancetype)jumpWithTitle:(NSString *)title link:(NSString *)link type:(NSString *)type {
    return [[self alloc] initWithUUID:[[NSUUID UUID] UUIDString] title:title link:link icon:nil type:type shortcutType:nil];
}

+ (instancetype)jumpWithDictionary:(NSDictionary<NSString *, id> *)dictionary {
    id uuid = dictionary[kKayokoCustomJumpDictionaryKeyUUID];
    id title = dictionary[kKayokoCustomJumpDictionaryKeyTitle];
    id link = dictionary[kKayokoCustomJumpDictionaryKeyLink];
    id icon = dictionary[kKayokoCustomJumpDictionaryKeyIcon];
    id type = dictionary[kKayokoCustomJumpDictionaryKeyType];
    id shortcutType = dictionary[kKayokoCustomJumpDictionaryKeyShortcutType];
    if (![uuid isKindOfClass:[NSString class]] || ![title isKindOfClass:[NSString class]] ||
        ![link isKindOfClass:[NSString class]] || [uuid length] == 0) {
        return nil;
    }

    return [[self alloc] initWithUUID:uuid
                                title:title
                                 link:link
                                 icon:[icon isKindOfClass:[NSString class]] ? icon : nil
                                 type:[type isKindOfClass:[NSString class]] ? type : nil
                         shortcutType:[shortcutType isKindOfClass:[NSString class]] ? shortcutType : nil];
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary<NSString *, id> *dictionary = [@{
        kKayokoCustomJumpDictionaryKeyUUID : [self uuid] ?: @"",
        kKayokoCustomJumpDictionaryKeyTitle : [self title] ?: @"",
        kKayokoCustomJumpDictionaryKeyLink : [self link] ?: @"",
        kKayokoCustomJumpDictionaryKeyIcon : [self icon] ?: kKayokoCustomJumpDefaultIconName
    } mutableCopy];
    // Legacy entries stay keyless so they keep their legacy editor and URL
    // behavior even after a round-trip through the store.
    if ([self type] != nil) {
        dictionary[kKayokoCustomJumpDictionaryKeyType] = [self type];
    }
    if ([self shortcutType] != nil) {
        dictionary[kKayokoCustomJumpDictionaryKeyShortcutType] = [self shortcutType];
    }
    return [dictionary copy];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithUUID:[self uuid]
                                                     title:[self title]
                                                      link:[self link]
                                                      icon:[self icon]
                                                      type:[self type]
                                              shortcutType:[self shortcutType]];
}

@end
