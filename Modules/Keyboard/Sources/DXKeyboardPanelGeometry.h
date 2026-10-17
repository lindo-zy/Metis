#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// All inputs use the panel window's coordinates. Ignore invalid/stale rectangles
// and full-screen ancestors; the keyboard surface must sit below the app content.
static inline CGRect DXKeyboardPanelUnionCoverage(CGRect coverage, CGRect candidate, CGRect bounds,
                                                  BOOL keyboardSurface) {
    if (!isfinite(candidate.origin.x) || !isfinite(candidate.origin.y) ||
        !isfinite(candidate.size.width) || !isfinite(candidate.size.height) ||
        CGRectIsNull(candidate) || CGRectIsEmpty(candidate)) return coverage;
    candidate = CGRectIntersection(candidate, bounds);
    if (CGRectIsNull(candidate) || CGRectIsEmpty(candidate)) return coverage;
    if (keyboardSurface && (CGRectGetMinY(candidate) <= CGRectGetMinY(bounds) + CGRectGetHeight(bounds) * 0.25 ||
        CGRectGetWidth(candidate) < CGRectGetWidth(bounds) * 0.72)) return coverage;
    return CGRectIsNull(coverage) ? candidate : CGRectUnion(coverage, candidate);
}

static inline CGRect DXKeyboardPanelFullWidthCoverage(CGRect coverage, CGRect bounds) {
    if (CGRectIsNull(coverage) || CGRectIsEmpty(coverage) || CGRectGetHeight(coverage) < 100) return CGRectNull;
    coverage.origin.x = CGRectGetMinX(bounds);
    coverage.size.width = CGRectGetWidth(bounds);
    return CGRectIntersection(coverage, bounds);
}
