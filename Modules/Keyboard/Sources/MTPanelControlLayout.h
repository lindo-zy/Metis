#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

static inline CGFloat MTPanelControlCircle(CGFloat width) { return MAX(0, MIN(58, width / 5 - 8)); }
static inline CGFloat MTPanelSystemControlsSliderTop(CGFloat width, BOOL showsToggleRow) {
    return showsToggleRow ? MTPanelControlCircle(width) + 24 + 12 : 0;
}
static inline CGFloat MTPanelSystemControlsHeightForRows(CGFloat width, BOOL showsToggleRow, BOOL showsSliderRow) {
    if (!showsToggleRow && !showsSliderRow) return 0;
    CGFloat contentHeight = showsSliderRow ? MTPanelSystemControlsSliderTop(width, showsToggleRow) + 50 :
        MTPanelControlCircle(width) + 4 + 24;
    return contentHeight + 14;
}
static inline CGFloat MTPanelSystemControlsHeight(CGFloat width) {
    return MTPanelSystemControlsHeightForRows(width, YES, YES);
}
