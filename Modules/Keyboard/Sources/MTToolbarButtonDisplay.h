#pragma once
#import <Foundation/Foundation.h>

// Display belongs to an individual button. Retired toolbar/segment switches
// must never override the text default, including on upgrade.
#define kMTButtonDisplayMode @"displayMode"
#define MTButtonDisplayText @"text"
#define MTButtonDisplayIcon @"icon"

static inline NSString *MTButtonDisplayMode(id value) {
    return [value isKindOfClass:NSString.class] && [value isEqual:MTButtonDisplayIcon]
        ? MTButtonDisplayIcon : MTButtonDisplayText;
}

static inline BOOL MTButtonShowsText(NSDictionary *button) {
    return ![MTButtonDisplayMode(button[kMTButtonDisplayMode]) isEqual:MTButtonDisplayIcon];
}
