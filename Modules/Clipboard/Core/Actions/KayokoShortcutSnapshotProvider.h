//
//  KayokoShortcutSnapshotProvider.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// SpringBoard side of the shortcut catalogue. Handles refresh requests from
// the preferences bundle by replacing the shared snapshot, and resolves
// shortcut activations for typed actions.
@interface KayokoShortcutSnapshotProvider : NSObject

+ (void)installObserver;

// Reads the pending refresh request from the shared domain, rebuilds the
// snapshot and deduplicates by request ID.
+ (void)handleRefreshRequest;

// Resolves the app's current item for shortcutType and activates it exactly
// like a home-screen long-press tap.
+ (void)activateShortcutWithType:(NSString *)shortcutType
            forBundleIdentifier:(NSString *)bundleIdentifier;

@end

NS_ASSUME_NONNULL_END
