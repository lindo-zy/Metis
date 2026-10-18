#import <CoreGraphics/CoreGraphics.h>

// Pure geometry shared with host checks. Callers supply safe-area distances.
// Docked side hugs the screen edge (4pt seam); the floating side keeps 8pt.
// scalePercent：设置里的面板大小百分比（80~130，缺省 100），等比缩放基准宽高；
// 缩放后仍夹回可用区域，小屏放大到放不下时按可用宽度截断。
static inline CGFloat MTQuickLauncherScaleFactor(CGFloat scalePercent) {
    if (!isfinite(scalePercent) || scalePercent <= 0) return 1.0;
    return MIN(MAX(scalePercent, 80.0), 130.0) / 100.0;
}

static inline CGRect MTQuickLauncherPanelFrame(CGRect bounds, CGFloat topInset, CGFloat leftInset,
    CGFloat bottomInset, CGFloat rightInset, NSInteger side, CGFloat scalePercent) {
    CGFloat left = CGRectGetMinX(bounds) + leftInset + (side == 0 ? 4 : 8);
    CGFloat right = CGRectGetMaxX(bounds) - rightInset - (side == 1 ? 4 : 8);
    CGFloat top = CGRectGetMinY(bounds) + topInset + 8, bottom = CGRectGetMaxY(bounds) - bottomInset - 8;
    BOOL wide = right - left > 440 && bounds.size.width > bounds.size.height;
    CGFloat factor = MTQuickLauncherScaleFactor(scalePercent);
    CGFloat width = MIN((wide ? 620 : 316) * factor, MAX(0, right - left));
    CGFloat height = MIN((wide ? 278 : 470) * factor, MAX(0, bottom - top));
    return CGRectMake(side == 1 ? right - width : left, bottom - height, width, height);
}

static inline CGRect MTQuickLauncherKeysFrame(CGSize size) {
    return size.width > 400 ? CGRectMake(size.width * 0.47, 48, size.width * 0.53 - 12, size.height - 60)
        // 面板缩小后可用高度可能不足，仍然不能给负高度让数字键画到面板外。
        : CGRectMake(12, 254, size.width - 24, MAX(0, size.height - 266));
}
static inline CGRect MTQuickLauncherDigitFrame(CGSize size, NSUInteger index) {
    return CGRectMake((index % 3) * (size.width + 6) / 3, (index / 3) * (size.height + 6) / 4,
        (size.width - 12) / 3, (size.height - 18) / 4);
}
