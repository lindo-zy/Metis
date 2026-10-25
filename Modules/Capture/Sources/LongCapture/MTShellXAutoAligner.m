#import "MTShellXAutoAligner.h"
#import "../Common/MTLongShotAligner.h"
#import <stdlib.h>

// 固定栏判定：3 行平滑差值过 2.0 阈值，孤立异动行（时钟/角标/压缩噪声）被窗口稀释；
// 正文边界之后要求连续 8 行不稳，避免把短异动带尾迹误当正文起点。
static const CGFloat MTShellXAutoStillThreshold = 2.0;
static const NSInteger MTShellXAutoEdgeStableRows = 8;
static const NSInteger MTShellXAutoPriorDriftRows = 8;
static const NSInteger MTShellXAutoMinBodyRows = 128;

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

// 正文重叠带每 4 行密集复验，返回平均行差；主峰通过了粗匹配仍可能整体偏移，
// 这里用密集采样把"低误差静止帧"和"错误位移"拦下来。
static CGFloat MTShellXAutoDenseVerify(const uint8_t *x, const uint8_t *y, NSInteger rows,
                                       NSInteger fixedTop, NSInteger fixedBottom, NSInteger shift) {
    NSInteger overlap = (rows - fixedTop - fixedBottom) - shift;
    if (shift <= 0 || overlap < 64) return CGFLOAT_MAX;
    const uint8_t *a = x + fixedTop * MTLongShotSigWidth;
    const uint8_t *b = y + fixedTop * MTLongShotSigWidth;
    CGFloat total = 0;
    NSInteger count = 0;
    for (NSInteger r = 0; r < overlap; r += 4) {
        total += MTLongShotRowDifference(a + (r + shift) * MTLongShotSigWidth,
                                         b + r * MTLongShotSigWidth);
        count++;
    }
    return count ? total / count : CGFLOAT_MAX;
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
    out->confidence = err <= 3.0 ? 1.0 : (err <= 5.0 ? 0.6 : 0.0);
    if (out->confidence == 0.0) {
        out->kind = MTShellXAutoMatchUncertain;   // 密集复验不过：位移不可信，交由会话恢复
        out->boundsValid = NO;
    }
}

MTShellXAutoMatchResult MTShellXAutoMatchFrames(const uint8_t *prev, NSInteger prevRows,
                                                const uint8_t *cur, NSInteger curRows,
                                                NSInteger priorTop, NSInteger priorBottom) {
    MTShellXAutoMatchResult out = {MTShellXAutoMatchUncertain, 0, 0, 0, 0, NO};
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

    MTLongShotFrameMatch match = MTLongShotMatchFrames(prev, cur, rows, fixedTop, fixedBottom);
    if (match.kind == MTLongShotMatchUncertain && havePrior &&
        (fixedTop != detectedTop || fixedBottom != detectedBottom) &&
        MTShellXAutoBoundsUsable(detectedTop, detectedBottom, rows)) {
        // 先验信不过（栏高突变/遮挡）：换容错识别结果重试一次
        match = MTLongShotMatchFrames(prev, cur, rows, detectedTop, detectedBottom);
    }
    if (match.kind == MTLongShotMatchUncertain && !havePrior) {
        // 首次配对无先验：回退全帧识别管线（含多正文起点交叉验证）
        match = MTLongShotMatchFrames(prev, cur, rows, -1, -1);
    }
    if (match.kind == MTLongShotMatchUncertain) return out;
    MTShellXAutoFillFromMatch(&out, match, rows, prev, cur);
    return out;
}
