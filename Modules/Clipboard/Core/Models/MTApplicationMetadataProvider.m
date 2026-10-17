//
//  MTApplicationMetadataProvider.m
//  Mt
//

#import "MTApplicationMetadataProvider.h"
#import "MTPasteboardItem.h"
#import "MTPasteboardManager.h"

#import <objc/runtime.h>

static int const kMTApplicationIconFormatListRow = 1;
static int const kMTApplicationIconFormatSearchToken = 5;
static NSString *const kMTSpotlightBundleIdentifier = @"com.apple.Spotlight";
static NSString *const kMTSpringBoardBundleIdentifier = @"com.apple.springboard";

NS_ASSUME_NONNULL_BEGIN

@interface UIImage (IconCache)
+ (nullable instancetype)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier
                                                           format:(int)format
                                                            scale:(CGFloat)scale;
@end

@interface SBApplication : NSObject
@property(nonatomic, copy, readonly) NSString *displayName;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

NS_ASSUME_NONNULL_END

@interface MTApplicationMetadataProvider ()
- (nullable SBApplication *)applicationForBundleIdentifier:(NSString *)bundleIdentifier;
@end

@implementation MTApplicationMetadataProvider

- (NSString *)displayNameForBundleIdentifier:(NSString *)bundleIdentifier {
    if ([self isContinuityBundleIdentifier:bundleIdentifier]) {
        return [[MTPasteboardManager localizationBundle] localizedStringForKey:@"Continuity"
                                                                             value:nil
                                                                             table:@"Tweak"];
    }

    if ([self isSpotlightBundleIdentifier:bundleIdentifier]) {
        return [[MTPasteboardManager localizationBundle] localizedStringForKey:@"Spotlight"
                                                                             value:nil
                                                                             table:@"Tweak"];
    }

    if ([self isSpringBoardBundleIdentifier:bundleIdentifier]) {
        return [[MTPasteboardManager localizationBundle] localizedStringForKey:@"SpringBoard"
                                                                             value:nil
                                                                             table:@"Tweak"];
    }

    NSString *displayName = [[self applicationForBundleIdentifier:bundleIdentifier] displayName];
    return [displayName length] > 0 ? displayName : bundleIdentifier;
}

- (BOOL)isContinuityBundleIdentifier:(NSString *)bundleIdentifier {
    NSString *normalizedBundleIdentifier = [[bundleIdentifier
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [normalizedBundleIdentifier isEqualToString:kMTContinuityBundleIdentifier] ||
           [normalizedBundleIdentifier isEqualToString:@"continuity"] ||
           [normalizedBundleIdentifier isEqualToString:@"handoff"];
}

- (BOOL)isSpotlightBundleIdentifier:(NSString *)bundleIdentifier {
    NSString *normalizedBundleIdentifier = [[bundleIdentifier
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [normalizedBundleIdentifier isEqualToString:[kMTSpotlightBundleIdentifier lowercaseString]] ||
           [normalizedBundleIdentifier isEqualToString:@"spotlight"];
}

- (nullable SBApplication *)applicationForBundleIdentifier:(NSString *)bundleIdentifier {
    return [[objc_getClass("SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bundleIdentifier];
}

- (BOOL)isSpringBoardBundleIdentifier:(NSString *)bundleIdentifier {
    NSString *normalizedBundleIdentifier = [[bundleIdentifier
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [normalizedBundleIdentifier isEqualToString:kMTSpringBoardBundleIdentifier] ||
           [normalizedBundleIdentifier isEqualToString:@"springboard"];
}

- (BOOL)hasApplicationForBundleIdentifier:(NSString *)bundleIdentifier {
    if ([self isContinuityBundleIdentifier:bundleIdentifier]) {
        return YES;
    }
    if ([self isSpotlightBundleIdentifier:bundleIdentifier]) {
        return YES;
    }
    if ([self isSpringBoardBundleIdentifier:bundleIdentifier]) {
        return YES;
    }
    return [self applicationForBundleIdentifier:bundleIdentifier] != nil;
}

- (nullable UIImage *)continuityIcon {
    return [UIImage imageNamed:@"HandOff"
                             inBundle:[MTPasteboardManager localizationBundle]
        compatibleWithTraitCollection:nil];
}

- (nullable UIImage *)continuitySearchTokenIcon {
    UIImage *icon = [UIImage imageNamed:@"HandOff-Search"
                               inBundle:[MTPasteboardManager localizationBundle]
          compatibleWithTraitCollection:nil];
    return [icon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (nullable UIImage *)springBoardIcon {
    return [UIImage imageNamed:@"HomeScreen"
                             inBundle:[MTPasteboardManager localizationBundle]
        compatibleWithTraitCollection:nil];
}

- (nullable UIImage *)springBoardSearchTokenIcon {
    UIImage *icon = [UIImage imageNamed:@"HomeScreen-Search"
                               inBundle:[MTPasteboardManager localizationBundle]
          compatibleWithTraitCollection:nil];
    return [icon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (nullable UIImage *)spotlightIcon {
    return [UIImage imageNamed:@"Spotlight"
                             inBundle:[MTPasteboardManager localizationBundle]
        compatibleWithTraitCollection:nil];
}

- (nullable UIImage *)spotlightSearchTokenIcon {
    UIImage *icon = [UIImage imageNamed:@"Spotlight-Search"
                               inBundle:[MTPasteboardManager localizationBundle]
          compatibleWithTraitCollection:nil];
    return [icon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (nullable UIImage *)applicationIconForBundleIdentifier:(NSString *)bundleIdentifier
                                                  format:(int)format
                                                   scale:(CGFloat)scale {
    NSString *effectiveBundleIdentifier = [bundleIdentifier length] > 0 ? bundleIdentifier : @"com.apple.WebSheet";
    UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:effectiveBundleIdentifier
                                                               format:format
                                                                scale:scale];
    if (!icon && ![effectiveBundleIdentifier isEqualToString:@"com.apple.WebSheet"]) {
        icon = [UIImage _applicationIconImageForBundleIdentifier:@"com.apple.WebSheet" format:format scale:scale];
    }
    return icon;
}

- (nullable UIImage *)iconForBundleIdentifier:(NSString *)bundleIdentifier {
    if ([self isContinuityBundleIdentifier:bundleIdentifier]) {
        return [self continuityIcon];
    }

    if ([self isSpotlightBundleIdentifier:bundleIdentifier]) {
        return [self spotlightIcon];
    }

    if ([self isSpringBoardBundleIdentifier:bundleIdentifier]) {
        return [self springBoardIcon];
    }

    return [self applicationIconForBundleIdentifier:bundleIdentifier
                                             format:kMTApplicationIconFormatListRow
                                              scale:[[UIScreen mainScreen] scale]];
}

- (nullable UIImage *)smallIconForBundleIdentifier:(NSString *)bundleIdentifier {
    if ([self isContinuityBundleIdentifier:bundleIdentifier]) {
        return [self continuitySearchTokenIcon];
    }

    if ([self isSpotlightBundleIdentifier:bundleIdentifier]) {
        return [self spotlightSearchTokenIcon];
    }

    if ([self isSpringBoardBundleIdentifier:bundleIdentifier]) {
        return [self springBoardSearchTokenIcon];
    }

    return [self applicationIconForBundleIdentifier:bundleIdentifier
                                             format:kMTApplicationIconFormatSearchToken
                                              scale:[[UIScreen mainScreen] scale]];
}

@end
