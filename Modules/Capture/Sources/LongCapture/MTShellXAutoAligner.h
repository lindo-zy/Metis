#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// SHELLX 自动拼接专用匹配结果：区分不确定、反向与尺寸异常，
/// 会话据此走原地重抓或有限回滑恢复，不再把一切失败折叠成"重叠不足"。
typedef NS_ENUM(NSInteger, MTShellXAutoMatchKind) {
    MTShellXAutoMatchUncertain,
    MTShellXAutoMatchDuplicate,
    MTShellXAutoMatchForward,
    MTShellXAutoMatchReverse,
    MTShellXAutoMatchSizeMismatch
};

typedef struct {
    MTShellXAutoMatchKind kind;
    NSInteger shiftRows;     // Forward：cur 正文行 c 与 prev 正文行 c+shiftRows 对齐（正文相对坐标）
    CGFloat confidence;      // 密集复验均值差 ≤3.0 为 1.0、≤5.0 为 0.6；Duplicate 恒为 1.0
    NSInteger bodyTop;       // 本次匹配使用的正文边界（绝对行号，含头不含尾）
    NSInteger bodyBottom;
    BOOL boundsValid;
} MTShellXAutoMatchResult;

/// priorTop/priorBottom 为上一确认帧的正文边界（绝对行号；<0 表示无先验）。
/// 固定栏在相邻帧之间不动，先验边界直接进入"仅比较正文"的显式匹配；
/// 与容错识别结果相差 ≤8 行时跟随缓慢漂移，分歧过大时信先验。
/// 无先验时先做容错边界识别，仍不确定再回退全帧识别管线。
MTShellXAutoMatchResult MTShellXAutoMatchFrames(const uint8_t *prev, NSInteger prevRows,
                                                const uint8_t *cur, NSInteger curRows,
                                                NSInteger priorTop, NSInteger priorBottom);

NS_ASSUME_NONNULL_END
