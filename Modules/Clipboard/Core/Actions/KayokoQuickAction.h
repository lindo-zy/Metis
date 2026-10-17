//
//  KayokoQuickAction.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, KayokoQuickActionKind) {
    KayokoQuickActionKindText,
    KayokoQuickActionKindImage,
};

@interface KayokoQuickAction : NSObject

// Loads the custom actions persisted by the Preferences bundle. Every type
// surfaces in the quick-action panels: legacy/urlscheme entries open a URL,
// openapp launches its app, shortcut activates the app's long-press item.
+ (NSArray<NSDictionary<NSString *, id> *> *)actionsForKind:(KayokoQuickActionKind)kind;
+ (void)openAction:(NSDictionary<NSString *, id> *)action
             input:(nullable NSString *)input
 completionHandler:(nullable void (^)(BOOL success))completionHandler;

@end

NS_ASSUME_NONNULL_END
