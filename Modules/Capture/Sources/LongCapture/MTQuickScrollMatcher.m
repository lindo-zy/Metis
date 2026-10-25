#include "MTQuickScrollMatcher.h"
#include <stdlib.h>
#include <math.h>
#include <limits.h>

// 纯 C 编译单元（host 测试按 -x c 编译）：不依赖 ObjC 运行时宏。
#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif

enum { MTQuickTemplateCount = 12, MTQuickTemplateHeight = 160, MTQuickTemplateWidth = 40 };
typedef struct { int delta, y; float error; } MTQuickVote;

// Effective body window: patch placement keeps the conservative fixed fractions
// (large shifts need patches at every depth to gather votes); sticky chrome and
// fixed-overlay rows only ever REMOVE sampling rows, they never re-anchor bands.
typedef struct {
    int top, bottom;                  // Conservative patch band [top, bottom).
    int stickyTop, stickyBottom;      // Measured sticky chrome; 0 = none.
    const uint8_t *fixedRows;
    int fixedThreshold;
} MTQuickWindow;

static MTQuickWindow MTQuickMakeWindow(int rows, const MTQuickScrollLimits *limits) {
    MTQuickWindow window = { rows / 5, rows - rows / 7, 0, 0, NULL, 0 };
    if (limits) {
        window.stickyTop = limits->stickyTop;
        window.stickyBottom = limits->stickyBottom > 0 ? MIN(limits->stickyBottom, rows) : 0;
        window.fixedRows = limits->fixedRows;
        window.fixedThreshold = limits->fixedThreshold;
    }
    window.top = MAX(2, MIN(window.top, rows - MTQuickTemplateHeight - 2));
    window.bottom = MAX(window.top + MTQuickTemplateHeight, MIN(window.bottom, rows));
    // 粘性区覆盖不了有效补丁带时按未测定处理，避免整窗采样被清空。
    if (window.stickyTop >= window.bottom - MTQuickTemplateHeight) window.stickyTop = 0;
    if (window.stickyBottom > 0 && window.stickyBottom <= window.top + MTQuickTemplateHeight) window.stickyBottom = 0;
    return window;
}
static int MTQuickRowFixed(const MTQuickWindow *window, int row) {
    if (window->stickyTop > 0 && row < window->stickyTop) return 1;
    if (window->stickyBottom > 0 && row >= window->stickyBottom) return 1;
    return window->fixedRows && window->fixedThreshold > 0 &&
           window->fixedRows[row] >= window->fixedThreshold;
}

static float MTQuickPatchCost(const uint8_t *a, const uint8_t *b, int x, int y, int delta, int stride) {
    unsigned sum = 0, count = 0;
    for (int r = 0; r < MTQuickTemplateHeight; r += stride) {
        const uint8_t *p = a + (y + r) * MTQuickScrollSignatureWidth + x;
        const uint8_t *q = b + (y + r - delta) * MTQuickScrollSignatureWidth + x;
        for (int c = 0; c < MTQuickTemplateWidth; c += 2) {
            sum += (unsigned)abs((int)p[c] - q[c]); count++;
        }
    }
    return count ? (float)sum / count : 255;
}

static int MTQuickPatchHasTexture(const uint8_t *a, int x, int y) {
    unsigned gradient = 0, count = 0;
    for (int r = 0; r < MTQuickTemplateHeight; r += 2) {
        const uint8_t *p = a + (y + r) * MTQuickScrollSignatureWidth + x;
        for (int c = 1; c < MTQuickTemplateWidth; c += 2) {
            gradient += (unsigned)abs((int)p[c] - p[c - 1]); count++;
        }
    }
    return gradient * 4 > count * 3;
}

// Fixed overlays never translate: a patch overlapping them cannot vote any shift.
// Sticky chrome bands are skipped the same way.
static int MTQuickPatchTouchesFixed(const MTQuickWindow *window, int y) {
    if (!window->fixedRows || window->fixedThreshold <= 0) {
        if (window->stickyTop <= 0 && window->stickyBottom <= 0) return 0;
    }
    for (int r = y; r < y + MTQuickTemplateHeight; r += 4)
        if (MTQuickRowFixed(window, r)) return 1;
    return 0;
}

