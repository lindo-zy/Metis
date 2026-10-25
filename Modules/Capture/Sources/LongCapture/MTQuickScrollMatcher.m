#include "MTQuickScrollMatcher.h"
#include <stdlib.h>
#include <math.h>
#include <limits.h>

enum { MTQuickTemplateCount = 12, MTQuickTemplateHeight = 160, MTQuickTemplateWidth = 40 };
typedef struct { int delta, y; float error; } MTQuickVote;

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

static float MTQuickVerifyMotion(const uint8_t *a, const uint8_t *b, int rows, int delta) {
    int start = rows / 5, end = rows - rows / 7;
    int supported = 0, informative = 0, bands = 0;
    double total = 0, weights = 0;
    for (int y = start; y < end; y += 3) {
        int currentY = y - delta;
        if (currentY < start || currentY >= end) continue;
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

MTQuickScrollMatch MTQuickScrollMatchFrames(const uint8_t *a, const uint8_t *b, int rows, int predicted) {
    MTQuickScrollMatch out = {MTQuickScrollUncertain, 0, 0, 0, rows, 255};
    if (!a || !b || rows < 160 || rows > 16384) return out;
    MTQuickVote votes[MTQuickTemplateCount]; int count = 0, textured = 0, still = 0;
    // All patches avoid the fixed top/bottom chrome and the outer scrollbar columns.
    int top = rows / 5, bottom = rows - rows / 7 - MTQuickTemplateHeight;
    int maximum = rows * 3 / 5;
    predicted = predicted < -maximum ? -maximum : predicted > maximum ? maximum : predicted;
    for (int band = 0; band < 4; band++) for (int column = 0; column < 3; column++) {
        int y = top + (bottom - top) * band / 3;
        int x = 4 + column * 40;
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
        float error = MTQuickVerifyMotion(a, b, rows, candidate);
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
            float cost = MTQuickVerifyMotion(a, b, rows, d);
            if (cost < best) { best = cost; candidate = d; }
        }
        float second = 255;
        for (int d = low; d <= high; d++) if (abs(d - candidate) > 3) {
            float cost = MTQuickVerifyMotion(a, b, rows, d);
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
