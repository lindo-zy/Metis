//
//  KayokoAppInfo.m
//  Kayoko
//

#import "KayokoAppInfo.h"

#import <dlfcn.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// Not in the SDK; loaded lazily from MobileCoreServices/CoreServices.
@interface LSApplicationRecord : NSObject
@property (nonatomic, readonly) NSArray *appTags;
@property (getter=isLaunchProhibited, readonly) BOOL launchProhibited;
@end

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly, copy) NSString *applicationIdentifier;
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *localizedName;
@property (nonatomic, readonly, copy) NSString *applicationType;
@property (nonatomic, readonly) NSArray *appTags;
@property (nonatomic, readonly) NSURL *bundleURL;
@property (getter=isLaunchProhibited, readonly) BOOL launchProhibited;
- (LSApplicationRecord *)correspondingApplicationRecord;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
// Single all-apps pass, matching the PullOver-X picker; can block while
// LaunchServices is cold, so callers keep this off the main thread.
- (NSArray<LSApplicationProxy *> *)allApplications;
@end

@interface UIImage (KayokoAppIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(NSInteger)format;
@end

#pragma clang diagnostic pop

// Hidden-app detection follows the PullOver-X picker: a "hidden" tag on the
// proxy, its LaunchServices record, or the bundle's SBAppTags; a
// launch-prohibited app; or a web-app identifier. SpringBoard's own shortlist
// is what surfaces these, so the picker list matches what the home screen
// actually shows.
static BOOL KayokoTagArrayContainsHidden(NSArray *tags) {
    if (![tags isKindOfClass:[NSArray class]]) {
        return NO;
    }
    for (id tag in tags) {
        if ([tag isKindOfClass:[NSString class]] &&
            [(NSString *)tag rangeOfString:@"hidden" options:0].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static BOOL KayokoAppProxyIsHidden(LSApplicationProxy *proxy) {
    NSArray *proxyAppTags = nil;
    NSArray *recordAppTags = nil;
    NSArray *bundleAppTags = nil;
    BOOL launchProhibited = NO;

    @try {
        if ([proxy respondsToSelector:@selector(correspondingApplicationRecord)]) {
            LSApplicationRecord *record = [proxy correspondingApplicationRecord];
            if ([record respondsToSelector:@selector(appTags)]) {
                recordAppTags = [record appTags];
            }
            if ([record respondsToSelector:@selector(isLaunchProhibited)]) {
                launchProhibited = [record isLaunchProhibited];
            }
        }
        if ([proxy respondsToSelector:@selector(appTags)]) {
            proxyAppTags = [proxy appTags];
        }
        if (!launchProhibited && [proxy respondsToSelector:@selector(isLaunchProhibited)]) {
            launchProhibited = [proxy isLaunchProhibited];
        }
        NSURL *bundleURL = [proxy respondsToSelector:@selector(bundleURL)] ? [proxy bundleURL] : nil;
        if (bundleURL && [bundleURL checkResourceIsReachableAndReturnError:nil]) {
            NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
            bundleAppTags = [bundle objectForInfoDictionaryKey:@"SBAppTags"];
        }
    } @catch (NSException *exception) {
        (void)exception;
    }

    NSString *identifier = [proxy respondsToSelector:@selector(applicationIdentifier)]
        ? [proxy applicationIdentifier] : nil;
    BOOL isWebApplication = [identifier rangeOfString:@"com.apple.webapp"
                                              options:NSCaseInsensitiveSearch].location != NSNotFound;

    return KayokoTagArrayContainsHidden(proxyAppTags)
        || KayokoTagArrayContainsHidden(recordAppTags)
        || KayokoTagArrayContainsHidden(bundleAppTags)
        || isWebApplication
        || launchProhibited;
}

static NSString *KayokoAppProxyType(LSApplicationProxy *proxy) {
    NSString *type = nil;
    @try {
        if ([proxy respondsToSelector:@selector(applicationType)]) {
            type = [proxy applicationType];
        }
    } @catch (NSException *exception) {
        (void)exception;
    }
    return [type isKindOfClass:[NSString class]] ? type : nil;
}

@implementation KayokoAppInfo

+ (void)ensureLaunchServicesLoaded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Settings on iOS 17 normally has LaunchServices loaded already;
        // iOS 16 does not. Keep both framework locations for compatibility.
        for (NSString *path in @[
            @"/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
            @"/System/Library/Frameworks/CoreServices.framework/CoreServices",
        ]) {
            if (dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL)) break;
        }
    });
}

+ (Class)appProxyClass {
    [self ensureLaunchServicesLoaded];
    return NSClassFromString(@"LSApplicationProxy");
}

+ (NSArray<LSApplicationProxy *> *)installedAppProxies {
    [self ensureLaunchServicesLoaded];
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        return @[];
    }
    @try {
        id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
        if (!workspace || ![workspace respondsToSelector:@selector(allApplications)]) {
            return @[];
        }

        NSArray *applications = [workspace allApplications];
        Class proxyClass = [self appProxyClass];
        if (!proxyClass) {
            return [applications isKindOfClass:[NSArray class]] ? applications : @[];
        }
        NSMutableArray *proxies = [NSMutableArray array];
        for (LSApplicationProxy *proxy in applications) {
            if ([proxy isKindOfClass:proxyClass]) [proxies addObject:proxy];
        }
        return proxies;
    } @catch (NSException *exception) {
        NSLog(@"[Kayoko] app enumeration failed (%@)", exception);
        return @[];
    }
}

