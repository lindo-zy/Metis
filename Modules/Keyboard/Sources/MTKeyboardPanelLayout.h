#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// Shared by the keyboard surface and the Settings preview. Units are points;
// content scale affects the circles and labels, never the number of columns.
static inline CGFloat MTKeyboardPanelCircle(CGFloat width, NSInteger columns, CGFloat scale) {
    return MAX(0, MIN(54 * scale, width / MAX(1, columns) - 16));
}
static inline CGFloat MTKeyboardPanelRowHeight(CGFloat width, NSInteger columns, CGFloat scale) {
    return MTKeyboardPanelCircle(width, columns, scale) + 42 * scale;
}
static inline CGRect MTKeyboardPanelItemFrame(NSUInteger index, CGFloat width, NSInteger columns, CGFloat scale) {
    columns = MAX(1, columns);
    CGFloat itemWidth = width / columns;
    CGFloat height = MTKeyboardPanelRowHeight(width, columns, scale);
    return CGRectMake((index % columns) * itemWidth, (index / columns) * height, itemWidth, height);
}
static inline CGFloat MTKeyboardPanelContentHeight(NSUInteger count, CGFloat width, NSInteger columns, CGFloat scale) {
    return ceil((double)count / MAX(1, columns)) * MTKeyboardPanelRowHeight(width, columns, scale);
}

// Logical page zero starts at the right edge: a rightward drag reveals the
// next page to its left. Item order within every page remains row-major.
static inline NSUInteger MTPanelPageCapacity(NSInteger columns) {
    return (NSUInteger)MAX(1, columns) * 3;
}
static inline NSUInteger MTPanelPageCount(NSUInteger count, NSInteger columns) {
    NSUInteger capacity = MTPanelPageCapacity(columns);
    return count / capacity + (count % capacity != 0);
}
static inline CGFloat MTPanelPageHeight(NSUInteger count, CGFloat width, NSInteger columns, CGFloat scale) {
    return MTKeyboardPanelContentHeight(MIN(count, MTPanelPageCapacity(columns)), width, columns, scale);
}
static inline CGFloat MTPanelPageOffset(NSUInteger page, NSUInteger pages, CGFloat width) {
    if (!pages || !isfinite(width) || width <= 0) return 0;
    return (pages - 1 - MIN(page, pages - 1)) * width;
}
static inline NSUInteger MTPanelPageAtOffset(CGFloat offset, NSUInteger pages, CGFloat width) {
    if (!pages || !isfinite(offset) || !isfinite(width) || width <= 0) return 0;
    CGFloat physicalPage = MIN((CGFloat)(pages - 1), MAX(0, round(offset / width)));
    return pages - 1 - (NSUInteger)physicalPage;
}
static inline CGRect MTPanelPagedItemFrame(NSUInteger index, NSUInteger count, CGFloat width, NSInteger columns, CGFloat scale) {
    if (index >= count || !isfinite(width) || width <= 0) return CGRectZero;
    NSUInteger capacity = MTPanelPageCapacity(columns);
    CGRect frame = MTKeyboardPanelItemFrame(index % capacity, width, columns, scale);
    frame.origin.x += MTPanelPageOffset(index / capacity, MTPanelPageCount(count, columns), width);
    return frame;
}
