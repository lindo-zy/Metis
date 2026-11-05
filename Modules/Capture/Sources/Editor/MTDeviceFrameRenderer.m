#import "MTDeviceFrameRenderer.h"
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>

static void MTFrameFillRound(CGRect r, CGFloat radius, UIColor *color) {
    [color setFill]; [[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:radius] fill];
}
static UIImage *MTFrameLoadOverlay(NSString *path, CGFloat edge) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return nil;
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{
        (id)kCGImageSourceCreateThumbnailFromImageAlways:@YES, (id)kCGImageSourceThumbnailMaxPixelSize:@(ceil(edge)),
        (id)kCGImageSourceCreateThumbnailWithTransform:@YES, (id)kCGImageSourceShouldCacheImmediately:@YES});
    CFRelease(source);
    UIImage *result = image ? [UIImage imageWithCGImage:image] : nil;
    if (image) CGImageRelease(image);
    return result;
}

@implementation MTDeviceFrameRenderer
+ (UIColor *)backgroundColor:(NSInteger)index {
    switch (index) {
        case 0: return UIColor.clearColor;
        case 1: return [UIColor colorWithWhite:0.96 alpha:1];
        case 2: return [UIColor colorWithWhite:0.12 alpha:1];
        default: return [UIColor colorWithRed:0.89 green:0.87 blue:0.97 alpha:1];
    }
}
+ (UIImage *)renderImage:(UIImage *)source configuration:(MTDeviceFrameConfiguration *)c
                template:(MTDeviceFrameTemplate *)frame previewEdge:(CGFloat)edge {
    if (!source.CGImage || !frame || !MTDeviceFrameValidQuad(frame.screenQuad, frame.canvasSize)) return nil;
    CGSize pixels = CGSizeMake(source.size.width*source.scale,source.size.height*source.scale);
    BOOL landscape = c.autoLandscape && pixels.width > pixels.height && frame.canvasSize.height > frame.canvasSize.width;
    CGSize canvas = landscape ? CGSizeMake(frame.canvasSize.height,frame.canvasSize.width) : frame.canvasSize;
    MTDeviceFrameQuad q = landscape ? MTDeviceFrameLandscapeQuad(frame.screenQuad,frame.canvasSize) : frame.screenQuad;
    CGSize screen = MTDeviceFrameScreenSize(q);
    CGSize output = MTDeviceFrameOutputSize(pixels,canvas,screen,c.paddingFraction,edge);
    if (CGSizeEqualToSize(output,CGSizeZero)) return nil;
    CGFloat margin = MIN(canvas.width,canvas.height)*c.paddingFraction;
    CGFloat density = output.width/(canvas.width+2*margin);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
    format.scale = 1; format.opaque = c.background != 0;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;

    // 自定义素材先把完整截图铺在屏幕平面上，再通过四点透视变换映射。
    UIImage *warped = nil, *overlay = nil;
    if (frame.kind == 3) {
        overlay = MTFrameLoadOverlay(frame.overlayPath,MAX(canvas.width,canvas.height)*density);
        CGSize plateSize = CGSizeMake(ceil(screen.width*density),ceil(screen.height*density));
        if (!overlay || !MTDeviceFrameValidCanvas(plateSize)) return nil;
        UIGraphicsImageRendererFormat *plateFormat = [UIGraphicsImageRendererFormat new];
        plateFormat.scale = 1; plateFormat.opaque = YES; plateFormat.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
        UIImage *plate = [[[UIGraphicsImageRenderer alloc] initWithSize:plateSize format:plateFormat]
            imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                [UIColor.blackColor setFill]; UIRectFill((CGRect){CGPointZero,plateSize});
                [source drawInRect:MTDeviceFrameAspectFit(source.size,(CGRect){CGPointZero,plateSize})];
            }];
        CIFilter *filter = [CIFilter filterWithName:@"CIPerspectiveTransform"];
        [filter setValue:[CIImage imageWithCGImage:plate.CGImage] forKey:kCIInputImageKey];
        CGPoint points[] = {q.topLeft,q.topRight,q.bottomRight,q.bottomLeft};
        NSArray *keys = @[@"inputTopLeft",@"inputTopRight",@"inputBottomRight",@"inputBottomLeft"];
        for (NSUInteger i=0;i<4;i++) {
            [filter setValue:[CIVector vectorWithX:(points[i].x+margin)*density
                Y:output.height-(points[i].y+margin)*density] forKey:keys[i]];
        }
        static CIContext *ciContext;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ ciContext = [CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}]; });
        CIImage *result = filter.outputImage;
        CGImageRef cg = result ? [ciContext createCGImage:result fromRect:(CGRect){CGPointZero,output}] : NULL;
        warped = cg ? [UIImage imageWithCGImage:cg] : nil;
        if (cg) CGImageRelease(cg);
        if (!warped) return nil;
    }
    return [[[UIGraphicsImageRenderer alloc] initWithSize:output format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGContextRef context = ctx.CGContext;
            [[self backgroundColor:c.background] setFill]; UIRectFill((CGRect){CGPointZero,output});
            if (warped) [warped drawInRect:(CGRect){CGPointZero,output}];
            CGContextSaveGState(context);
            CGContextScaleCTM(context,density,density);
            CGContextTranslateCTM(context,margin,margin);
            if (landscape) {
                CGContextTranslateCTM(context,0,frame.canvasSize.width);
                CGContextRotateCTM(context,-M_PI_2);
            }
            CGRect body = CGRectInset((CGRect){CGPointZero,frame.canvasSize},3,3);
            if (frame.kind == 3) {
                if (c.shadow) CGContextSetShadowWithColor(context,CGSizeMake(0,7),12,[UIColor colorWithWhite:0 alpha:0.3].CGColor);
                [overlay drawInRect:(CGRect){CGPointZero,frame.canvasSize}];
            } else {
                if (c.shadow) {
                    CGContextSaveGState(context);
                    CGContextSetShadowWithColor(context,CGSizeMake(0,7),12,[UIColor colorWithWhite:0 alpha:0.35].CGColor);
                    MTFrameFillRound(body,frame.kind==2 ? 49 : 63,UIColor.blackColor);
                    CGContextRestoreGState(context);
                }
                [self drawBody:body kind:frame.kind color:c.bodyColor];
            }
            CGContextRestoreGState(context);
            if (frame.kind != 3) {
                // 内容在输出方向绘制，不随外壳旋转。
                CGRect screenRect = CGRectMake((q.topLeft.x+margin)*density,(q.topLeft.y+margin)*density,
                    screen.width*density,screen.height*density);
                CGContextSaveGState(context);
                CGFloat radius = frame.kind == 2 ? 0 : 47*density;
                [[UIBezierPath bezierPathWithRoundedRect:screenRect cornerRadius:radius] addClip];
                [UIColor.blackColor setFill]; UIRectFill(screenRect);
                [source drawInRect:MTDeviceFrameAspectFit(source.size,screenRect)];
                CGContextRestoreGState(context);
                // 摄像头与 Home 装饰在内容上方，和外壳同方向。
                CGContextSaveGState(context);
                CGContextScaleCTM(context,density,density); CGContextTranslateCTM(context,margin,margin);
                if (landscape) { CGContextTranslateCTM(context,0,frame.canvasSize.width); CGContextRotateCTM(context,-M_PI_2); }
                [self drawHardware:frame.kind canvas:frame.canvasSize];
                CGContextRestoreGState(context);
            }
        }];
}
+ (void)drawBody:(CGRect)body kind:(NSInteger)kind color:(NSInteger)index {
    NSArray *colors = @[[UIColor colorWithWhite:0.24 alpha:1],[UIColor colorWithWhite:0.83 alpha:1],
        [UIColor colorWithRed:0.65 green:0.61 blue:0.54 alpha:1],[UIColor colorWithRed:0.27 green:0.36 blue:0.47 alpha:1]];
    UIColor *metal = colors[MAX(0,MIN(3,index))];
    CGFloat radius = kind == 2 ? 49 : 63;
    MTFrameFillRound(body,radius,metal);
    UIBezierPath *rim = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(body,2,2) cornerRadius:radius-2];
    [[UIColor colorWithWhite:0.93 alpha:0.7] setStroke]; rim.lineWidth=1; [rim stroke];
    MTFrameFillRound(CGRectInset(body,5,5),radius-5,[UIColor colorWithWhite:0.015 alpha:1]);
    CGFloat x = CGRectGetMinX(body), w = body.size.width;
    MTFrameFillRound(CGRectMake(x-2,145,3,25),1,metal);
    MTFrameFillRound(CGRectMake(x-2,195,3,51),1,metal);
    MTFrameFillRound(CGRectMake(x-2,262,3,51),1,metal);
    MTFrameFillRound(CGRectMake(x+w-1,215,3,79),1,metal);
}
+ (void)drawHardware:(NSInteger)kind canvas:(CGSize)canvas {
    CGFloat center = canvas.width/2;
    if (kind == 0) {
        MTFrameFillRound(CGRectMake(center-62,27,124,35),17.5,UIColor.blackColor);
        MTFrameFillRound(CGRectMake(center+39,39,9,9),4.5,[UIColor colorWithRed:0.035 green:0.055 blue:0.12 alpha:1]);
    } else if (kind == 1) {
        MTFrameFillRound(CGRectMake(center-89,12,178,35),17,UIColor.blackColor);
        MTFrameFillRound(CGRectMake(center-25,24,50,5),2.5,[UIColor colorWithWhite:0.12 alpha:1]);
    } else {
        UIBezierPath *home = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(center-23,canvas.height-62,46,46)];
        [[UIColor colorWithWhite:0.32 alpha:1] setStroke]; home.lineWidth=2; [home stroke];
        MTFrameFillRound(CGRectMake(center-28,35,56,5),2.5,[UIColor colorWithWhite:0.15 alpha:1]);
    }
}
@end
