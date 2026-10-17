//
//  KayokoCustomJump.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kKayokoCustomJumpDictionaryKeyUUID;
extern NSString *const kKayokoCustomJumpDictionaryKeyTitle;
extern NSString *const kKayokoCustomJumpDictionaryKeyLink;
extern NSString *const kKayokoCustomJumpDictionaryKeyIcon;
extern NSString *const kKayokoCustomJumpDictionaryKeyType;
extern NSString *const kKayokoCustomJumpDictionaryKeyShortcutType;
extern NSString *const kKayokoCustomJumpDefaultIconName;

// Typed actions. Entries stored before typed actions existed carry no type
// and keep their legacy editor and URL-opening behavior.
extern NSString *const kKayokoCustomJumpTypeURLScheme;
extern NSString *const kKayokoCustomJumpTypeOpenApp;
extern NSString *const kKayokoCustomJumpTypeShortcut;

@interface KayokoCustomJump : NSObject <NSCopying>

@property(nonatomic, copy) NSString *uuid;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *link;
@property(nonatomic, copy) NSString *icon;
// nil for legacy entries. openapp stores the target bundle identifier in
// link; shortcut stores the owning app's bundle identifier in link and the
// UIApplicationShortcutItemType in shortcutType.
@property(nonatomic, copy, nullable) NSString *type;
@property(nonatomic, copy, nullable) NSString *shortcutType;

- (instancetype)initWithUUID:(NSString *)uuid
                        title:(NSString *)title
                         link:(NSString *)link
                         icon:(nullable NSString *)icon;
- (instancetype)initWithUUID:(NSString *)uuid
                        title:(NSString *)title
                         link:(NSString *)link
                         icon:(nullable NSString *)icon
                         type:(nullable NSString *)type
                 shortcutType:(nullable NSString *)shortcutType NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithUUID:(NSString *)uuid
                        title:(NSString *)title
                         link:(NSString *)link;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)jumpWithTitle:(NSString *)title link:(NSString *)link;
+ (instancetype)jumpWithTitle:(NSString *)title
                         link:(NSString *)link
                         type:(nullable NSString *)type;
+ (nullable instancetype)jumpWithDictionary:(NSDictionary<NSString *, id> *)dictionary;

- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
