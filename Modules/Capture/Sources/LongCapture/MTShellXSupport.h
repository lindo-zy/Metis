#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Common/MTLongShotControl.h"

NS_ASSUME_NONNULL_BEGIN

// 保留 SHELLX 的录制/逐屏采集模型和 JPEG 切片；对齐采用项目已验证的
// 多正文窗口校验，合并采用受预算约束的逐片解码。所有图像原语在后台调用。
// 行序与 MTLongImageComposer 一致，正位移表示页面内容上移。

UIImage * _Nullable MTShellXThumbnail(UIImage *image, NSInteger maxDimension);
BOOL MTShellXWriteSlice(UIImage *image, NSInteger top, NSInteger height, NSString *path);

/// fastHash：最长边 20px（scale=1）JPEG(0.1) 压缩指纹；等值比较用 isEqualToData。
/// SHELLX 用它做帧静止检测，O(1) 且对渲染噪声不敏感。
NSData * _Nullable MTShellXFastHash(UIImage *image);

/// 原生行精度、每行 64 字节的亮度签名，与已验证的 Metis 像素对齐契约一致。
/// 只保存最近成功帧的签名；返回行数/每行采样数/行距，失败返回 nil。
NSData * _Nullable MTShellXRowSignature(UIImage *image, NSInteger * _Nullable outRows,
                                        NSInteger * _Nullable outStripWidth, NSInteger * _Nullable outBytesPerRow);

/// 滚动匹配：在 prev 下部寻找 cur 正文出现的行偏移 S
/// （内容上移 S 行），多个正文窗口验证方向和唯一性。返回 S（行），无可靠
/// 重叠返回 -1；两帧正文几乎相同返回 0。
/// 静止判定独立于移动匹配，拒绝倒退和无可靠重叠的画面。
NSInteger MTShellXMatchScroll(const uint8_t *prev, const uint8_t *cur, NSInteger bytesPerRow,
                              NSInteger rows, NSInteger winRows, NSInteger comparePixels);

/// 多片顺序合并为一张长图并写出 jpg：逐片绘制（高 +0.5pt 消缝）、
/// y 按片高步进；使用像素坐标，画布受 maxCanvasHeight 与 8MP/进程预算约束。
/// 每片绘制后立即释放解码位图，分配失败减半预算重试，取消时停止处理。
/// 成功返回图片（outSize 为像素尺寸）。
UIImage * _Nullable MTShellXComposeSlices(NSArray<NSString *> *slicePaths,
                                          NSString *outputPath,
                                          NSInteger maxCanvasHeight,
                                          double quality,
                                          MTLongShotCancellation *cancellation,
                                          CGSize *outSize,
                                          NSError **error);

NS_ASSUME_NONNULL_END
