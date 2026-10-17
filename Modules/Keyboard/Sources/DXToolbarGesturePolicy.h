#include <math.h>

// Signed result: +/-1 is a confined button swipe, +/-2 is a configured toolbar long swipe.
// Travel outside the original button never falls back to that button's action.
static inline int DXToolbarHorizontalResult(double dx, double dy, double toolbarWidth,
                                            double buttonWidth, int hasButton, int stayedInButton) {
    if (!isfinite(dx) || !isfinite(dy) || !isfinite(toolbarWidth) || toolbarWidth <= 0) return 0;
    if (fabs(dx) < 12 || fabs(dx) < fabs(dy) * 1.5) return 0;
    int direction = dx < 0 ? -1 : 1;
    if (hasButton && stayedInButton) return direction;
    double threshold = fmax(100.0, toolbarWidth * 0.30);
    if (hasButton) threshold = fmax(threshold, buttonWidth * 1.25);
    return fabs(dx) >= threshold ? direction * 2 : 0;
}