static int MTQuickStaticEdge(const uint8_t *a, const uint8_t *b, int rows, int bottom) {
    int limit = bottom ? rows / 4 : rows / 3, run = 0;
    for (int r = 0; r < limit; r++) {
        int y = bottom ? rows - 1 - r : r;
        unsigned difference = 0;
        for (int x = 6; x < MTQuickScrollSignatureWidth - 6; x++)
            difference += (unsigned)abs((int)a[y * MTQuickScrollSignatureWidth + x] - b[y * MTQuickScrollSignatureWidth + x]);
        run = difference > (MTQuickScrollSignatureWidth - 12) * 2 ? run + 1 : 0;
        if (run >= 8) return r + 1 - run;
    }
    return limit;
}

static float MTQuickVerifyMotion(const uint8_t *a, const uint8_t *b, int delta,
                                 const MTQuickWindow *window) {
    int start = window->top, end = window->bottom;
    int supported = 0, informative = 0, bands = 0;
    double total = 0, weights = 0;
    if (end - start < 64) return 255;
    for (int y = start; y < end; y += 3) {
        int currentY = y - delta;
        if (currentY < start || currentY >= end) continue;
        if (MTQuickRowFixed(window, y)) continue;
        const uint8_t *p = a + y * MTQuickScrollSignatureWidth;
        const uint8_t *q = b + currentY * MTQuickScrollSignatureWidth;
        unsigned rowError = 0, rowWeight = 0;
        for (int x = 5; x < MTQuickScrollSignatureWidth - 5; x += 2) {
            int weight = abs((int)p[x] - p[x - 1]);
            int other = abs((int)q[x] - q[x - 1]);
            if (other > weight) weight = other;
            weight -= 4;
            if (weight <= 0) continue;
            rowError += (unsigned)(weight * abs((int)p[x] - q[x])); rowWeight += (unsigned)weight;
        }
        if (rowWeight < 30) continue;
        informative++;
        if ((float)rowError / rowWeight < 24) {
            supported++; bands |= 1 << ((y - start) * 4 / (end - start));
        }
        total += rowError; weights += rowWeight;
    }
    int bandCount = 0;
    for (int v = bands; v; v >>= 1) bandCount += v & 1;
    if (!weights || informative < 16 || supported * 5 < informative * 3 || bandCount < 2) return 255;
    return (float)(total / weights);
}

