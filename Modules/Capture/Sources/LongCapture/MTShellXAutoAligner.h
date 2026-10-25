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
    NSInteger shiftRows;     // Forward：cur 行 y 与 prev 行 y+shiftRows 对齐（原图像素坐标）
    CGFloat confidence;      // 有结构像素的匹配置信度；Duplicate 为 1.0
    CGFloat denseError;      // 有结构像素的加权误差；-1 表示未评估
    NSInteger bodyTop;       // 本次匹配使用的正文边界（绝对行号，含头不含尾）
    NSInteger bodyBottom;
    BOOL boundsValid;
    BOOL chromeChanged;      // Duplicate：正文静止但顶/底工具栏变化（大标题折叠、地址栏收起）
    NSInteger diagBestLen;       // 诊断：静态正文分类找到的最大静止窗口行数（未找到为 -1）
    NSInteger diagChangedOutside; // 诊断：该窗口之外的变化行数（未评估为 -1）
} MTShellXAutoMatchResult;

/// 原生行签名的正文静止判断，排除状态栏与固定工具栏的异动。
BOOL MTShellXAutoSignaturesAreStable(const uint8_t *prev, NSInteger prevRows,
                                    const uint8_t *cur, NSInteger curRows);

/// 按文字/图标结构匹配，不让白底投票；候选必须通过独立次峰与分区密集校验。
/// priorTop/priorBottom 仅用于维持已经确认的裁带接缝，不限制运动搜索。
MTShellXAutoMatchResult MTShellXAutoMatchFrames(const uint8_t *prev, NSInteger prevRows,
                                              const uint8_t *cur, NSInteger curRows,
                                              NSInteger priorTop, NSInteger priorBottom);

NS_ASSUME_NONNULL_END
