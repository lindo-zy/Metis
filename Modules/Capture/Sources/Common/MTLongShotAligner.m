#import "MTLongShotAligner.h"
#import <math.h>
#import <stdlib.h>
const NSInteger MTLongShotSigWidth = 64;

void MTLongShotComputeRowSignature(const uint8_t *buffer,
                                   NSInteger pixelWidth,
                                   NSInteger bytesPerRow,
                                   NSInteger row,
                                   uint8_t *outSig) {
    const uint8_t *line = buffer + row * bytesPerRow;
    CGFloat stride = (CGFloat)MAX(pixelWidth, 1) / (CGFloat)MTLongShotSigWidth;
    for (NSInteger c = 0; c < MTLongShotSigWidth; c++) {
        NSInteger x0 = (NSInteger)((CGFloat)c * stride);
        NSInteger x1 = MIN(x0 + 1, pixelWidth - 1);
        NSInteger x2 = MIN(x0 + 2, pixelWidth - 1);
        // RGBA8：3 点横向均值亮度，抑制 JPEG 噪声与亚像素锯齿。
        uint32_t sum = 0;
        const NSInteger xs[3] = {x0, x1, x2};
        for (NSInteger i = 0; i < 3; i++) {
            const uint8_t *p = line + xs[i] * 4;
            sum += (uint32_t)((77 * p[0] + 150 * p[1] + 29 * p[2]) >> 8);
        }
        outSig[c] = (uint8_t)(sum / 3);
    }
}

BOOL MTLongShotSignaturesAreDuplicate(const uint8_t *prevSigs, NSInteger prevRows,
                                     const uint8_t *curSigs, NSInteger curRows) {
    if (!prevSigs || !curSigs || prevRows <= 0 || prevRows != curRows) return NO;
    size_t count = (size_t)prevRows * MTLongShotSigWidth;
    uint64_t total = 0;
    size_t changed = 0;
    for (size_t i = 0; i < count; i++) {
        uint8_t diff = prevSigs[i] > curSigs[i] ? prevSigs[i] - curSigs[i] : curSigs[i] - prevSigs[i];
        total += diff;
        if (diff > 12) changed++;
    }
    return (CGFloat)total / (CGFloat)count <= 0.75 && (CGFloat)changed / (CGFloat)count <= 0.02;
}


// 中部列用于运动估计，减小边缘时钟、滚动条和视频角标的干扰。
// 密集验证每 4 行取一采样；主流设备签名行数 ≤2900，容量 768 足够覆盖，
// 超出时按容量截断采样（仅极端分辨率下降低采样密度，不影响正确性）。
#define MTLongShotDenseSampleCap 768
static int MTLongShotFloatCompare(const void *a, const void *b) {
    CGFloat x = *(const CGFloat *)a, y = *(const CGFloat *)b;
    return x < y ? -1 : (x > y ? 1 : 0);
}

CGFloat MTLongShotRowDifference(const uint8_t *a, const uint8_t *b) {
    NSUInteger sum = 0;
    for (NSInteger c = 8; c < 56; c++) sum += abs((int)a[c] - (int)b[c]);
    return (CGFloat)sum / 48.0;
}

// 截尾均值：丢弃最差 25% 样本后取均值。折叠标题、半透明底栏下滚动的内容、
// 局部动画只污染少数行，朴素均值会被它们拖过 8.0 门槛把正确位移判成失败；
// 截尾后少数脏行不再影响判分，整体错位（半数以上行不同）仍被拒绝。
static CGFloat MTTrimmedMean(CGFloat *samples, NSInteger count) {
    if (count <= 0) return CGFLOAT_MAX;
    qsort(samples, (size_t)count, sizeof(CGFloat), MTLongShotFloatCompare);
    NSInteger keep = count - count / 4;
    CGFloat total = 0;
    for (NSInteger i = 0; i < keep; i++) total += samples[i];
    return total / (CGFloat)keep;
}

static CGFloat MTShiftCost(const uint8_t *prev, const uint8_t *cur, NSInteger rows, NSInteger delta) {
    NSInteger overlap = rows - delta;
    if (overlap < 64) return CGFLOAT_MAX;
    CGFloat samples[32];
    // 全重叠带分布采样，不能仅拿固定页头或顶部白底作为锚点。
    for (NSInteger s = 0; s < 32; s++) {
        NSInteger r = (2 * s + 1) * overlap / 64;
        const uint8_t *a = prev + (r + delta) * MTLongShotSigWidth;
        const uint8_t *b = cur + r * MTLongShotSigWidth;
        NSUInteger sum = 0;
        for (NSInteger c = 8; c < 56; c += 3) sum += abs((int)a[c] - (int)b[c]);
        samples[s] = (CGFloat)sum / 16.0;
    }
    return MTTrimmedMean(samples, 32);
}

