#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Common/MTLongShotControl.h"

NS_ASSUME_NONNULL_BEGIN

// 逐屏保存 JPEG 切片，使用原生行签名确认滚动位移；合并受内存预算约束，
// 每次只解码一个切片。所有图像原语在后台调用。
// 行序与 MTLongImageComposer 一致，正位移表示页面内容上移。

UIImage * _Nullable MTShellXThumbnail(UIImage *image, NSInteger maxDimension);
BOOL MTShellXWriteSlice(UIImage *image, NSInteger top, NSInteger height, NSString *path);

/// 原生行精度、每行 64 字节的亮度签名，与已验证的 Metis 像素对齐契约一致。
/// 只保存最近成功帧的签名；返回行数/每行采样数/行距，失败返回 nil。
NSData * _Nullable MTShellXRowSignature(UIImage *image, NSInteger * _Nullable outRows,
                                        NSInteger * _Nullable outStripWidth, NSInteger * _Nullable outBytesPerRow);



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
