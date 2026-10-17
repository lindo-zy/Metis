//
//  KayokoAppInfo.h
//  Kayoko
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// One installed application, shared by the preferences app picker and the
// shortcut picker. Enumeration and icons live in Shared so the exact same
// list and rendering are used from both processes. The list is the home
// screen's shortlist: hidden, launch-prohibited and web-app proxies are
// filtered out, and each entry knows whether it is a user or system app.
@interface KayokoAppInfo : NSObject

@property(nonatomic, copy, readonly) NSString *bundleID;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, assign, readonly, getter=isUserApp) BOOL userApp;

+ (NSArray<KayokoAppInfo *> *)installedApps;
+ (nullable instancetype)appWithBundleID:(NSString *)bundleID;
+ (UIImage *)iconForBundleID:(nullable NSString *)bundleID;

// Reverse-DNS shape test shared with the Core-side execution paths so the
// open-app channel can never be coerced into acting on a non-identifier.
+ (BOOL)isValidBundleIdentifier:(nullable NSString *)value;

@end

NS_ASSUME_NONNULL_END
