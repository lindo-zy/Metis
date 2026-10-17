#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

// Shared geometry for the small handle, its partially hidden edge state and app panel.
static const CGFloat DXKbdHandleSide = 34.0;
static const CGFloat DXKbdHandleCornerRadius = 8.0;
static const CGFloat DXKbdHandleVisibleEdge = 11.0;
// 面板对齐 PullOver-X 应用栏：每个 App 一块与把手同款的 34pt 毛玻璃瓦片，
// 无整体容器背景，瓦片间隙 4pt（PO_APP_RAIL_TILE_GAP）。
static const CGFloat DXKbdPanelWidth = DXKbdHandleSide;
static const CGFloat DXKbdPanelTileSide = DXKbdHandleSide;
static const CGFloat DXKbdPanelTileGap = 4.0;
// 把手内嵌图标与面板瓦片图标共用的内缩量（34pt 槽内显示 24pt 图标）。
static const CGFloat DXKbdHandleIconInset = 5.0;
static const CGFloat DXKbdHandleEdgeMargin = 6.0;
static const CGFloat DXKbdHandleBottomGap = 8.0;

static inline CGFloat DXKbdHandleClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return MIN(MAX(isfinite(value) ? value : minimum, minimum), MAX(minimum, maximum));
}

static inline CGFloat DXKbdHandleMinY(CGRect bounds, CGFloat top) {
    return CGRectGetMinY(bounds) + MAX(0, top) + DXKbdHandleEdgeMargin;
}

static inline CGFloat DXKbdHandleMaxY(CGRect bounds, CGFloat top, CGFloat bottom) {
    return MAX(DXKbdHandleMinY(bounds, top), CGRectGetMaxY(bounds) - MAX(0, bottom)
        - DXKbdHandleEdgeMargin - DXKbdHandleSide);
}

static inline CGRect DXKbdHandleFrame(CGRect bounds, CGFloat top, CGFloat bottom,
                                     NSInteger alignment, CGFloat fraction, BOOL nubbed) {
    CGFloat minimum = DXKbdHandleMinY(bounds, top);
    CGFloat maximum = DXKbdHandleMaxY(bounds, top, bottom);
    CGFloat x = alignment == 1
        ? CGRectGetMaxX(bounds) - (nubbed ? DXKbdHandleVisibleEdge : DXKbdHandleSide + DXKbdHandleEdgeMargin)
        : CGRectGetMinX(bounds) + (nubbed ? DXKbdHandleVisibleEdge - DXKbdHandleSide : DXKbdHandleEdgeMargin);
    return CGRectMake(x, minimum + DXKbdHandleClamp(fraction, 0, 1) * (maximum - minimum),
                      DXKbdHandleSide, DXKbdHandleSide);
}

static inline CGPoint DXKbdHandleDragCenter(CGRect bounds, CGFloat top, CGFloat bottom, CGPoint point) {
    CGFloat half = DXKbdHandleSide / 2;
    return CGPointMake(DXKbdHandleClamp(point.x, CGRectGetMinX(bounds) - half + DXKbdHandleVisibleEdge,
                                       CGRectGetMaxX(bounds) + half - DXKbdHandleVisibleEdge),
                       DXKbdHandleClamp(point.y, DXKbdHandleMinY(bounds, top) + half,
                                       DXKbdHandleMaxY(bounds, top, bottom) + half));
}

static inline CGFloat DXKbdHandleFraction(CGRect bounds, CGFloat top, CGFloat bottom, CGFloat centerY) {
    CGFloat minimum = DXKbdHandleMinY(bounds, top);
    CGFloat range = DXKbdHandleMaxY(bounds, top, bottom) - minimum;
    return range > 0 ? DXKbdHandleClamp((centerY - DXKbdHandleSide / 2 - minimum) / range, 0, 1) : 0;
}

static inline BOOL DXKbdHandleShouldNub(CGRect bounds, CGPoint center, CGPoint translation,
                                      NSInteger startSide, NSInteger endSide) {
    BOOL pushedOut = startSide == endSide && fabs(translation.x) > fabs(translation.y) &&
        (endSide == 1 ? translation.x >= 12 : translation.x <= -12);
    return pushedOut || (endSide == 1 ? center.x > CGRectGetMaxX(bounds) - DXKbdHandleSide / 4
                                      : center.x < CGRectGetMinX(bounds) + DXKbdHandleSide / 4);
}

static inline CGRect DXKbdHandlePanelFrame(CGRect bounds, CGFloat top, CGFloat bottom,
                                          CGRect handle, NSUInteger count) {
    CGFloat tiles = MAX(count, (NSUInteger)1);
    CGFloat height = DXKbdPanelTileSide * tiles + DXKbdPanelTileGap * (tiles - 1);
    CGFloat minimum = CGRectGetMinY(bounds) + MAX(0, top) + DXKbdHandleEdgeMargin;
    CGFloat maximum = CGRectGetMaxY(bounds) - MAX(0, bottom) - DXKbdHandleEdgeMargin;
    CGFloat x = DXKbdHandleClamp(CGRectGetMidX(handle) - DXKbdPanelWidth / 2,
        CGRectGetMinX(bounds) + DXKbdHandleEdgeMargin, CGRectGetMaxX(bounds) - DXKbdPanelWidth - DXKbdHandleEdgeMargin);
    CGFloat y = CGRectGetMinY(handle) - DXKbdHandleBottomGap - height;
    if (y < minimum) y = CGRectGetMaxY(handle) + DXKbdHandleBottomGap;
    y = DXKbdHandleClamp(y, minimum, maximum - height);
    return CGRectMake(x, y, DXKbdPanelWidth, height);
}