MTQuickScrollMatch MTQuickScrollMatchFrames(const uint8_t *a, const uint8_t *b, int rows, int predicted,
                                            const MTQuickScrollLimits *limits) {
    MTQuickScrollMatch out = {MTQuickScrollUncertain, 0, 0, 0, rows, 255};
    if (!a || !b || rows < 160 || rows > 16384) return out;
    MTQuickWindow window = MTQuickMakeWindow(rows, limits);
    MTQuickVote votes[MTQuickTemplateCount]; int count = 0, textured = 0, still = 0;
    // All patches avoid the sticky chrome bands, fixed overlays and the outer scrollbar columns.
    int top = window.top, bottom = window.bottom - MTQuickTemplateHeight;
    int maximum = rows * 3 / 5;
    predicted = predicted < -maximum ? -maximum : predicted > maximum ? maximum : predicted;
    for (int band = 0; band < 4; band++) for (int column = 0; column < 3; column++) {
        int y = top + (bottom - top) * band / 3;
        int x = 4 + column * 40;
        if (y < top || y > bottom) continue;
        if (MTQuickPatchTouchesFixed(&window, y)) continue;
        if (!MTQuickPatchHasTexture(a, x, y)) continue;
        textured++;
        if (MTQuickPatchCost(a, b, x, y, 0, 1) <= 1.25f) still++;
        int low = y + MTQuickTemplateHeight - (rows - rows / 12);
        int high = y - rows / 12;
        if (low < -maximum) low = -maximum;
        if (high > maximum) high = maximum;
        float best = 255; int shift = 0;
        for (int d = low; d <= high; d++) {
            float cost = MTQuickPatchCost(a, b, x, y, d, 3);
            if (cost < best) { best = cost; shift = d; }
        }
        if (best > 16) continue;
        // Repeated rows must have a distinct winner outside the same pixel peak.
        float second = 255;
        for (int d = low; d <= high; d++) if (abs(d - shift) > 3) {
            float cost = MTQuickPatchCost(a, b, x, y, d, 3);
            if (cost < second) second = cost;
        }
        if (second - best < fmaxf(0.65f, best * 0.10f)) continue;
        float dense = MTQuickPatchCost(a, b, x, y, shift, 1);
        if (dense <= 18) votes[count++] = (MTQuickVote){shift, band, dense};
    }
    if (textured >= 3 && still * 5 >= textured * 4) {
        out.kind = MTQuickScrollStill; out.error = 0; out.votes = still; return out;
    }
    int winningCount = 0, winningDelta = 0; float winningError = 255, competingError = 255;
    for (int i = 0; i < count; i++) {
        int supporters = 0, sum = 0;
        for (int j = 0; j < count; j++) if (abs(votes[i].delta - votes[j].delta) <= 1) {
            supporters++; sum += votes[j].delta;
        }
        if (supporters < 3) continue;
        int candidate = (int)lroundf((float)sum / supporters);
        float error = MTQuickVerifyMotion(a, b, candidate, &window);
        if (error < winningError) {
            if (abs(candidate - winningDelta) > 3) competingError = winningError;
            winningCount = supporters; winningDelta = candidate; winningError = error;
        } else if (abs(candidate - winningDelta) > 3 && error < competingError) {
            competingError = error;
        }
    }
    // A competing displacement cannot be silently discarded by a majority of blank pixels.
    if (winningCount >= 3 && winningError <= 20 &&
        competingError - winningError < fmaxf(1, winningError * 0.12f)) return out;
    if (winningCount < 3 || winningError > 20) {
        // Sparse/periodic rows can reject every local unique peak. A narrow temporal
        // prediction is only a search range: every candidate still needs dense SAD
        // support and a distinct competing peak. Never infer motion from touch alone.
        if (!predicted) return out;
        int radius = abs(predicted) / 3 + 16;
        if (radius < 24) radius = 24;
        int low = predicted - radius, high = predicted + radius;
        if (low < -maximum) low = -maximum;
        if (high > maximum) high = maximum;
        float best = 255; int candidate = 0;
        for (int d = low; d <= high; d++) {
            float cost = MTQuickVerifyMotion(a, b, d, &window);
            if (cost < best) { best = cost; candidate = d; }
        }
        float second = 255;
        for (int d = low; d <= high; d++) if (abs(d - candidate) > 3) {
            float cost = MTQuickVerifyMotion(a, b, d, &window);
            if (cost < second) second = cost;
        }
        if (best > 16 || second - best < fmaxf(1, best * 0.12f)) return out;
        winningDelta = candidate; winningError = best; winningCount = 0;
    }
    out.kind = abs(winningDelta) <= 1 ? MTQuickScrollStill : MTQuickScrollMoved;
    out.delta = out.kind == MTQuickScrollMoved ? winningDelta : 0;
    out.votes = winningCount; out.error = winningError;
    out.bodyTop = MTQuickStaticEdge(a, b, rows, 0);
    out.bodyBottom = rows - MTQuickStaticEdge(a, b, rows, 1);
    return out;
}

int MTQuickScrollAdvance(MTQuickScrollCoverage *coverage, int delta, int bodyRows, int minimumAppend, int commit) {
    if (!coverage || bodyRows < 1 || minimumAppend < 1 || coverage->frontier < 0 ||
        (delta > 0 && coverage->position > INT64_MAX - delta) ||
        (delta < 0 && coverage->position < INT64_MIN - delta)) return -1;
    int64_t next = coverage->position + delta;
    if (next <= coverage->frontier) { coverage->position = next; return 0; }
    int64_t advance = next - coverage->frontier;
    // Keep the last valid position on a gap; the caller must reacquire overlap.
    if (advance >= bodyRows) return -1;
    coverage->position = next;
    if (advance < minimumAppend || !commit) return 0;
    coverage->frontier = next;
    return (int)advance;
}