static NSInteger MTFindShift(const uint8_t *prev, const uint8_t *cur, NSInteger rows, CGFloat *cost) {
    CGFloat *costs = malloc((size_t)rows * sizeof(CGFloat));
    if (!costs) return 0;
    NSInteger bestDelta = 0;
    CGFloat best = CGFLOAT_MAX;
    for (NSInteger d = 3; d <= rows - 64; d++) {
        costs[d] = CGFLOAT_MAX;
        if (MTShiftCost(prev, cur, rows, d) > 8.0) continue;
        // 稀疏页上多个粗候选可能全部落在白底；先密集验证每个候选，再比较独立匹配峰。
        NSInteger overlap = rows - d;
        NSInteger count = MIN(MAX((overlap + 3) / 4, 1), MTLongShotDenseSampleCap);
        CGFloat samples[MTLongShotDenseSampleCap];
        NSInteger n = 0;
        for (NSInteger r = 0; r < overlap && n < count; r += 4)
            samples[n++] = MTLongShotRowDifference(prev + (r + d) * MTLongShotSigWidth,
                                                   cur + r * MTLongShotSigWidth);
        CGFloat v = MTTrimmedMean(samples, n);
        if (v > 8.0) continue;
        costs[d] = v;
        if (v < best) { best = v; bestDelta = d; }
    }
    CGFloat second = CGFLOAT_MAX;
    for (NSInteger d = 3; d <= rows - 64; d++) {
        if (labs(d - bestDelta) <= 3) continue;
        second = MIN(second, costs[d]);
    }
    free(costs);
    if (!bestDelta || second - best < 1.5) return 0;
    *cost = best;
    return bestDelta;
}

// 首次严格识别失败时允许固定栏中的局部状态图标/压缩噪声；连续 8 行的均值
// 必须稳定。此宽容只用于候选正文边界，位移仍受完整重叠验证和独立次峰约束。
static NSInteger MTStableEdge(const uint8_t *prev, const uint8_t *cur, NSInteger rows, BOOL bottom) {
    NSInteger limit = bottom ? rows / 4 : rows / 3;
    for (NSInteger r = 0; r < limit; r++) {
        CGFloat cost = 0;
        for (NSInteger j = 0; j < 8; j++) {
            NSInteger y = bottom ? rows - 1 - r - j : r + j;
            cost += MTLongShotRowDifference(prev + y * MTLongShotSigWidth, cur + y * MTLongShotSigWidth);
        }
        if (cost / 8 > 5.0) {
            // 窗口前瞻找到边界后逐行精化，避免每一段残留 7 行固定页脚。
            while (r < limit) {
                NSInteger y = bottom ? rows - 1 - r : r;
                if (MTLongShotRowDifference(prev + y * MTLongShotSigWidth, cur + y * MTLongShotSigWidth) > 5.0) break;
                r++;
            }
            return r;
        }
    }
    return limit;
}

