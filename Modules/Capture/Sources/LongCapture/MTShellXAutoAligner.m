#import "MTShellXAutoAligner.h"
#import "../Common/MTLongShotAligner.h"
#import <math.h>
#import <stdlib.h>

// 白底列表不能用“最相似的 75% 行”判位移：它会删掉文字，只留下白底，
// 多个位移都得到零分。这里仅让有横向结构的像素投票；空白既不加分也不
// 增加置信度。日期、文件名、图标等必须在分散的正文区域共同确认位移。
static const CGFloat MTFeatureErrorLimit = 24.0;
static const NSInteger MTSignatureRowLimit = 16384;

typedef struct {
    CGFloat error;
    NSInteger informativeRows;
    NSInteger supportedRows;
    NSInteger bands;
} MTFeatureScore;

static MTFeatureScore MTScoreShift(const uint8_t *prev, const uint8_t *cur,
                                   NSInteger rows, NSInteger delta, NSInteger stride) {
    MTFeatureScore out = {CGFLOAT_MAX, 0, 0, 0};
    NSInteger shift = labs(delta);
    // 固定的中部搜索带独立于静止栏检测；标题折叠/时钟变化不能锁死正文先验。
    NSInteger top = rows / 5, bottom = rows - rows / 8;
    NSInteger overlap = bottom - top - shift;
    if (overlap < MAX(64, rows / 10)) return out;
    const uint8_t *a = delta >= 0 ? prev : cur;
    const uint8_t *b = delta >= 0 ? cur : prev;
    uint64_t total = 0, weights = 0;
    NSUInteger bands = 0;
    for (NSInteger r = 0; r < overlap; r += stride) {
        const uint8_t *x = a + (top + r + shift) * MTLongShotSigWidth;
        const uint8_t *y = b + (top + r) * MTLongShotSigWidth;
        NSUInteger rowTotal = 0, rowWeight = 0;
        // 略去屏幕最外侧，避开滚动条、边缘手势与圆角。
        for (NSInteger c = 4; c < MTLongShotSigWidth - 4; c++) {
            NSInteger weight = MAX(abs(x[c] - x[c - 1]), abs(y[c] - y[c - 1])) - 5;
            if (weight <= 0) continue;
            rowWeight += weight;
            rowTotal += (NSUInteger)weight * abs(x[c] - y[c]);
        }
        if (rowWeight < 64) continue;
        out.informativeRows++;
        total += rowTotal; weights += rowWeight;
        if ((CGFloat)rowTotal / rowWeight <= MTFeatureErrorLimit) {
            out.supportedRows++;
            bands |= (NSUInteger)1 << MIN(3, r * 4 / overlap);
        }
    }
    for (NSUInteger b = bands; b; b >>= 1) out.bands += b & 1;
    if (weights && out.informativeRows >= MAX(8, 24 / stride)) out.error = (CGFloat)total / weights;
    return out;
}

// 栏边界只决定裁带接缝，不决定运动候选。连续 8 行变化才结束静止条带，
// 跨过时钟等孤立异动；接缝选在正文中，末帧仍保留其下全部内容。
static NSInteger MTStillEdge(const uint8_t *prev, const uint8_t *cur, NSInteger rows, BOOL bottom) {
    NSInteger limit = bottom ? rows / 4 : rows / 3;
    NSInteger run = 0;
    for (NSInteger r = 0; r < limit; r++) {
        NSInteger y = bottom ? rows - 1 - r : r;
        CGFloat diff = MTLongShotRowDifference(prev + y * MTLongShotSigWidth, cur + y * MTLongShotSigWidth);
        run = diff > 2.0 ? run + 1 : 0;
        if (run >= 8) return r + 1 - run;
    }
    return limit;
}

