#import <CoreGraphics/CoreGraphics.h>

// Pure geometry shared with host checks. Callers supply safe-area distances.
// Docked side hugs the screen edge (4pt seam); the floating side keeps 8pt.
// scalePercent：设置里的面板大小百分比（80~100，缺省 100）。
static inline CGFloat MTQuickLauncherScaleFactor(CGFloat scalePercent) {
    if (!isfinite(scalePercent) || scalePercent <= 0) return 1.0;
    return MIN(MAX(scalePercent, 80.0), 100.0) / 100.0;
}

static inline CGSize MTQuickLauncherBaseSize(BOOL wide) {
    return wide ? CGSizeMake(620, 278) : CGSizeMake(316, 470);
}

static inline CGRect MTQuickLauncherPanelFrame(CGRect bounds, CGFloat topInset, CGFloat leftInset,
    CGFloat bottomInset, CGFloat rightInset, NSInteger side, CGFloat scalePercent) {
    CGFloat left = CGRectGetMinX(bounds) + leftInset + (side == 0 ? 4 : 8);
    CGFloat right = CGRectGetMaxX(bounds) - rightInset - (side == 1 ? 4 : 8);
    CGFloat top = CGRectGetMinY(bounds) + topInset + 8, bottom = CGRectGetMaxY(bounds) - bottomInset - 8;
    BOOL wide = right - left > 440 && bounds.size.width > bounds.size.height;
    CGSize base = MTQuickLauncherBaseSize(wide);
    CGFloat factor = MTQuickLauncherScaleFactor(scalePercent);
    // 安全区不足时整体等比收缩，不能单独压扁高度挤占九键区。
    factor = MIN(factor, MIN(MAX(0, right - left) / base.width, MAX(0, bottom - top) / base.height));
    CGFloat width = base.width * factor, height = base.height * factor;
    return CGRectMake(side == 1 ? right - width : left, bottom - height, width, height);
}

// 拖动摆放：可用区为安全区内统一再留 8pt，落点以此为界（与默认态贴边不同，
// 摆放后四边都留缝，避免面板压住状态栏/主屏底部指示条）。
static inline CGRect MTQuickLauncherAvailableRect(CGRect bounds, CGFloat topInset, CGFloat leftInset,
    CGFloat bottomInset, CGFloat rightInset) {
    CGFloat x = CGRectGetMinX(bounds) + leftInset + 8, y = CGRectGetMinY(bounds) + topInset + 8;
    return CGRectMake(x, y, MAX(0, CGRectGetMaxX(bounds) - rightInset - 8 - x),
                      MAX(0, CGRectGetMaxY(bounds) - bottomInset - 8 - y));
}

// 摆放态与默认态共用同一套尺寸计算（横屏两列、等比缩放、安全区不足时收缩）。
static inline CGSize MTQuickLauncherDisplayedSize(CGRect bounds, CGRect available, CGFloat scalePercent) {
    BOOL wide = available.size.width > 440 && bounds.size.width > bounds.size.height;
    CGSize base = MTQuickLauncherBaseSize(wide);
    CGFloat factor = MIN(MTQuickLauncherScaleFactor(scalePercent),
        MIN(MAX(0, available.size.width) / base.width, MAX(0, available.size.height) / base.height));
    return CGSizeMake(base.width * factor, base.height * factor);
}

static inline CGFloat MTQuickLauncherClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return MIN(MAX(isfinite(value) ? value : minimum, minimum), MAX(minimum, maximum));
}

// 归一化中心点 -> 落点中心：可用区容不下面板时退化为可用区中心，不产生外溢。
static inline CGPoint MTQuickLauncherCenter(CGRect available, CGSize size, CGPoint normalized) {
    CGFloat halfWidth = size.width / 2, halfHeight = size.height / 2;
    CGFloat minX = CGRectGetMinX(available) + halfWidth, maxX = CGRectGetMaxX(available) - halfWidth;
    CGFloat minY = CGRectGetMinY(available) + halfHeight, maxY = CGRectGetMaxY(available) - halfHeight;
    CGFloat x = maxX > minX ? minX + MTQuickLauncherClamp(normalized.x, 0, 1) * (maxX - minX) : CGRectGetMidX(available);
    CGFloat y = maxY > minY ? minY + MTQuickLauncherClamp(normalized.y, 0, 1) * (maxY - minY) : CGRectGetMidY(available);
    return CGPointMake(x, y);
}

// 落点中心 -> 归一化中心点：拖动结束落盘前调用，越界一律夹回 0~1。
static inline CGPoint MTQuickLauncherNormalizedCenter(CGRect available, CGSize size, CGPoint center) {
    CGFloat halfWidth = size.width / 2, halfHeight = size.height / 2;
    CGFloat minX = CGRectGetMinX(available) + halfWidth, maxX = CGRectGetMaxX(available) - halfWidth;
    CGFloat minY = CGRectGetMinY(available) + halfHeight, maxY = CGRectGetMaxY(available) - halfHeight;
    CGFloat x = maxX > minX ? (center.x - minX) / (maxX - minX) : 0.5;
    CGFloat y = maxY > minY ? (center.y - minY) / (maxY - minY) : 0.5;
    return CGPointMake(MTQuickLauncherClamp(x, 0, 1), MTQuickLauncherClamp(y, 0, 1));
}

static inline CGRect MTQuickLauncherPlacedFrame(CGRect available, CGSize size, CGPoint normalized) {
    CGPoint center = MTQuickLauncherCenter(available, size, normalized);
    return CGRectMake(center.x - size.width / 2, center.y - size.height / 2, size.width, size.height);
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
