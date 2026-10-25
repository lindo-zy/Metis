#import <CoreGraphics/CoreGraphics.h>

/// Return an owned image rotated clockwise by quarterTurns. No UIKit/main-thread work.
CGImageRef MTNativeCaptureCreateOrientedImage(CGImageRef source, unsigned quarterTurns) CF_RETURNS_RETAINED;
