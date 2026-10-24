#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// SHELLX 3.1.1 长截图算法原语（逆向还原）。
// 节奏常量与阈值与原实现一致；条带采样循环按可读性重写（同为逐行
// RGB 三通道 |差| 累加、每 4 像素取样）。条带一律行 0 = 图像顶部
// （原实现经位图上下文翻转后等价），行偏移按物理滚动方向定义。

/// fastHash：20×20（scale=1）JPEG(0.1) 压缩指纹；等值比较用 isEqualToData。
/// SHELLX 用它做帧静止检测，O(1) 且对渲染噪声不敏感。
NSData * _Nullable MTShellXFastHash(UIImage *image);

/// RGBA8 对比条带：下采样 sw×sh，横向左移 sw×0.1（去边缘）。
/// 返回 malloc 缓冲（调用方 free），行距 sw*4，行 0 = 顶部；失败返回 NULL。
uint8_t * _Nullable MTShellXCreateStrip(UIImage *image, NSInteger sw, NSInteger sh);

/// 条带尺寸约定（录制式）：宽高各取原图 25%、下限 64。
void MTShellXRecordingStripSize(CGFloat pixelWidth, CGFloat pixelHeight,
                                NSInteger *outWidth, NSInteger *outHeight);

/// 行签名（拼接式判底/重拼用）：下采样 max(64,W/4)×max(64,H/4)，
/// 宽取 80%、横向偏移 10%；输出签名行数/宽/行距。失败返回 nil。
NSData * _Nullable MTShellXRowSignature(UIImage *image, NSInteger *outRows,
                                        NSInteger *outStripWidth, NSInteger *outBytesPerRow);

/// 条带 SAD：prev 行 [0, rows) 与 cur 行 [dy, dy+rows) 逐行比较，
/// 每 4 像素取 RGB 三通道 |差| 累加；comparePixels ≤ 0 表示整条带宽。
uint64_t MTShellXStripSAD(const uint8_t *prev, const uint8_t *cur, NSInteger bytesPerRow,
                          NSInteger dy, NSInteger rows, NSInteger comparePixels);

/// 滚动匹配：在 cur 中寻找 prev 顶部条带（win 行）出现的行偏移 S
/// （内容上移 S 行），粗扫步长 2、细扫步长 1。返回 S（行），无可靠
/// 重叠返回 -1；两帧几乎相同（SAD 低于静止阈值）返回 0。
/// 阈值与 SHELLX 同构：静止 (win/2)×(pixels/4)×5，接受 ×75。
NSInteger MTShellXMatchScroll(const uint8_t *prev, const uint8_t *cur, NSInteger bytesPerRow,
                              NSInteger rows, NSInteger winRows, NSInteger comparePixels);

/// 多片顺序合并为一张长图并写出 jpg：逐片绘制（高 +0.5pt 消缝）、
/// y 按片高步进；画布高度受 maxCanvasHeight 与内存像素预算收缩。
/// 成功返回图片（outSize 为像素尺寸）。
UIImage * _Nullable MTShellXComposeSlices(NSArray<NSString *> *slicePaths,
                                          NSString *outputPath,
                                          NSInteger maxCanvasHeight,
                                          double quality,
                                          CGSize *outSize,
                                          NSError **error);

NS_ASSUME_NONNULL_END
