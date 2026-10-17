#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

static inline CGFloat DXPanelControlCircle(CGFloat width) { return MAX(0, MIN(58, width / 5 - 8)); }
static inline CGFloat DXPanelSystemControlsSliderTop(CGFloat width, BOOL showsToggleRow) {
    return showsToggleRow ? DXPanelControlCircle(width) + 24 + 12 : 0;
}
static inline CGFloat DXPanelSystemControlsHeightForRows(CGFloat width, BOOL showsToggleRow, BOOL showsSliderRow) {
    if (!showsToggleRow && !showsSliderRow) return 0;
    CGFloat contentHeight = showsSliderRow ? DXPanelSystemControlsSliderTop(width, showsToggleRow) + 50 :
        DXPanelControlCircle(width) + 4 + 24;
    return contentHeight + 14;
}
static inline CGFloat DXPanelSystemControlsHeight(CGFloat width) {
    return DXPanelSystemControlsHeightForRows(width, YES, YES);
}
