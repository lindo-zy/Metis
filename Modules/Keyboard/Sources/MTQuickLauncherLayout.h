#import <CoreGraphics/CoreGraphics.h>

// Pure geometry shared with host checks. Callers supply safe-area distances.
static inline CGRect MTQuickLauncherPanelFrame(CGRect bounds, CGFloat topInset, CGFloat leftInset,
    CGFloat bottomInset, CGFloat rightInset, NSInteger side) {
    CGFloat left = CGRectGetMinX(bounds) + leftInset + 8, right = CGRectGetMaxX(bounds) - rightInset - 8;
    CGFloat top = CGRectGetMinY(bounds) + topInset + 8, bottom = CGRectGetMaxY(bounds) - bottomInset - 8;
    BOOL wide = right - left > 440 && bounds.size.width > bounds.size.height;
    CGFloat width = MIN(wide ? 620 : 316, MAX(0, right - left));
    CGFloat height = MIN(wide ? 278 : 470, MAX(0, bottom - top));
    return CGRectMake(side == 1 ? right - width : left, bottom - height, width, height);
}

static inline CGRect MTQuickLauncherKeysFrame(CGSize size) {
    return size.width > 400 ? CGRectMake(size.width * 0.47, 48, size.width * 0.53 - 12, size.height - 60)
        : CGRectMake(12, 254, size.width - 24, size.height - 266);
}
static inline CGRect MTQuickLauncherDigitFrame(CGSize size, NSUInteger index) {
    return CGRectMake((index % 3) * (size.width + 6) / 3, (index / 3) * (size.height + 6) / 4,
        (size.width - 12) / 3, (size.height - 18) / 4);
}
