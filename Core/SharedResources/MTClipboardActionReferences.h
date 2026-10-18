#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Clipboard stores ordered bindings only. Action payloads always come from the global library.
@interface MTClipboardActionReferences : NSObject
+ (BOOL)supportsEntry:(NSDictionary *)entry;
+ (NSArray<NSDictionary *> *)actionsInDocument:(NSDictionary *)document slot:(NSString *)slot;
+ (NSDictionary *)document:(NSDictionary *)document settingActionIDs:(NSArray<NSString *> *)ids slot:(NSString *)slot;
+ (BOOL)setActionIDs:(NSArray<NSString *> *)ids slot:(NSString *)slot expectedRevision:(uint64_t)revision error:(NSError **)error;
// Settings-only one-time import. Existing legacy files remain as backups.
+ (NSDictionary *)document:(NSDictionary *)document importingText:(NSArray *)text image:(NSArray *)image doubleTapURL:(NSString *)url;
@end

NS_ASSUME_NONNULL_END
