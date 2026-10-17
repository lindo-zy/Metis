#import <Foundation/Foundation.h>

// A remote/system keyboard surface wins over a text-effects accessory surface.
// Ordinary app windows are never a fallback: they can sit below the keyboard's
// separately composited scene regardless of their UIWindow level.
static inline NSInteger DXKeyboardPanelHostRank(NSString *className, BOOL activeKeyboardWindow) {
    if ([className containsString:@"RemoteKeyboardWindow"] || [className containsString:@"SystemKeyboardWindow"]) return 4;
    if (activeKeyboardWindow) return 3;
    if ([className containsString:@"TextEffectsWindow"]) return 2;
    return 0;
}
