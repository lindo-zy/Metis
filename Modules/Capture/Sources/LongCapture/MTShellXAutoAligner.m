#import "MTShellXAutoAligner.h"
#import "../Common/MTLongShotAligner.h"
#import <stdlib.h>

// 固定栏判定：3 行平滑差值过 2.0 阈值，孤立异动行（时钟/角标/压缩噪声）被窗口稀释；
// 正文边界之后要求连续 8 行不稳，避免把短异动带尾迹误当正文起点。
static const CGFloat MTShellXAutoStillThreshold = 2.0;
static const NSInteger MTShellXAutoEdgeStableRows = 8;
static const NSInteger MTShellXAutoPriorDriftRows = 8;
static const NSInteger MTShellXAutoMinBodyRows = 128;
// 中位行差超过此值说明位移整体没有对上（粗大错位兜底），远宽于底层匹配器
// 自身的接受门槛，正常内容不会触到。
static const CGFloat MTShellXAutoGrossErrorCap = 12.0;

static CGFloat MTShellXAutoSmoothedDifference(const uint8_t *prev, const uint8_t *cur,
                                              NSInteger rows, NSInteger r, BOOL bottom) {
    CGFloat total = 0;
    NSInteger n = 0;
    for (NSInteger j = 0; j < 3; j++) {
        NSInteger y = bottom ? rows - 1 - r - j : r + j;
        if (y < 0 || y >= rows) break;
        total += MTLongShotRowDifference(prev + y * MTLongShotSigWidth, cur + y * MTLongShotSigWidth);
        n++;
    }
    return n ? total / n : CGFLOAT_MAX;
}

// 返回固定行数（自顶/自底）。与 MTStableEdge 同形，但差值经平滑、
// 边界后要求连续不稳定行，抗单行动态内容。
static NSInteger MTShellXAutoDetectEdge(const uint8_t *prev, const uint8_t *cur,
                                        NSInteger rows, BOOL bottom) {
    NSInteger limit = bottom ? rows / 4 : rows / 3;
    NSInteger r = 0;
    while (r < limit) {
        if (MTShellXAutoSmoothedDifference(prev, cur, rows, r, bottom) <= MTShellXAutoStillThreshold) {
            r++;
            continue;
        }
        NSInteger unstable = 0;
        while (r + unstable < limit &&
               MTShellXAutoSmoothedDifference(prev, cur, rows, r + unstable, bottom) > MTShellXAutoStillThreshold)
            unstable++;
        if (unstable >= MTShellXAutoEdgeStableRows || r + unstable >= limit) return r;
        r += unstable;   // 短异动带（刷新指示等）：跨过继续算固定段
    }
    return limit;
}

static BOOL MTShellXAutoBoundsUsable(NSInteger fixedTop, NSInteger fixedBottom, NSInteger rows) {
    return fixedTop >= 0 && fixedBottom >= 0 && fixedTop <= rows / 3 && fixedBottom <= rows / 4 &&
        rows - fixedTop - fixedBottom >= MTShellXAutoMinBodyRows;
}

static int MTShellXAutoFloatCompare(const void *a, const void *b) {
    CGFloat x = *(const CGFloat *)a, y = *(const CGFloat *)b;
    return x < y ? -1 : (x > y ? 1 : 0);
}

// 正文重叠带每 4 行密集复验，返回行差中位数。必须用中位数而不是均值：
// 折叠标题、半透明底栏下滚动的内容、局部动画只污染少数行，均值会被它们
// 拖进 5~8 区间把正确位移判成失败（1.0.4 真机提前停止的根因）；中位数
// 只要有半数行对齐就稳定。
static CGFloat MTShellXAutoDenseVerify(const uint8_t *x, const uint8_t *y, NSInteger rows,
                                       NSInteger fixedTop, NSInteger fixedBottom, NSInteger shift) {
    NSInteger overlap = (rows - fixedTop - fixedBottom) - shift;
    if (shift <= 0 || overlap < 64) return CGFLOAT_MAX;
    NSInteger count = (overlap + 3) / 4;
    CGFloat *diffs = malloc((size_t)count * sizeof(CGFloat));
    if (!diffs) return CGFLOAT_MAX;
    const uint8_t *a = x + fixedTop * MTLongShotSigWidth;
    const uint8_t *b = y + fixedTop * MTLongShotSigWidth;
    NSInteger n = 0;
    for (NSInteger r = 0; r < overlap && n < count; r += 4)
        diffs[n++] = MTLongShotRowDifference(a + (r + shift) * MTLongShotSigWidth,
                                             b + r * MTLongShotSigWidth);
    qsort(diffs, (size_t)n, sizeof(CGFloat), MTShellXAutoFloatCompare);
    CGFloat result = n ? diffs[n / 2] : CGFLOAT_MAX;
    free(diffs);
    return result;
}

