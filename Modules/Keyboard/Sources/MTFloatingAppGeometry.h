#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// Area includes the header; 20% is not a 20% linear scale.
static inline CGFloat MTFloatingAppContentScale(CGSize canvas, CGRect display, CGRect available,
                                               CGFloat area, CGFloat header) {
    if (canvas.width <= 0 || canvas.height <= 0 || !isfinite(canvas.width) || !isfinite(canvas.height) ||
        CGRectIsEmpty(display) || CGRectIsEmpty(available) || CGRectIsInfinite(display) ||
        CGRectIsInfinite(available) || !isfinite(header) || header < 0) return 0;
    if (!isfinite(area) || area < .10 || area > .60) area = .20;
    CGFloat pixels = display.size.width * display.size.height * area;
    CGFloat scale = (sqrt(header * header + 4 * canvas.height * pixels / canvas.width) - header) / (2 * canvas.height);
    return MAX(0, MIN(scale, MIN(available.size.width / canvas.width,
                                MAX(0, available.size.height - header) / canvas.height)));
}

static inline CGRect MTFloatingAppAvailableRect(CGRect display, CGRect safeArea, CGFloat keyboardTop) {
    CGRect available = CGRectInset(CGRectIntersection(display, safeArea), 8, 8);
    if (isfinite(keyboardTop) && keyboardTop >= 0 && keyboardTop < 1) {
        CGFloat bottom = CGRectGetMinY(display) + display.size.height * keyboardTop - 8;
        available.size.height = MAX(0, MIN(CGRectGetMaxY(available), bottom) - CGRectGetMinY(available));
    }
    return available;
}

// Scale the whole card (header and hosted canvas) by the same factor. Bounds
// remain in unscaled coordinates so UIKit also transforms host input correctly.
static inline CGFloat MTFloatingAppZoom(CGSize card, CGRect available, CGFloat requested) {
    if (card.width <= 0 || card.height <= 0 || CGRectIsEmpty(available) || CGRectIsInfinite(available) ||
        !isfinite(card.width) || !isfinite(card.height)) return 1;
    CGFloat maximum = MIN(available.size.width / card.width, available.size.height / card.height);
    // Keep the two 36pt header controls usable, including initially small cards.
    CGFloat minimum = MIN(maximum, MIN(1, MAX(30.0 / 36.0, 132 / card.width)));
    return MAX(minimum, MIN(maximum, isfinite(requested) ? requested : 1));
}

static inline CGRect MTFloatingAppFrame(CGSize card, CGRect available, CGFloat zoom,
                                       CGPoint center, NSInteger alignment, BOOL customized) {
    CGSize displayed = CGSizeMake(card.width * zoom, card.height * zoom);
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
