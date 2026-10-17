//
//  MTClipboardHelperLocalization.m
//  Mt
//

#import "MTClipboardHelperLocalization.h"

#import <roothide.h>

static NSBundle *mtHelperLocalizationBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      bundle = [NSBundle bundleWithPath:jbroot(@"/Library/PreferenceBundles/MetisClipboardPrefs.bundle")];
    });
    return bundle;
}

NSString *MTClipboardHelperLocalizedString(NSString *key) {
    return [mtHelperLocalizationBundle() localizedStringForKey:key value:nil table:@"Tweak"];
}