static void MTShellXAutoFillFromMatch(MTShellXAutoMatchResult *out, MTLongShotFrameMatch match,
                                      NSInteger rows, const uint8_t *prev, const uint8_t *cur) {
    out->bodyTop = match.fixedTopRows;
    out->bodyBottom = rows - match.fixedBottomRows;
    out->shiftRows = match.shiftRows;
    out->boundsValid = YES;
    if (match.kind == MTLongShotMatchDuplicate) {
        out->kind = MTShellXAutoMatchDuplicate;
        out->confidence = 1.0;   // 沿用严格重复阈值（均值与变动行比例双重约束）
        return;
    }
    // Forward：prev[r+s] ≈ cur[r]；Reverse：cur[r+s] ≈ prev[r]。
    const uint8_t *x = match.kind == MTLongShotMatchForward ? prev : cur;
    const uint8_t *y = match.kind == MTLongShotMatchForward ? cur : prev;
    CGFloat err = MTShellXAutoDenseVerify(x, y, rows, match.fixedTopRows, match.fixedBottomRows, match.shiftRows);
    out->kind = (match.kind == MTLongShotMatchForward) ? MTShellXAutoMatchForward : MTShellXAutoMatchReverse;
    out->denseError = err == CGFLOAT_MAX ? -1.0 : err;
    // 接受门槛交给底层匹配器（行差 ≤8.0 + 独立次峰约束）；这里的置信度只是
    // 参考值。唯一保留的否决是中位行差 >12 的粗大错位——那种位移整体没对上。
    if (err > MTShellXAutoGrossErrorCap) {
        out->kind = MTShellXAutoMatchUncertain;
        out->confidence = 0.0;
        out->boundsValid = NO;
        return;
    }
    out->confidence = err <= 3.0 ? 1.0 : (err <= 8.0 ? 0.6 : 0.3);
}

// 管线判不确定后的专项分类：大标题折叠、地址栏收起这类工具栏动画会改变
// 顶部（或底部）一条带，而正文完全静止——真机 Files 列表实测首次拖动即
// 如此（内容位移 0，仅标题区变化）。此时应报告"正文重复 + 工具栏变化"，
// 会话据此直接再滚一次（标题已折叠，下次拖动能真正滚动），而不是原地
// 重抓或回滑后误停。
// 实现：按行差把行标记为变化/静止（阈值高于边界识别，容忍 JPEG 噪声），
// 在"顶部变化行都落在前 1/3、底部变化行都落在后 1/4"的约束下找最大的
// 静止窗口作为正文；窗口内变化行 ≤5%（容忍列表内稀疏动图/角标），窗口外
// 变化行 ≥8（确有工具栏变化，而非整体静止）。状态栏的零星变化行与标题
// 折叠带同属窗口外，不影响正文。
static const CGFloat MTShellXAutoChromeDiffThreshold = 4.0;
static const NSInteger MTShellXAutoChromeClusterGap = 12;

static MTShellXAutoMatchResult MTShellXAutoClassifyStaticBody(const uint8_t *prev, const uint8_t *cur,
                                                              NSInteger rows) {
    MTShellXAutoMatchResult out = {MTShellXAutoMatchUncertain, 0, 0, -1.0, 0, 0, NO, NO, -1, -1};
    uint8_t *changed = malloc((size_t)rows);
    NSInteger *prefix = malloc((size_t)(rows + 1) * sizeof(NSInteger));
    if (!changed || !prefix) { free(changed); free(prefix); return out; }
    for (NSInteger r = 0; r < rows; r++) {
        CGFloat total = 0;
        NSInteger n = 0;
        for (NSInteger j = -1; j <= 1; j++) {
            NSInteger y = r + j;
            if (y < 0 || y >= rows) continue;
            total += MTLongShotRowDifference(prev + y * MTLongShotSigWidth, cur + y * MTLongShotSigWidth);
            n++;
        }
        changed[r] = (total / n) > MTShellXAutoChromeDiffThreshold;
    }
    prefix[0] = 0;
    for (NSInteger r = 0; r < rows; r++) prefix[r + 1] = prefix[r] + changed[r];

    NSInteger guard = rows - rows / 4;   // 底部变化行只允许出现在 [guard, rows)

    // 候选正文起点 = 每个静态段的起点（0 与每个变化簇的簇尾+1，
    // 簇间隙 ≤12 行合并）。同一段内所有起点给出同一窗口终点，
    // 段首起点窗口最长，故只需按段评估，取全局最大窗口。
    NSInteger bestTop = -1, bestBottom = -1, bestLen = 0;
    NSInteger t = 0;
    while (t <= rows / 3) {
        // 最大静止窗口：prefix[b]-prefix[t] ≤ 0.05(b-t)。该条件对 b 不单调
        //（变化行升、静止行降），从右向左线性找首个同时满足窗口预算与
        // 底部约束的 b。
        CGFloat qt = (CGFloat)prefix[t] - 0.05 * (CGFloat)t;
        NSInteger lo = t;
        for (NSInteger b = rows; b > t; b--) {
            if ((CGFloat)prefix[b] - 0.05 * (CGFloat)b <= qt && prefix[guard] == prefix[b]) { lo = b; break; }
        }
        if (lo - t > bestLen && lo - t >= MTShellXAutoMinBodyRows) {
            bestLen = lo - t; bestTop = t; bestBottom = lo;
        }
        // 推进到下一个静态段起点：跳过当前段（到 lo）、其后一个变化簇
        // （簇间隙 ≤12 行合并）。
        NSInteger y = lo;
        while (y < rows && changed[y]) y++;          // 若窗口因 5% 预算提前停，越过剩余变化行
        NSInteger clusterEnd = y;
        while (y < rows) {
            while (y < rows && !changed[y]) y++;
            if (y >= rows) break;
            NSInteger z = y;
            while (z < rows && changed[z]) z++;
            if (z - y > MTShellXAutoChromeClusterGap) break;   // 间隙过大：新簇
            clusterEnd = z; y = z;
        }
        if (clusterEnd <= t) break;
        t = clusterEnd;
    }
    NSInteger changedOutside = (prefix[rows] - prefix[bestBottom]) + prefix[bestTop];
    out.diagBestLen = bestTop >= 0 ? bestLen : -1;
    out.diagChangedOutside = bestTop >= 0 ? changedOutside : -1;
    free(changed); free(prefix);
    if (bestTop < 0 || bestLen < MTShellXAutoMinBodyRows) return out;
    if (changedOutside < 8) return out;
    out.kind = MTShellXAutoMatchDuplicate;
    out.chromeChanged = YES;
    out.confidence = 1.0;
    out.bodyTop = bestTop;
    out.bodyBottom = bestBottom;
    out.boundsValid = YES;
    return out;
}