BOOL MTShellXAutoSignaturesAreStable(const uint8_t *prev, NSInteger prevRows,
                                    const uint8_t *cur, NSInteger curRows) {
    if (!prev || !cur || prevRows != curRows || prevRows < 128 || prevRows > MTSignatureRowLimit) return NO;
    // 只比较正文，状态栏秒数、标题动画和底部工具栏不延长等待。
    NSInteger top = prevRows / 5, bottom = prevRows - prevRows / 8;
    return MTLongShotSignaturesAreDuplicate(prev + top * MTLongShotSigWidth, bottom - top,
                                           cur + top * MTLongShotSigWidth, bottom - top);
}

MTShellXAutoMatchResult MTShellXAutoMatchFrames(const uint8_t *prev, NSInteger prevRows,
                                              const uint8_t *cur, NSInteger curRows,
                                              NSInteger priorTop, NSInteger priorBottom) {
    MTShellXAutoMatchResult out = {MTShellXAutoMatchUncertain, 0, 0, -1.0, 0, 0, NO, NO, -1, -1};
    if (!prev || !cur) return out;
    if (prevRows != curRows || prevRows < 128 || prevRows > MTSignatureRowLimit) {
        out.kind = MTShellXAutoMatchSizeMismatch;
        return out;
    }
    NSInteger rows = prevRows;
    BOOL prior = priorTop >= 0 && priorTop < rows && priorBottom > priorTop &&
        priorBottom <= rows && priorBottom - priorTop >= 128;
    NSInteger top = prior ? priorTop : MTStillEdge(prev, cur, rows, NO);
    NSInteger bottom = prior ? priorBottom : rows - MTStillEdge(prev, cur, rows, YES) - MAX(4, rows / 240);
    // 零位移先严格验证，正文静止而工具栏变化与真正到底分开交给会话。
    if (MTShellXAutoSignaturesAreStable(prev, rows, cur, rows)) {
        out.kind = MTShellXAutoMatchDuplicate;
        out.confidence = 1.0; out.denseError = 0;
        out.bodyTop = top; out.bodyBottom = bottom; out.boundsValid = YES;
        out.chromeChanged = !MTLongShotSignaturesAreDuplicate(prev, rows, cur, rows);
        return out;
    }
    NSInteger maxShift = (rows - rows / 8) - rows / 5 - MAX(64, rows / 10);
    if (maxShift < 3) return out;
    CGFloat *costs = malloc((size_t)(maxShift * 2 + 1) * sizeof(CGFloat));
    if (!costs) return out;
    CGFloat best = CGFLOAT_MAX;
    NSInteger bestDelta = 0;
    for (NSInteger delta = -maxShift; delta <= maxShift; delta++) {
        MTFeatureScore score = MTScoreShift(prev, cur, rows, delta, 3);
        costs[delta + maxShift] = score.error;
        if (score.error < best) { best = score.error; bestDelta = delta; }
    }
    CGFloat second = CGFLOAT_MAX;
    for (NSInteger delta = -maxShift; delta <= maxShift; delta++) {
        // 相邻像素的抗锯齿峰属于同一候选；其他行周期必须独立竞争。
        if (labs(delta - bestDelta) > 4) second = MIN(second, costs[delta + maxShift]);
    }
    free(costs);
    if (labs(bestDelta) < 3 || best > MTFeatureErrorLimit ||
        second - best < MAX(3.0, best * 0.25)) return out;
    MTFeatureScore verified = MTScoreShift(prev, cur, rows, bestDelta, 1);
    if (verified.error > MTFeatureErrorLimit || verified.bands < 3 ||
        verified.supportedRows < verified.informativeRows * 0.60) return out;
    // 固定栏的估计可更新，但已入账记录不可被下一次配对改写。
    out.kind = bestDelta > 0 ? MTShellXAutoMatchForward : MTShellXAutoMatchReverse;
    out.shiftRows = labs(bestDelta);
    out.denseError = verified.error;
    out.confidence = MAX(0, 1.0 - verified.error / (MTFeatureErrorLimit * 2));
    out.bodyTop = top; out.bodyBottom = bottom; out.boundsValid = bottom - top >= 128;
    return out;
}
