#import "MTDeviceFramePhotoMaterial.h"
#import <ImageIO/ImageIO.h>
#import <math.h>

static NSError *MTPhotoMaterialError(NSString *message) {
    return [NSError errorWithDomain:@"com.lindo.metis.capture.frame.photo" code:1
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}
static CGContextRef MTPhotoMaterialContext(size_t width, size_t height) {
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context=CGBitmapContextCreate(NULL,width,height,8,0,space,kCGBitmapByteOrder32Big|kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space); return context;
}
static NSData *MTPhotoMaterialPNGData(UIImage *image) {
    if (!image.CGImage) return nil;
    NSMutableData *data=[NSMutableData new];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,CFSTR("public.png"),1,NULL);
    if (!destination) return nil;
    CGImageDestinationAddImage(destination,image.CGImage,NULL);BOOL ok=CGImageDestinationFinalize(destination);CFRelease(destination);
    return ok ? data : nil;
}
static BOOL MTPhotoMaterialHasOpening(CGImageRef image,MTDeviceFrameQuad q) {
    CGFloat originalWidth=CGImageGetWidth(image),originalHeight=CGImageGetHeight(image);
    CGFloat factor=MIN(1,256.0/MAX(originalWidth,originalHeight));
    size_t width=MAX(1,ceil(originalWidth*factor)),height=MAX(1,ceil(originalHeight*factor));
    CGContextRef context=MTPhotoMaterialContext(width,height);if(!context)return NO;
    CGContextDrawImage(context,CGRectMake(0,0,width,height),image);
    CGMutablePathRef path=CGPathCreateMutable();CGPoint p[]={q.topLeft,q.topRight,q.bottomRight,q.bottomLeft};
    CGPathMoveToPoint(path,NULL,p[0].x*width/originalWidth,p[0].y*height/originalHeight);
    for(NSUInteger i=1;i<4;i++)CGPathAddLineToPoint(path,NULL,p[i].x*width/originalWidth,p[i].y*height/originalHeight);
    CGPathCloseSubpath(path);
    size_t inside=0,transparent=0,stride=CGBitmapContextGetBytesPerRow(context);const uint8_t *pixels=CGBitmapContextGetData(context);
    for(size_t y=0;y<height;y++)for(size_t x=0;x<width;x++){
        if(!CGPathContainsPoint(path,NULL,CGPointMake(x+0.5,y+0.5),false))continue;
        inside++;if(pixels[y*stride+x*4+3]<=24)transparent++;
    }
    CGPathRelease(path);CGContextRelease(context);
    return inside>0 && transparent>=MAX(1,inside/10);
}

