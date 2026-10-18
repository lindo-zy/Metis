#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

// Shared geometry for the small handle, its partially hidden edge state and the quick launcher.
static const CGFloat MTKbdHandleSide = 34.0;
static const CGFloat MTKbdHandleCornerRadius = 8.0;
static const CGFloat MTKbdHandleVisibleEdge = 11.0;
// 把手内嵌图标的内缩量（34pt 槽内显示 24pt 图标）。
static const CGFloat MTKbdHandleIconInset = 5.0;
static const CGFloat MTKbdHandleEdgeMargin = 6.0;

static inline CGFloat MTKbdHandleClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return MIN(MAX(isfinite(value) ? value : minimum, minimum), MAX(minimum, maximum));
}

static inline CGFloat MTKbdHandleMinY(CGRect bounds, CGFloat top) {
    return CGRectGetMinY(bounds) + MAX(0, top) + MTKbdHandleEdgeMargin;
}

static inline CGFloat MTKbdHandleMaxY(CGRect bounds, CGFloat top, CGFloat bottom) {
    return MAX(MTKbdHandleMinY(bounds, top), CGRectGetMaxY(bounds) - MAX(0, bottom)
        - MTKbdHandleEdgeMargin - MTKbdHandleSide);
}

static inline CGRect MTKbdHandleFrame(CGRect bounds, CGFloat top, CGFloat bottom,
                                     NSInteger alignment, CGFloat fraction, BOOL nubbed) {
    CGFloat minimum = MTKbdHandleMinY(bounds, top);
    CGFloat maximum = MTKbdHandleMaxY(bounds, top, bottom);
    CGFloat x = alignment == 1
        ? CGRectGetMaxX(bounds) - (nubbed ? MTKbdHandleVisibleEdge : MTKbdHandleSide + MTKbdHandleEdgeMargin)
        : CGRectGetMinX(bounds) + (nubbed ? MTKbdHandleVisibleEdge - MTKbdHandleSide : MTKbdHandleEdgeMargin);
    return CGRectMake(x, minimum + MTKbdHandleClamp(fraction, 0, 1) * (maximum - minimum),
                      MTKbdHandleSide, MTKbdHandleSide);
}

static inline CGPoint MTKbdHandleDragCenter(CGRect bounds, CGFloat top, CGFloat bottom, CGPoint point) {
    CGFloat half = MTKbdHandleSide / 2;
    return CGPointMake(MTKbdHandleClamp(point.x, CGRectGetMinX(bounds) - half + MTKbdHandleVisibleEdge,
                                       CGRectGetMaxX(bounds) + half - MTKbdHandleVisibleEdge),
                       MTKbdHandleClamp(point.y, MTKbdHandleMinY(bounds, top) + half,
                                       MTKbdHandleMaxY(bounds, top, bottom) + half));
}

static inline CGFloat MTKbdHandleFraction(CGRect bounds, CGFloat top, CGFloat bottom, CGFloat centerY) {
    CGFloat minimum = MTKbdHandleMinY(bounds, top);
    CGFloat range = MTKbdHandleMaxY(bounds, top, bottom) - minimum;
    return range > 0 ? MTKbdHandleClamp((centerY - MTKbdHandleSide / 2 - minimum) / range, 0, 1) : 0;
}

static inline BOOL MTKbdHandleShouldNub(CGRect bounds, CGPoint center, CGPoint translation,
                                      NSInteger startSide, NSInteger endSide) {
    BOOL pushedOut = startSide == endSide && fabs(translation.x) > fabs(translation.y) &&
        (endSide == 1 ? translation.x >= 12 : translation.x <= -12);
    return pushedOut || (endSide == 1 ? center.x > CGRectGetMaxX(bounds) - MTKbdHandleSide / 4
                                      : center.x < CGRectGetMinX(bounds) + MTKbdHandleSide / 4);
}
