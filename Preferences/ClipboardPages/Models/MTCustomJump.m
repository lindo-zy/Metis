//
//  MTCustomJump.m
//  Mt
//

#import "MTCustomJump.h"

NSString *const kMTCustomJumpDictionaryKeyUUID = @"uuid";
NSString *const kMTCustomJumpDictionaryKeyTitle = @"title";
NSString *const kMTCustomJumpDictionaryKeyLink = @"link";
NSString *const kMTCustomJumpDictionaryKeyIcon = @"icon";
NSString *const kMTCustomJumpDictionaryKeyType = @"type";
NSString *const kMTCustomJumpDictionaryKeyShortcutType = @"shortcuttype";
NSString *const kMTCustomJumpDefaultIconName = @"link";

NSString *const kMTCustomJumpTypeURLScheme = @"urlscheme";
NSString *const kMTCustomJumpTypeOpenApp = @"openapp";
NSString *const kMTCustomJumpTypeShortcut = @"shortcut";

@implementation MTCustomJump

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
        _icon = [([icon length] > 0 ? icon : kMTCustomJumpDefaultIconName) copy];
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
    id uuid = dictionary[kMTCustomJumpDictionaryKeyUUID];
    id title = dictionary[kMTCustomJumpDictionaryKeyTitle];
    id link = dictionary[kMTCustomJumpDictionaryKeyLink];
    id icon = dictionary[kMTCustomJumpDictionaryKeyIcon];
    id type = dictionary[kMTCustomJumpDictionaryKeyType];
    id shortcutType = dictionary[kMTCustomJumpDictionaryKeyShortcutType];
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
        kMTCustomJumpDictionaryKeyUUID : [self uuid] ?: @"",
        kMTCustomJumpDictionaryKeyTitle : [self title] ?: @"",
        kMTCustomJumpDictionaryKeyLink : [self link] ?: @"",
        kMTCustomJumpDictionaryKeyIcon : [self icon] ?: kMTCustomJumpDefaultIconName
    } mutableCopy];
    // Legacy entries stay keyless so they keep their legacy editor and URL
    // behavior even after a round-trip through the store.
    if ([self type] != nil) {
        dictionary[kMTCustomJumpDictionaryKeyType] = [self type];
    }
    if ([self shortcutType] != nil) {
        dictionary[kMTCustomJumpDictionaryKeyShortcutType] = [self shortcutType];
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
