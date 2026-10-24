#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

static inline CGFloat MTFloatingAppClampArea(CGFloat area) {
    return isfinite(area) ? MIN(.80, MAX(.10, area)) : .20;
}

// 自动缩放开启时离开卡片后的收缩面积。位置记忆只在这个尺寸下维护：
// 放大态卡片会被 available 边界钳制，把钳制结果写回记忆会让缩回时丢掉拖动位置。
static inline CGFloat MTFloatingAppCollapsedArea(void) {
    return .10;
}

// Area includes the header; 20% is not a 20% linear scale.
static inline CGFloat MTFloatingAppContentScale(CGSize canvas, CGRect display, CGRect available,
                                               CGFloat area, CGFloat header) {
    if (canvas.width <= 0 || canvas.height <= 0 || !isfinite(canvas.width) || !isfinite(canvas.height) ||
        CGRectIsEmpty(display) || CGRectIsEmpty(available) || CGRectIsInfinite(display) ||
        CGRectIsInfinite(available) || !isfinite(header) || header < 0) return 0;
    area = MTFloatingAppClampArea(area);
    CGFloat pixels = display.size.width * display.size.height * area;
    CGFloat scale = (sqrt(header * header + 4 * canvas.height * pixels / canvas.width) - header) / (2 * canvas.height);
    return MAX(0, MIN(scale, MIN(available.size.width / canvas.width,
                                MAX(0, available.size.height - header) / canvas.height)));
}

static inline CGRect MTFloatingAppAvailableRect(CGRect display, CGRect safeArea) {
    return CGRectInset(CGRectIntersection(display, safeArea), 8, 8);
}

// Convert a pinch's content scale back to the same area contract as Settings.
// The header stays 36pt, so area does not simply scale by the pinch squared.
static inline CGFloat MTFloatingAppAreaForContentScale(CGSize canvas, CGRect display,
                                                       CGFloat scale, CGFloat header) {
    if (canvas.width <= 0 || canvas.height <= 0 || !isfinite(canvas.width) || !isfinite(canvas.height) ||
        CGRectIsEmpty(display) || CGRectIsInfinite(display) || !isfinite(scale) || scale <= 0 ||
        !isfinite(header) || header < 0) return .20;
    CGFloat area = canvas.width * scale * (canvas.height * scale + header) /
                   (display.size.width * display.size.height);
    return MTFloatingAppClampArea(area);
}

static inline CGRect MTFloatingAppFrame(CGSize card, CGRect available,
                                       CGPoint center, NSInteger alignment, BOOL customized) {
    CGSize displayed = card;
    if (!customized) {
        if (alignment == 0) center.x = CGRectGetMinX(available) + displayed.width / 2;
        else if (alignment == 2) center.x = CGRectGetMaxX(available) - displayed.width / 2;
        else center.x = CGRectGetMidX(available);
    }
    center.x = MAX(CGRectGetMinX(available) + displayed.width / 2,
                   MIN(CGRectGetMaxX(available) - displayed.width / 2, center.x));
    center.y = MAX(CGRectGetMinY(available) + displayed.height / 2,
                   MIN(CGRectGetMaxY(available) - displayed.height / 2, center.y));
    return CGRectMake(center.x - displayed.width / 2, center.y - displayed.height / 2,
                      displayed.width, displayed.height);
}
