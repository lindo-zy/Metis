#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    CGPoint topLeft, topRight, bottomRight, bottomLeft;
} MTDeviceFrameQuad;

BOOL MTDeviceFrameValidCanvas(CGSize size);
BOOL MTDeviceFrameValidQuad(MTDeviceFrameQuad quad, CGSize canvas);
MTDeviceFrameQuad MTDeviceFrameQuadForRect(CGRect rect);
/// 左上坐标系逆时针转 90°，外壳和四角一起转，截图内容保持原方向。
MTDeviceFrameQuad MTDeviceFrameLandscapeQuad(MTDeviceFrameQuad quad, CGSize portraitCanvas);
CGSize MTDeviceFrameScreenSize(MTDeviceFrameQuad quad);
CGRect MTDeviceFrameAspectFit(CGSize content, CGRect bounds);
/// 按源图与屏幕等比完整显示确定密度；previewEdge>0 时允许预览降采样。
/// 正式输出超过 24MP/8192px 返回 CGSizeZero，不静默降质。
CGSize MTDeviceFrameOutputSize(CGSize sourcePixels, CGSize canvas, CGSize screen,
                             CGFloat paddingFraction, CGFloat previewEdge);

#ifdef __cplusplus
}
#endif
NS_ASSUME_NONNULL_END
