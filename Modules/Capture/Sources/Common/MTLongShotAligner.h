#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT const NSInteger MTLongShotSigWidth;
void MTLongShotComputeRowSignature(const uint8_t *buffer, NSInteger pixelWidth,
                                  NSInteger bytesPerRow, NSInteger row, uint8_t *outSig);
BOOL MTLongShotSignaturesAreDuplicate(const uint8_t *prev, NSInteger prevRows,
                                     const uint8_t *cur, NSInteger curRows);

typedef NS_ENUM(NSInteger, MTLongShotMatchKind) {
    MTLongShotMatchUncertain, MTLongShotMatchDuplicate, MTLongShotMatchForward, MTLongShotMatchReverse
};
typedef struct {
    MTLongShotMatchKind kind;
    NSInteger shiftRows;
    NSInteger fixedTopRows;
    NSInteger fixedBottomRows;
} MTLongShotFrameMatch;

/// 纯像素对齐：fixedTop/Bottom < 0 时从首个移动帧识别固定条带。
/// 不可信/无纹理/周期多解返回 Uncertain，禁止据此追加整屏。
MTLongShotFrameMatch MTLongShotMatchFrames(const uint8_t *prev, const uint8_t *cur,
                                          NSInteger rows, NSInteger fixedTop, NSInteger fixedBottom);
NS_ASSUME_NONNULL_END
