#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// Shared by the keyboard surface and the Settings preview. Units are points;
// content scale affects the circles and labels, never the number of columns.
static inline CGFloat DXKeyboardPanelCircle(CGFloat width, NSInteger columns, CGFloat scale) {
    return MAX(0, MIN(54 * scale, width / MAX(1, columns) - 16));
}
static inline CGFloat DXKeyboardPanelRowHeight(CGFloat width, NSInteger columns, CGFloat scale) {
    return DXKeyboardPanelCircle(width, columns, scale) + 42 * scale;
}
static inline CGRect DXKeyboardPanelItemFrame(NSUInteger index, CGFloat width, NSInteger columns, CGFloat scale) {
    columns = MAX(1, columns);
    CGFloat itemWidth = width / columns;
    CGFloat height = DXKeyboardPanelRowHeight(width, columns, scale);
    return CGRectMake((index % columns) * itemWidth, (index / columns) * height, itemWidth, height);
}
static inline CGFloat DXKeyboardPanelContentHeight(NSUInteger count, CGFloat width, NSInteger columns, CGFloat scale) {
    return ceil((double)count / MAX(1, columns)) * DXKeyboardPanelRowHeight(width, columns, scale);
}

// Logical page zero starts at the right edge: a rightward drag reveals the
// next page to its left. Item order within every page remains row-major.
static inline NSUInteger DXPanelPageCapacity(NSInteger columns) {
    return (NSUInteger)MAX(1, columns) * 3;
}
static inline NSUInteger DXPanelPageCount(NSUInteger count, NSInteger columns) {
    NSUInteger capacity = DXPanelPageCapacity(columns);
    return count / capacity + (count % capacity != 0);
}
static inline CGFloat DXPanelPageHeight(NSUInteger count, CGFloat width, NSInteger columns, CGFloat scale) {
    return DXKeyboardPanelContentHeight(MIN(count, DXPanelPageCapacity(columns)), width, columns, scale);
}
static inline CGFloat DXPanelPageOffset(NSUInteger page, NSUInteger pages, CGFloat width) {
    if (!pages || !isfinite(width) || width <= 0) return 0;
    return (pages - 1 - MIN(page, pages - 1)) * width;
}
static inline NSUInteger DXPanelPageAtOffset(CGFloat offset, NSUInteger pages, CGFloat width) {
    if (!pages || !isfinite(offset) || !isfinite(width) || width <= 0) return 0;
    CGFloat physicalPage = MIN((CGFloat)(pages - 1), MAX(0, round(offset / width)));
    return pages - 1 - (NSUInteger)physicalPage;
}
static inline CGRect DXPanelPagedItemFrame(NSUInteger index, NSUInteger count, CGFloat width, NSInteger columns, CGFloat scale) {
    if (index >= count || !isfinite(width) || width <= 0) return CGRectZero;
    NSUInteger capacity = DXPanelPageCapacity(columns);
    CGRect frame = DXKeyboardPanelItemFrame(index % capacity, width, columns, scale);
    frame.origin.x += DXPanelPageOffset(index / capacity, DXPanelPageCount(count, columns), width);
    return frame;
}
