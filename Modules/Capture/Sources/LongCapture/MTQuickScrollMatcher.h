#pragma once
#include <stdint.h>

// Horizontal grayscale samples, retaining every original vertical pixel.
// Pure C so the same matcher and coverage accounting can be replayed on the host.
enum { MTQuickScrollSignatureWidth = 128 };
typedef enum {
    MTQuickScrollUncertain, MTQuickScrollStill, MTQuickScrollMoved
} MTQuickScrollMatchKind;

/// 跨帧累积的正文区域约束：吸顶/吸底与固定悬浮元素（同位置跨帧不动的行）
/// 不参与匹配投票，接缝与条带也避开这些行。
typedef struct {
    int stickyTop;              // [0, stickyTop) 为吸顶固定区（绝对行）
    int stickyBottom;           // [stickyBottom, rows) 为吸底固定区
    const uint8_t *fixedRows;   // 每行同位置静止 streak（可空）
    int fixedThreshold;         // streak 达到该值视为固定悬浮元素
} MTQuickScrollLimits;

typedef struct {
    MTQuickScrollMatchKind kind;
    int delta;                 // Positive: content moved upwards.
    int votes;
    int bodyTop, bodyBottom;   // Top-origin native pixel rows.
    float error;
} MTQuickScrollMatch;

MTQuickScrollMatch MTQuickScrollMatchFrames(const uint8_t *previous, const uint8_t *current,
                                            int rows, int predictedDelta,
                                            const MTQuickScrollLimits *limits);

typedef struct { int64_t position, frontier; } MTQuickScrollCoverage;
// Tracking includes backwards motion. Only extending the frontier adds pixels.
// Returns -1 if the unrecorded span no longer fits inside the current body.
int MTQuickScrollAdvance(MTQuickScrollCoverage *coverage, int delta, int bodyRows,
                         int minimumAppend, int commit);

/// 同位置行差异（内部列均值）：驱动固定悬浮行的 streak 累积。
unsigned MTQuickScrollRowDifference(const uint8_t *previous, const uint8_t *current,
                                    int rows, int row);
/// 接缝选择：在 [low, high] 内优先安静（近空白）且避开固定行的行，向 preferred 收敛。
/// previous 为参考签名、current 为当前签名；delta 与匹配结果同号（正=内容上移）。
int MTQuickScrollSeamRow(const uint8_t *previous, const uint8_t *current, int rows, int delta,
                         int preferred, int low, int high, const MTQuickScrollLimits *limits);
/// [from, to) 行区间内自底部向上的连续安静行数（空白尾部裁剪依据）。
int MTQuickScrollTrailingQuietRows(const uint8_t *signature, int rows, int from, int to);
/// 右缘滚动条可见性：对齐后内部列一致而最右列异常变化即视为指示条入画。
int MTQuickScrollIndicatorVisible(const uint8_t *previous, const uint8_t *current,
                                  int rows, int delta, int bodyTop, int bodyBottom);