static MTLongShotFrameMatch MTMatchWithBounds(const uint8_t *prev, const uint8_t *cur,
                                             NSInteger rows, NSInteger fixedTop, NSInteger fixedBottom) {
    MTLongShotFrameMatch result = {MTLongShotMatchUncertain, 0, 0, 0};
    if (!prev || !cur || rows < 128) return result;
    NSInteger top = MAX(0, fixedTop), bottom = MAX(0, fixedBottom);
    if (fixedTop < 0 || fixedBottom < 0) {
        // 仅固定的连续首尾条带可排除；超过上限说明静止或无法辨认正文。
        if (MTLongShotSignaturesAreDuplicate(prev, rows, cur, rows)) {
            result.kind = MTLongShotMatchDuplicate;
            return result;
        }
        // 边界识别直接用容错版（8 行均值 + 逐行精化）：严格单行版会把含时钟/
        // 动态图标的导航栏提前截进正文，截尾均值能容忍这些行但报告的正文
        // 范围会偏大，步长与切片边界都跟着失真。
        if (fixedTop < 0) top = MTStableEdge(prev, cur, rows, NO);
        if (fixedBottom < 0) bottom = MTStableEdge(prev, cur, rows, YES);
    }
    if (top > rows / 3 || bottom > rows / 4 || rows - top - bottom < 128) return result;
    result.fixedTopRows = top;
    result.fixedBottomRows = bottom;
    const uint8_t *a = prev + top * 64, *b = cur + top * 64;
    NSInteger bodyRows = rows - top - bottom;
    if (MTLongShotSignaturesAreDuplicate(a, bodyRows, b, bodyRows)) {
        result.kind = MTLongShotMatchDuplicate;
        return result;
    }
    CGFloat forwardCost = CGFLOAT_MAX, reverseCost = CGFLOAT_MAX;
    NSInteger forward = MTFindShift(a, b, bodyRows, &forwardCost);
    NSInteger reverse = MTFindShift(b, a, bodyRows, &reverseCost);
    if (forward && (!reverse || forwardCost + 1.5 < reverseCost)) {
        result.kind = MTLongShotMatchForward;
        result.shiftRows = forward;
    } else if (reverse && (!forward || reverseCost + 1.5 < forwardCost)) {
        result.kind = MTLongShotMatchReverse;
        result.shiftRows = reverse;
    }
    if (result.kind == MTLongShotMatchUncertain && (fixedTop < 0 || fixedBottom < 0)) {
        NSInteger tolerantTop = fixedTop < 0 ? MTStableEdge(prev, cur, rows, NO) : top;
        NSInteger tolerantBottom = fixedBottom < 0 ? MTStableEdge(prev, cur, rows, YES) : bottom;
        if (tolerantTop != top || tolerantBottom != bottom)
            return MTMatchWithBounds(prev, cur, rows, tolerantTop, tolerantBottom);
    }
    return result;
}

MTLongShotFrameMatch MTLongShotMatchFrames(const uint8_t *prev, const uint8_t *cur,
                                          NSInteger rows, NSInteger fixedTop, NSInteger fixedBottom) {
    MTLongShotFrameMatch result = MTMatchWithBounds(prev, cur, rows, fixedTop, fixedBottom);
    if (!prev || !cur || rows < 128 || fixedTop >= 0) return result;

    // 多正文起点独立验证，两种用途：
    // 1) 主结果不确定（大标题折叠、搜索栏收起、状态栏数字变化让静止检测
    //    在顶部提前结束）：至少两个起点给出同一位移才接纳，不放宽像素匹配
    //    与次峰阈值；无重叠、空白或周期列表仍返回 Uncertain 交由会话恢复。
    // 2) 主结果已确认（截尾均值容忍了少数脏行）：把与位移一致的更大固定
    //    条带并入报告范围——含时钟的导航栏、内容在其下滚动的半透明底栏
    //    不能留在正文里，否则步长估计与到底判定都被这些行污染。
    const NSInteger divisors[] = {12, 8, 6, 4, 3};
    MTLongShotFrameMatch candidate = result;
    BOOL confirmed = (result.kind == MTLongShotMatchForward || result.kind == MTLongShotMatchReverse);
    NSInteger bottom = fixedBottom >= 0 ? fixedBottom : result.fixedBottomRows;
    for (NSUInteger i = 0; i < sizeof(divisors) / sizeof(divisors[0]); i++) {
        MTLongShotFrameMatch match = MTMatchWithBounds(prev, cur, rows, rows / divisors[i], bottom);
        if (match.kind != MTLongShotMatchForward && match.kind != MTLongShotMatchReverse) continue;
        if (candidate.kind == match.kind && labs(candidate.shiftRows - match.shiftRows) <= 1) {
            if (!confirmed) {
                result = candidate;
                confirmed = YES;
            } else if (result.kind == match.kind && labs(result.shiftRows - match.shiftRows) <= 1) {
                result.fixedTopRows = MAX(result.fixedTopRows, match.fixedTopRows);
                result.fixedBottomRows = MAX(result.fixedBottomRows, match.fixedBottomRows);
            }
            continue;
        }
        candidate = match;
    }
    if (!confirmed || fixedBottom >= 0) return result;
    for (NSUInteger i = 0; i < 4; i++) {
        // 底栏同样按一致性扩大排除（rows/3 超出底栏上限，最大取 rows/4）。
        MTLongShotFrameMatch match = MTMatchWithBounds(prev, cur, rows, result.fixedTopRows, rows / divisors[i]);
        if ((match.kind == MTLongShotMatchForward || match.kind == MTLongShotMatchReverse) &&
            match.kind == result.kind && labs(match.shiftRows - result.shiftRows) <= 1)
            result.fixedBottomRows = MAX(result.fixedBottomRows, match.fixedBottomRows);
    }
    return result;
}