@implementation MTDeviceFramePhotoMaterial
+ (UIImage *)imageForTemplate:(MTDeviceFrameTemplate *)frame error:(NSError **)error {
    unsigned long long bytes=frame.overlayPath.length ? [[NSFileManager.defaultManager attributesOfItemAtPath:frame.overlayPath error:nil]fileSize] : 0;
    if(frame.kind!=3 || !bytes || bytes>40*1024*1024 || !MTDeviceFrameValidCanvas(frame.canvasSize)) {
        if(error)*error=MTPhotoMaterialError(@"素材图片不可用，请重新导入");return nil;
    }
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:frame.overlayPath],NULL);
    NSDictionary *info=source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)) : nil;
    CGSize size=CGSizeMake([info[(id)kCGImagePropertyPixelWidth]doubleValue],[info[(id)kCGImagePropertyPixelHeight]doubleValue]);
    CFStringRef type=source ? CGImageSourceGetType(source) : NULL;
    BOOL valid=source && CGImageSourceGetCount(source)==1 && CGSizeEqualToSize(size,frame.canvasSize) &&
        type && CFEqual(type,CFSTR("public.png"));
    CGImageRef cg=valid ? CGImageSourceCreateImageAtIndex(source,0,(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCacheImmediately:@YES}) : NULL;
    if(source)CFRelease(source);
    UIImage *image=cg ? [UIImage imageWithCGImage:cg] : nil;if(cg)CGImageRelease(cg);
    if(!image && error)*error=MTPhotoMaterialError(@"素材图片与配置不一致，请重新导入");
    return image;
}
+ (UIImage *)imageFromPhotoURL:(NSURL *)URL error:(NSError **)error {
    if(!URL.isFileURL){if(error)*error=MTPhotoMaterialError(@"相册图片不可用，请重新选择");return nil;}
    unsigned long long bytes=[[NSFileManager.defaultManager attributesOfItemAtPath:URL.path error:nil] fileSize];
    if (!bytes || bytes>40*1024*1024) {
        if(error)*error=MTPhotoMaterialError(@"相册图片最大 40MB，请缩小后导入");return nil;
    }
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)URL,NULL);
    NSDictionary *info=source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)) : nil;
    CGSize size=CGSizeMake([info[(id)kCGImagePropertyPixelWidth] doubleValue],[info[(id)kCGImagePropertyPixelHeight] doubleValue]);
    if (!source || CGImageSourceGetCount(source)!=1 || !MTDeviceFrameValidCanvas(size)) {
        if(source)CFRelease(source);
        if(error)*error=MTPhotoMaterialError(@"请选择单张静态图片，最大 24MP / 8192px");return nil;
    }
    CGImageRef cg=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{
        (id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (id)kCGImageSourceCreateThumbnailWithTransform:@YES,
        (id)kCGImageSourceThumbnailMaxPixelSize:@(MAX(size.width,size.height)),
        (id)kCGImageSourceShouldCacheImmediately:@YES});
    CFRelease(source);
    UIImage *image=cg ? [UIImage imageWithCGImage:cg] : nil;
    if(cg)CGImageRelease(cg);
    if(!image && error)*error=MTPhotoMaterialError(@"相册图片解码失败，请重新选择");
    return image;
}
+ (MTDeviceFrameQuad)suggestedScreenForImage:(UIImage *)image hasTransparentScreen:(BOOL *)transparent {
    if(transparent)*transparent=NO;
    if(!image.CGImage)return MTDeviceFrameQuadForRect(CGRectZero);
    CGSize size=CGSizeMake(CGImageGetWidth(image.CGImage),CGImageGetHeight(image.CGImage));
    MTDeviceFrameQuad fallback=MTDeviceFrameQuadForRect(CGRectMake(size.width*0.08,size.height*0.06,size.width*0.84,size.height*0.88));
    if(!MTDeviceFrameValidCanvas(size))return fallback;
    CGFloat factor=MIN(1,256.0/MAX(size.width,size.height));
    size_t width=MAX(1,ceil(size.width*factor)),height=MAX(1,ceil(size.height*factor)),count=width*height;
    CGContextRef context=MTPhotoMaterialContext(width,height);
    if(!context)return fallback;
    CGContextDrawImage(context,CGRectMake(0,0,width,height),image.CGImage);
    const uint8_t *pixels=CGBitmapContextGetData(context);
    size_t stride=CGBitmapContextGetBytesPerRow(context);
    uint8_t *seen=calloc(count,1);uint32_t *queue=malloc(count*sizeof(uint32_t));
    if(!seen || !queue){free(seen);free(queue);CGContextRelease(context);return fallback;}
    size_t bestCount=0,bestX=0,bestY=0,bestRight=0,bestBottom=0;
    for(size_t seed=0;seed<count;seed++) {
        size_t sx=seed%width,sy=seed/width;
        if(seen[seed] || pixels[sy*stride+sx*4+3]>24)continue;
        size_t head=0,tail=1,minX=sx,maxX=sx,minY=sy,maxY=sy;BOOL touchesEdge=NO;
        queue[0]=(uint32_t)seed;seen[seed]=1;
        while(head<tail) {
            size_t p=queue[head++],x=p%width,y=p/width;
            minX=MIN(minX,x);maxX=MAX(maxX,x);minY=MIN(minY,y);maxY=MAX(maxY,y);
            if(x==0 || y==0 || x+1==width || y+1==height)touchesEdge=YES;
            size_t neighbors[]={x>0?p-1:p,x+1<width?p+1:p,y>0?p-width:p,y+1<height?p+width:p};
            for(NSUInteger i=0;i<4;i++) {
                size_t n=neighbors[i],nx=n%width,ny=n/width;
                if(!seen[n] && pixels[ny*stride+nx*4+3]<=24){seen[n]=1;queue[tail++]=(uint32_t)n;}
            }
        }
        if(!touchesEdge && tail>bestCount && maxX-minX>=width*0.12 && maxY-minY>=height*0.12) {
            bestCount=tail;bestX=minX;bestY=minY;bestRight=maxX+1;bestBottom=maxY+1;
        }
    }
    free(seen);free(queue);CGContextRelease(context);
    if(bestCount<count*0.02)return fallback;
    // 低分辨率检测边缘向外覆盖一个采样像素，避免开孔边缘露出底色；原 PNG 遮罩裁出真实轮廓。
    bestX=bestX>0 ? bestX-1 : 0;bestY=bestY>0 ? bestY-1 : 0;
    bestRight=MIN(width,bestRight+1);bestBottom=MIN(height,bestBottom+1);
    CGRect rect=CGRectMake(bestX*size.width/width,bestY*size.height/height,
        (bestRight-bestX)*size.width/width,(bestBottom-bestY)*size.height/height);
    MTDeviceFrameQuad result=MTDeviceFrameQuadForRect(rect);
    if(!MTDeviceFrameValidQuad(result,size))return fallback;
    if(transparent)*transparent=YES;return result;
}
+ (UIImage *)previewForImage:(UIImage *)image {
    if(!image.CGImage)return nil;
    CGSize size=CGSizeMake(CGImageGetWidth(image.CGImage),CGImageGetHeight(image.CGImage));
    CGFloat factor=MIN(1,1200.0/MAX(size.width,size.height));
    CGContextRef context=MTPhotoMaterialContext(MAX(1,floor(size.width*factor)),MAX(1,floor(size.height*factor)));
    if(!context)return nil;
    CGContextDrawImage(context,CGRectMake(0,0,CGBitmapContextGetWidth(context),CGBitmapContextGetHeight(context)),image.CGImage);
    CGImageRef cg=CGBitmapContextCreateImage(context);CGContextRelease(context);
    UIImage *result=cg ? [UIImage imageWithCGImage:cg] : nil;
    if(cg)CGImageRelease(cg);return result;
}
// 兼容旧素材调用方，保持原遮罩语义。
+ (MTDeviceFrameTemplate *)importImage:(UIImage *)image name:(NSString *)name
                           screenQuad:(MTDeviceFrameQuad)q cutout:(BOOL)cutout error:(NSError **)error {
    return [self storeImage:image name:name screenQuad:q cutout:cutout cornerRadius:0 preserveSource:NO error:error];
}
+ (UIImage *)sourceImageForTemplate:(MTDeviceFrameTemplate *)frame error:(NSError **)error {
    NSString *path=[frame.overlayPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"source.png"];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) return [self imageForTemplate:frame error:error];
    MTDeviceFrameTemplate *source=[MTDeviceFrameTemplate customTemplateWithDictionary:frame.dictionaryRepresentation
        identifier:frame.identifier overlayPath:path];
    return [self imageForTemplate:source error:error];
}
+ (UIImage *)overlayForImage:(UIImage *)image screenQuad:(MTDeviceFrameQuad)q
                     cutout:(BOOL)cutout cornerRadius:(CGFloat)radius error:(NSError **)error {
    CGSize size=image.CGImage ? CGSizeMake(CGImageGetWidth(image.CGImage),CGImageGetHeight(image.CGImage)) : CGSizeZero;
    if (!MTDeviceFrameValidQuad(q,size) || !isfinite(radius) || radius<0 || radius>100) {
        if(error)*error=MTPhotoMaterialError(@"屏幕四角无效，请按左上、右上、右下、左下顺序调整");return nil;
    }
    BOOL hasOpening=MTPhotoMaterialHasOpening(image.CGImage,q);
    if (!cutout && !hasOpening) {
        if(error)*error=MTPhotoMaterialError(@"所选屏幕区域没有透明开孔，请重新定位四角");return nil;
    }
    CGContextRef context=MTPhotoMaterialContext((size_t)size.width,(size_t)size.height);
    if(!context){if(error)*error=MTPhotoMaterialError(@"无法处理素材，请缩小图片后重试");return nil;}
    CGContextDrawImage(context,(CGRect){CGPointZero,size},image.CGImage);
    if (cutout && !hasOpening) {
        // 在原画布内清除圆角四边形；沿相邻边取切点，适用于倾斜和透视素材。
        CGPoint p[]={q.topLeft,q.topRight,q.bottomRight,q.bottomLeft},before[4],after[4];
        CGSize screen=MTDeviceFrameScreenSize(q);
        CGFloat r=radius*MIN(screen.width,screen.height)/393.0;
        for (NSUInteger i=0;i<4;i++) {
            CGPoint prev=p[(i+3)%4],next=p[(i+1)%4];
            CGFloat a=hypot(prev.x-p[i].x,prev.y-p[i].y),b=hypot(next.x-p[i].x,next.y-p[i].y);
            CGFloat distance=MIN(r,MIN(a,b)*0.45);
            before[i]=CGPointMake(p[i].x+(prev.x-p[i].x)*distance/a,p[i].y+(prev.y-p[i].y)*distance/a);
            after[i]=CGPointMake(p[i].x+(next.x-p[i].x)*distance/b,p[i].y+(next.y-p[i].y)*distance/b);
        }
        CGContextTranslateCTM(context,0,size.height);CGContextScaleCTM(context,1,-1);
        CGContextSetBlendMode(context,kCGBlendModeClear);
        CGContextMoveToPoint(context,after[0].x,after[0].y);
        for (NSUInteger step=1;step<=4;step++) {
            NSUInteger i=step%4;
            CGContextAddLineToPoint(context,before[i].x,before[i].y);
            CGContextAddQuadCurveToPoint(context,p[i].x,p[i].y,after[i].x,after[i].y);
        }
        CGContextClosePath(context);CGContextFillPath(context);
    }
    CGImageRef cg=CGBitmapContextCreateImage(context);CGContextRelease(context);
    UIImage *result=cg ? [UIImage imageWithCGImage:cg] : nil;if(cg)CGImageRelease(cg);
    return result;
}
+ (MTDeviceFrameTemplate *)importImage:(UIImage *)image name:(NSString *)name
                           screenQuad:(MTDeviceFrameQuad)q cornerRadius:(CGFloat)radius error:(NSError **)error {
    return [self storeImage:image name:name screenQuad:q cutout:YES cornerRadius:radius preserveSource:YES error:error];
}
+ (MTDeviceFrameTemplate *)storeImage:(UIImage *)image name:(NSString *)name screenQuad:(MTDeviceFrameQuad)q
                              cutout:(BOOL)cutout cornerRadius:(CGFloat)radius preserveSource:(BOOL)preserve error:(NSError **)error {
    UIImage *overlay=[self overlayForImage:image screenQuad:q cutout:cutout cornerRadius:radius error:error];
    if(!overlay)return nil;
    NSData *data=MTPhotoMaterialPNGData(overlay);
    if(!data){if(error)*error=MTPhotoMaterialError(@"PNG 素材生成失败");return nil;}
    CGSize size=CGSizeMake(CGImageGetWidth(image.CGImage),CGImageGetHeight(image.CGImage));
    NSDictionary *config=@{@"name":name ?: @"相册素材",@"screen_corner_radius":@(radius),
        @"template_width":@(size.width),@"template_height":@(size.height),
        @"left_top_x":@(q.topLeft.x),@"left_top_y":@(q.topLeft.y),@"right_top_x":@(q.topRight.x),@"right_top_y":@(q.topRight.y),
        @"right_bottom_x":@(q.bottomRight.x),@"right_bottom_y":@(q.bottomRight.y),
        @"left_bottom_x":@(q.bottomLeft.x),@"left_bottom_y":@(q.bottomLeft.y)};
    NSData *original=preserve ? MTPhotoMaterialPNGData(image) : nil;
    if (preserve && !original) {if(error)*error=MTPhotoMaterialError(@"原图保存失败，请重试");return nil;}
    return [MTDeviceFrameTemplateStore importPNGData:data configuration:config sourcePNGData:original error:error];
}
@end
