#import <Foundation/Foundation.h>
#import "DXDarwinOpenChannel.h"

NS_ASSUME_NONNULL_BEGIN

// SpringBoard-only source of truth for app icon quick actions. The Settings
// bundle supplies installed bundle identifiers; this provider resolves the
// corresponding SBApplication objects, reads their current static/dynamic
// shortcut items, and publishes one complete versioned snapshot.
@interface DXQuickActionProvider : NSObject

+ (void)refreshSnapshotForBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                                   requestID:(nullable NSString *)requestID;

// Re-resolves the current shortcut object immediately before activation so
// userInfo and other runtime payload stay intact. No synthetic item is created
// when the configured type no longer exists. Call on SpringBoard main queue;
// success reports invocation of the system entry, not completion inside the app.
+ (DXSystemOpenResult)activateShortcutWithBundleIdentifier:(NSString *)bundleIdentifier
                                        type:(NSString *)shortcutType;

@end

NS_ASSUME_NONNULL_END
