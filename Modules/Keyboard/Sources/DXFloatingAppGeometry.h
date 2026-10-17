#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// Scale the whole card (header and hosted canvas) by the same factor. Bounds
// remain in unscaled coordinates so UIKit also transforms host input correctly.
static inline CGFloat DXFloatingAppZoom(CGSize card, CGRect available, CGFloat requested) {
    if (card.width <= 0 || card.height <= 0 || CGRectIsEmpty(available) || CGRectIsInfinite(available) ||
        !isfinite(card.width) || !isfinite(card.height)) return 1;
    CGFloat maximum = MIN(available.size.width / card.width, available.size.height / card.height);
    // Keep the two 44pt header controls usable, including initially small cards.
    CGFloat minimum = MIN(maximum, MIN(1, MAX(30.0 / 44.0, 132 / card.width)));
    return MAX(minimum, MIN(maximum, isfinite(requested) ? requested : 1));
}

static inline CGRect DXFloatingAppFrame(CGSize card, CGRect available, CGFloat zoom,
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
