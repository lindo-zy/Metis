#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

typedef enum {
    MTQuickLauncherModeStrip = 0,
    MTQuickLauncherModeExpanded = 1,
    MTQuickLauncherModeSearch = 2
} MTQuickLauncherMode;

static inline MTQuickLauncherMode MTQuickLauncherNextMode(MTQuickLauncherMode mode, CGFloat dx, CGFloat dy, CGFloat velocity) {
    if (!isfinite(dx) || !isfinite(dy) || !isfinite(velocity) || fabs(dx) <= fabs(dy) * 1.2) return mode;
    if (fabs(dx) < 28 && !(fabs(dx) >= 10 && fabs(velocity) >= 450 && dx * velocity > 0)) return mode;
    return (MTQuickLauncherMode)MIN(2, MAX(0, (int)mode + (dx < 0 ? 1 : -1)));
}

static inline CGSize MTQuickLauncherModeBaseSize(MTQuickLauncherMode mode, BOOL wide) {
    if (mode == MTQuickLauncherModeSearch) return wide ? CGSizeMake(620, 372) : CGSizeMake(316, 600);
    return CGSizeMake(mode == MTQuickLauncherModeStrip ? 76 : 172, wide ? 340 : 480);
}

static inline CGSize MTQuickLauncherModeSize(CGRect bounds, CGRect available, CGFloat scalePercent, MTQuickLauncherMode mode);

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

// Three presentation stages share the same safe area, docking and saved-position contract.
static inline CGSize MTQuickLauncherModeSize(CGRect bounds, CGRect available, CGFloat scalePercent, MTQuickLauncherMode mode) {
    CGSize base = MTQuickLauncherModeBaseSize(mode, bounds.size.width > bounds.size.height);
    CGFloat factor = MIN(MTQuickLauncherScaleFactor(scalePercent),
        MIN(MAX(0, available.size.width) / base.width, MAX(0, available.size.height) / base.height));
    return CGSizeMake(base.width * factor, base.height * factor);
}
static inline CGRect MTQuickLauncherModeFrame(CGRect bounds, CGFloat top, CGFloat left, CGFloat bottom, CGFloat right,
    NSInteger side, CGFloat scalePercent, MTQuickLauncherMode mode) {
    CGRect available = MTQuickLauncherAvailableRect(bounds, top, left, bottom, right);
    // Default docking keeps the original 4pt seam.
    available.origin.x = CGRectGetMinX(bounds) + left + (side == 0 ? 4 : 8);
    available.size.width = MAX(0, CGRectGetMaxX(bounds) - right - (side == 1 ? 4 : 8) - available.origin.x);
    CGSize size = MTQuickLauncherModeSize(bounds, available, scalePercent, mode);
    return CGRectMake(side == 1 ? CGRectGetMaxX(available) - size.width : available.origin.x,
        CGRectGetMaxY(available) - size.height, size.width, size.height);
}

typedef struct {
    CGRect actions, query, status, apps, keys, footer;
    NSUInteger actionColumns, appColumns;
    CGFloat actionHeight;
} MTQuickLauncherContentFrames;

static inline MTQuickLauncherContentFrames MTQuickLauncherContentLayout(MTQuickLauncherMode mode, BOOL landscape) {
    CGSize size = MTQuickLauncherModeBaseSize(mode, landscape);
    CGFloat width = size.width, height = size.height;
    BOOL search = mode == MTQuickLauncherModeSearch, strip = mode == MTQuickLauncherModeStrip;
    MTQuickLauncherContentFrames f = {0};
    f.actionColumns = strip ? 1 : (search ? 4 : 2);
    f.appColumns = strip ? 1 : (search ? 3 : 2);
    f.actionHeight = search ? 52 : 44;
    f.actions = CGRectMake(8, search ? 44 : 24, width - 16, ((4 + f.actionColumns - 1) / f.actionColumns) * f.actionHeight);
    CGFloat afterActions = CGRectGetMaxY(f.actions);
    CGFloat contentWidth = search && landscape ? floor(width * .47) - 20 : width - 16;
    CGFloat gridTop = afterActions + 8, gridBottom = height - 44;
    if (search) {
        f.query = CGRectMake(8, afterActions + 6, contentWidth, 36);
        f.status = CGRectMake(8, afterActions + 44, contentWidth, 16);
        gridTop = afterActions + 64;
        if (landscape) f.keys = CGRectMake(width * .47, afterActions + 14, width * .53 - 12, height - afterActions - 66);
        else { f.keys = CGRectMake(12, height - 248, width - 24, 204); gridBottom = CGRectGetMinY(f.keys) - 8; }
    } else if (!strip) { f.status = CGRectMake(8, afterActions + 4, contentWidth, 16); gridTop += 16; }
    f.apps = CGRectMake(8, gridTop, contentWidth, MAX(44, gridBottom - gridTop));
    f.footer = CGRectMake(4, height - 44, width - 8, 44);
    return f;
}
