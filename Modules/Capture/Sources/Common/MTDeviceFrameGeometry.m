#import "MTDeviceFrameGeometry.h"
#import <math.h>

static BOOL MTFramePositiveSize(CGSize s) {
    return isfinite(s.width) && isfinite(s.height) && s.width > 0 && s.height > 0;
}

BOOL MTDeviceFrameValidCanvas(CGSize s) {
    return MTFramePositiveSize(s) && s.width >= 16 && s.height >= 16 &&
        s.width <= 8192 && s.height <= 8192 && s.width * s.height <= 24000000;
}

MTDeviceFrameQuad MTDeviceFrameQuadForRect(CGRect r) {
    return (MTDeviceFrameQuad){r.origin, CGPointMake(CGRectGetMaxX(r), CGRectGetMinY(r)),
        CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r)), CGPointMake(CGRectGetMinX(r), CGRectGetMaxY(r))};
}

BOOL MTDeviceFrameValidQuad(MTDeviceFrameQuad q, CGSize canvas) {
    if (!MTDeviceFrameValidCanvas(canvas)) return NO;
    CGPoint p[] = {q.topLeft, q.topRight, q.bottomRight, q.bottomLeft};
    double area = 0;
    for (NSUInteger i = 0; i < 4; i++) {
        CGPoint a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4];
        if (!isfinite(a.x) || !isfinite(a.y) || a.x < 0 || a.y < 0 ||
            a.x > canvas.width || a.y > canvas.height) return NO;
        double cross = (b.x-a.x)*(c.y-b.y) - (b.y-a.y)*(c.x-b.x);
        // 正向凸多边形；同时排除反向、三点共线、蝴蝶结和极细透视。
        if (!isfinite(cross) || cross <= 1.0) return NO;
        area += a.x*b.y-b.x*a.y;
    }
    CGSize s = MTDeviceFrameScreenSize(q);
    return area >= 32 && s.width >= 4 && s.height >= 4;
}

static CGPoint MTFrameRotatePoint(CGPoint p, CGSize size) { return CGPointMake(p.y, size.width-p.x); }
MTDeviceFrameQuad MTDeviceFrameLandscapeQuad(MTDeviceFrameQuad q, CGSize size) {
    return (MTDeviceFrameQuad){MTFrameRotatePoint(q.topRight, size), MTFrameRotatePoint(q.bottomRight, size),
        MTFrameRotatePoint(q.bottomLeft, size), MTFrameRotatePoint(q.topLeft, size)};
}

CGSize MTDeviceFrameScreenSize(MTDeviceFrameQuad q) {
    return CGSizeMake((hypot(q.topRight.x-q.topLeft.x, q.topRight.y-q.topLeft.y) +
                       hypot(q.bottomRight.x-q.bottomLeft.x, q.bottomRight.y-q.bottomLeft.y))/2,
                      (hypot(q.bottomLeft.x-q.topLeft.x, q.bottomLeft.y-q.topLeft.y) +
                       hypot(q.bottomRight.x-q.topRight.x, q.bottomRight.y-q.topRight.y))/2);
}

CGRect MTDeviceFrameAspectFit(CGSize content, CGRect b) {
    if (!MTFramePositiveSize(content) || !MTFramePositiveSize(b.size) ||
        !isfinite(b.origin.x) || !isfinite(b.origin.y)) return CGRectZero;
    CGFloat s = MIN(b.size.width/content.width, b.size.height/content.height);
    CGSize result = CGSizeMake(content.width*s, content.height*s);
    return CGRectMake(CGRectGetMidX(b)-result.width/2, CGRectGetMidY(b)-result.height/2,
                      result.width, result.height);
}

CGSize MTDeviceFrameOutputSize(CGSize source, CGSize canvas, CGSize screen, CGFloat padding, CGFloat edge) {
    if (!MTFramePositiveSize(source) || !MTDeviceFrameValidCanvas(canvas) || !MTFramePositiveSize(screen) ||
        !isfinite(padding) || padding < 0 || padding > 0.25 || !isfinite(edge) || edge < 0) return CGSizeZero;
    CGFloat density = MAX(source.width/screen.width, source.height/screen.height);
    CGFloat margin = MIN(canvas.width, canvas.height)*padding;
    CGSize output = CGSizeMake((canvas.width+2*margin)*density, (canvas.height+2*margin)*density);
    if (!MTFramePositiveSize(output)) return CGSizeZero;
    if (edge > 0) {
        CGFloat scale = MIN(1, edge/MAX(output.width,output.height));
        output.width *= scale; output.height *= scale;
    }
    output.width = ceil(output.width); output.height = ceil(output.height);
    if (edge > 0) {
        output.width = MIN(floor(edge),output.width);
        output.height = MIN(floor(edge),output.height);
        if (!MTFramePositiveSize(output)) return CGSizeZero;
    }
    if (output.width > 8192 || output.height > 8192 || output.width*output.height > 24000000) return CGSizeZero;
    return output;
}

CGSize MTDeviceFrameCanvasOutputSize(CGSize canvas, CGFloat edge) {
    if (!MTDeviceFrameValidCanvas(canvas) || !isfinite(edge) || edge < 0) return CGSizeZero;
    CGFloat scale = edge > 0 ? MIN(1,edge/MAX(canvas.width,canvas.height)) : 1;
    CGSize output = CGSizeMake(floor(canvas.width*scale),floor(canvas.height*scale));
    return MTFramePositiveSize(output) ? output : CGSizeZero;
}
