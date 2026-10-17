//
//  MTShortcutCatalog.h
//  Mt
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Settings and SpringBoard exchange quick-action data through an isolated
// CFPreferences domain plus two Darwin notifications. The preferences side
// writes a refresh request; SpringBoard (the only process that can resolve
// every app's real long-press menu) replaces the snapshot as one generation.
extern NSString *const kMTShortcutDarwinNotificationRefreshRequest;
extern NSString *const kMTShortcutDarwinNotificationSnapshotChanged;

@interface MTShortcutItem : NSObject

@property(nonatomic, copy) NSString *type;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy, nullable) NSString *subtitle;
// YES when the item came from the app's dynamic list.
@property(nonatomic, assign, getter=isDynamic) BOOL dynamic;

@end

@interface MTShortcutCatalog : NSObject

// The raw snapshot authored by SpringBoard: bundleID -> {name, items}.
+ (NSDictionary<NSString *, NSDictionary *> *)snapshotGroups;

// Display-ready groups sorted by app name; each group is
// {name, bundleID, items: NSArray<MTShortcutItem *>}.
+ (NSArray<NSDictionary *> *)displayGroups;

// Writes {format, requestID, bundles} into the shared domain and posts the
// refresh Darwin notification for SpringBoard.
+ (void)requestSnapshotRefreshForBundleIdentifiers:(nullable NSArray<NSString *> *)bundleIdentifiers;

// Writes {format, generation, updated, apps} into the shared domain and posts
// the changed Darwin notification. SpringBoard side only.
+ (void)storeSnapshotWithApps:(NSDictionary<NSString *, NSDictionary *> *)apps
                    requestID:(NSString *)requestID;

+ (nullable NSString *)readRefreshRequestID;
+ (NSDictionary *)readRefreshRequest;

@end

NS_ASSUME_NONNULL_END