MTShellXAutoMatchResult MTShellXAutoMatchFrames(const uint8_t *prev, NSInteger prevRows,
                                                const uint8_t *cur, NSInteger curRows,
                                                NSInteger priorTop, NSInteger priorBottom) {
    MTShellXAutoMatchResult out = {MTShellXAutoMatchUncertain, 0, 0, -1.0, 0, 0, NO, NO, -1, -1};
    if (!prev || !cur) return out;
    if (prevRows != curRows || prevRows < MTShellXAutoMinBodyRows) {
        out.kind = MTShellXAutoMatchSizeMismatch;
        return out;
    }
    NSInteger rows = prevRows;
    BOOL havePrior = priorTop >= 0 && priorBottom > priorTop &&
        priorTop <= rows / 3 && (rows - priorBottom) <= rows / 4 &&
        (priorBottom - priorTop) >= MTShellXAutoMinBodyRows;

    NSInteger detectedTop = MTShellXAutoDetectEdge(prev, cur, rows, NO);
    NSInteger detectedBottom = MTShellXAutoDetectEdge(prev, cur, rows, YES);
    NSInteger fixedTop, fixedBottom;
    if (havePrior) {
        NSInteger priorFixedBottom = rows - priorBottom;
        if (labs(detectedTop - priorTop) <= MTShellXAutoPriorDriftRows &&
            labs(detectedBottom - priorFixedBottom) <= MTShellXAutoPriorDriftRows) {
            fixedTop = detectedTop;
            fixedBottom = detectedBottom;            // 栏高缓慢变化：跟随漂移
        } else {
            fixedTop = priorTop;
            fixedBottom = priorFixedBottom;          // 分歧过大：信上一确认帧的先验
        }
    } else {
        fixedTop = detectedTop;
        fixedBottom = detectedBottom;
    }

    MTLongShotFrameMatch match;
    if (!havePrior) {
        // 首次配对直接走全帧识别管线：容错边界 → 截尾匹配 → 多起点一致性
        // 确认与固定条带扩大，含时钟的导航栏/毛玻璃底栏不会漏进正文范围。
        match = MTLongShotMatchFrames(prev, cur, rows, -1, -1);
    } else {
        match = MTLongShotMatchFrames(prev, cur, rows, fixedTop, fixedBottom);
        if (match.kind == MTLongShotMatchUncertain &&
            (fixedTop != detectedTop || fixedBottom != detectedBottom) &&
            MTShellXAutoBoundsUsable(detectedTop, detectedBottom, rows)) {
            // 先验信不过（栏高突变/遮挡）：换容错识别结果重试一次
            match = MTLongShotMatchFrames(prev, cur, rows, detectedTop, detectedBottom);
        }
    }
    if (match.kind == MTLongShotMatchUncertain)
        return MTShellXAutoClassifyStaticBody(prev, cur, rows);
    MTShellXAutoFillFromMatch(&out, match, rows, prev, cur);
    // 管线给出虚假 Forward 被密集复验降级为 Uncertain 时，同样要尝试
    // "正文静止、工具栏变化"分类——大标题折叠页的典型形态。
    if (out.kind == MTShellXAutoMatchUncertain)
        return MTShellXAutoClassifyStaticBody(prev, cur, rows);
    return out;
}
