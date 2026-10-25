#import "MTNativeCaptureOrientation.h"
#import <math.h>

CGImageRef MTNativeCaptureCreateOrientedImage(CGImageRef source, unsigned turns) {
    if (!source) return NULL;
    turns %= 4;
    if (!turns) return CGImageCreateCopy(source);
    size_t width = CGImageGetWidth(source), height = CGImageGetHeight(source);
    size_t outWidth = turns % 2 ? height : width, outHeight = turns % 2 ? width : height;
    CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (!color) return NULL;
    CGContextRef context = CGBitmapContextCreate(NULL, outWidth, outHeight, 8, 0, color,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(color);
    if (!context) return NULL;
    if (turns == 1) CGContextTranslateCTM(context, 0, width);
    else if (turns == 2) CGContextTranslateCTM(context, width, height);
    else CGContextTranslateCTM(context, height, 0);
    CGContextRotateCTM(context, -(CGFloat)turns * M_PI_2);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), source);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}