unsigned MTQuickScrollRowDifference(const uint8_t *previous, const uint8_t *current,
                                    int rows, int row) {
    if (!previous || !current || row < 0 || row >= rows) return 255;
    const uint8_t *a = previous + row * MTQuickScrollSignatureWidth;
    const uint8_t *b = current + row * MTQuickScrollSignatureWidth;
    unsigned sum = 0;
    for (int x = 4; x < MTQuickScrollSignatureWidth - 4; x++)
        sum += (unsigned)abs((int)a[x] - b[x]);
    return sum / (MTQuickScrollSignatureWidth - 8);
}

int MTQuickScrollSeamRow(const uint8_t *previous, const uint8_t *current, int rows, int delta,
                         int preferred, int low, int high, const MTQuickScrollLimits *limits) {
    if (!previous || !current || rows < 8) return preferred;
    low = MAX(2, low); high = MIN(rows - 3, high);
    if (low > high) return preferred;
    MTQuickWindow window = MTQuickMakeWindow(rows, limits);
    int best = MIN(MAX(preferred, low), high);
    float bestCost = HUGE_VALF;
    for (int y = low; y <= high; y++) {
        unsigned amplitude = 0, agreement = 0, columns = 0;
        int fixedHits = 0;
        for (int r = y - 2; r <= y + 2; r++) {
            const uint8_t *row = current + r * MTQuickScrollSignatureWidth;
            uint8_t lowValue = 255, highValue = 0;
            for (int x = 4; x < MTQuickScrollSignatureWidth - 4; x += 2) {
                if (row[x] < lowValue) lowValue = row[x];
                if (row[x] > highValue) highValue = row[x];
            }
            amplitude += highValue - lowValue;
            if (MTQuickRowFixed(&window, r)) fixedHits++;
            // Agreement needs the same content in the reference: current row r
            // was at reference row r + delta. New bottom content has no sample.
            int source = r + delta;
            if (source >= 0 && source < rows) {
                const uint8_t *reference = previous + source * MTQuickScrollSignatureWidth;
                for (int x = 4; x < MTQuickScrollSignatureWidth - 4; x += 2) {
                    agreement += (unsigned)abs((int)row[x] - reference[x]); columns++;
                }
            }
        }
        float cost = (float)amplitude * 0.30f;
        if (columns) cost += (float)agreement / columns * 4.0f;
        cost += fixedHits * 60.0f + fabsf((float)(y - preferred)) * 0.05f;
        if (cost < bestCost) { bestCost = cost; best = y; }
    }
    return best;
}

int MTQuickScrollTrailingQuietRows(const uint8_t *signature, int rows, int from, int to) {
    if (!signature || rows < 1) return 0;
    from = MAX(0, from); to = MIN(rows, to);
    int run = 0;
    for (int r = to - 1; r >= from; r--) {
        const uint8_t *row = signature + r * MTQuickScrollSignatureWidth;
        uint8_t lowValue = 255, highValue = 0;
        for (int x = 6; x < MTQuickScrollSignatureWidth - 6; x++) {
            if (row[x] < lowValue) lowValue = row[x];
            if (row[x] > highValue) highValue = row[x];
        }
        if (highValue - lowValue > 8) break;
        run++;
    }
    return run;
}

int MTQuickScrollIndicatorVisible(const uint8_t *previous, const uint8_t *current,
                                  int rows, int delta, int bodyTop, int bodyBottom) {
    if (!previous || !current || rows < 8) return 0;
    bodyTop = MAX(0, bodyTop); bodyBottom = MIN(rows, bodyBottom);
    if (bodyBottom - bodyTop < 64) return 0;
    unsigned interior = 0, edge = 0, samples = 0;
    int interiorColumn = MTQuickScrollSignatureWidth - 8, edgeColumn = MTQuickScrollSignatureWidth - 2;
    for (int r = bodyTop; r < bodyBottom; r += 4) {
        int source = r + delta;
        if (source < bodyTop || source >= bodyBottom) continue;
        const uint8_t *row = current + r * MTQuickScrollSignatureWidth;
        const uint8_t *reference = previous + source * MTQuickScrollSignatureWidth;
        interior += (unsigned)abs((int)row[interiorColumn] - reference[interiorColumn]);
        edge += (unsigned)abs((int)row[edgeColumn] - reference[edgeColumn]);
        samples++;
    }
    if (samples < 16) return 0;
    unsigned interiorError = interior / samples, edgeError = edge / samples;
    return interiorError <= 6 && edgeError >= 14;
}