+ (NSString *)bundleIDForProxy:(LSApplicationProxy *)proxy {
    NSString *bundleID = nil;
    @try {
        if ([proxy respondsToSelector:@selector(applicationIdentifier)]) {
            bundleID = [proxy applicationIdentifier];
        }
        if (![bundleID isKindOfClass:[NSString class]] || [bundleID length] == 0) {
            bundleID = [proxy respondsToSelector:@selector(bundleIdentifier)] ? [proxy bundleIdentifier] : nil;
        }
    } @catch (__unused NSException *exception) {
        bundleID = nil;
    }
    if ([bundleID isKindOfClass:[NSString class]] && [bundleID length] > 0) return bundleID;
    return nil;
}

+ (NSString *)localizedNameForProxy:(LSApplicationProxy *)proxy {
    NSString *name = nil;
    @try {
        if ([proxy respondsToSelector:@selector(localizedName)]) {
            name = [proxy localizedName];
        }
    } @catch (__unused NSException *exception) {
        name = nil;
    }
    return [name isKindOfClass:[NSString class]] && [name length] > 0 ? name : nil;
}

+ (NSArray<KayokoAppInfo *> *)installedApps {
    NSMutableArray<KayokoAppInfo *> *apps = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    Class proxyClass = [self appProxyClass];
    for (LSApplicationProxy *proxy in [self installedAppProxies]) {
        if (proxyClass && ![proxy isKindOfClass:proxyClass]) continue;
        if (![proxy respondsToSelector:@selector(applicationIdentifier)] &&
            ![proxy respondsToSelector:@selector(bundleIdentifier)]) {
            continue;
        }
        // Keep the picker list to launchable user/system apps, mirroring the
        // reference implementation: hidden, launch-prohibited, web-app and
        // internal proxies never reach the list.
        NSString *applicationType = KayokoAppProxyType(proxy);
        BOOL isUser = [applicationType isEqualToString:@"User"];
        BOOL isSystem = [applicationType isEqualToString:@"System"];
        if (!isUser && !isSystem) continue;
        if (KayokoAppProxyIsHidden(proxy)) continue;

        NSString *bundleID = [self bundleIDForProxy:proxy];
        NSString *name = [self localizedNameForProxy:proxy] ?: bundleID;
        if ([bundleID length] == 0 || [seen containsObject:bundleID]) continue;
        [seen addObject:bundleID];

        KayokoAppInfo *app = [[KayokoAppInfo alloc] init];
        app->_bundleID = [bundleID copy];
        app->_name = [name copy];
        app->_userApp = isUser;
        [apps addObject:app];
    }
    [apps sortUsingComparator:^NSComparisonResult(KayokoAppInfo *left, KayokoAppInfo *right) {
      return [[left name] localizedStandardCompare:[right name]];
    }];
    return apps;
}

+ (nullable instancetype)appWithBundleID:(NSString *)bundleID {
    if ([self isValidBundleIdentifier:bundleID]) {
        for (KayokoAppInfo *app in [self installedApps]) {
            if ([[app bundleID] isEqualToString:bundleID]) {
                return app;
            }
        }
    }
    return nil;
}

+ (UIImage *)iconForBundleID:(NSString *)bundleID {
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      cache = [[NSCache alloc] init];
      [cache setCountLimit:512];
    });
    if ([bundleID length] == 0) {
        return [UIImage systemImageNamed:@"app"];
    }
    UIImage *cached = [cache objectForKey:bundleID];
    if (cached) {
        return cached;
    }

    CGFloat side = 44.0;
    UIImage *base = nil;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:)]) {
        base = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2];
        if (!base) {
            base = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0];
        }
    }

    UIImage *icon = nil;
    if (base) {
        UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
        [format setScale:[[UIScreen mainScreen] scale]];
        [format setOpaque:NO];
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)
                                                                                   format:format];
        icon = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
          // Home-screen icons are square; round them like SpringBoard does.
          [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0, 0.0, side, side)
                                      cornerRadius:side * 0.225] addClip];
          [base drawInRect:CGRectMake(0.0, 0.0, side, side)];
        }];
    } else {
        icon = [UIImage systemImageNamed:@"app"];
    }
    if (icon) {
        [cache setObject:icon forKey:bundleID];
    }
    return icon;
}

+ (BOOL)isValidBundleIdentifier:(NSString *)value {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return NO;
    if ([value length] > 512) return NO;
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:
            @"^[A-Za-z0-9_](?:[A-Za-z0-9_-]*[A-Za-z0-9_])?(?:\\.[A-Za-z0-9_](?:[A-Za-z0-9_-]*[A-Za-z0-9_])?)+$"
                             options:0
                               error:nil];
    return [expression firstMatchInString:value options:0 range:NSMakeRange(0.0, [value length])] != nil;
}

@end
