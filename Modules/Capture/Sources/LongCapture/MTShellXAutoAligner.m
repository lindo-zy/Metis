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

MTShellXAutoMatchResult MTShellXAutoMatchFrames(const uint8_t *prev, NSInteger prevRows,
                                                const uint8_t *cur, NSInteger curRows,
                                                NSInteger priorTop, NSInteger priorBottom) {
    MTShellXAutoMatchResult out = {MTShellXAutoMatchUncertain, 0, 0, -1.0, 0, 0, NO};
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
    if (match.kind == MTLongShotMatchUncertain) return out;
    MTShellXAutoFillFromMatch(&out, match, rows, prev, cur);
    return out;
}
