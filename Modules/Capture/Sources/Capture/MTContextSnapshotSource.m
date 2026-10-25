#import "MTContextSnapshotSource.h"
#import <IOSurface/IOSurface.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <math.h>
#import "../Common/MTNativeCaptureOrientation.h"

// Prism 1.6.2k: request builder 0x56cc8, symbol resolver 0x66d8c.
// The context list contains descriptor dictionaries, NOT bare NSNumber context IDs.
typedef bool (*MTRenderSnapshotFunction)(unsigned int, CFDictionaryRef);
static MTRenderSnapshotFunction MTRenderSnapshot;
static NSDictionary<NSString *, id> *MTSnapshotKeys;
static void MTResolveSnapshot(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_LAZY);
        if (!handle) return;
        MTRenderSnapshot = (MTRenderSnapshotFunction)dlsym(handle, "CARenderServerSnapshot");
        NSMutableDictionary *keys = [NSMutableDictionary dictionary];
        for (NSString *name in @[@"kCASnapshotMode", @"kCASnapshotModeExcludeContextList",
             @"kCASnapshotContextList", @"kCASnapshotContextId", @"kCASnapshotDisplayName",
             @"kCASnapshotDestination", @"kCASnapshotSizeWidth", @"kCASnapshotSizeHeight"]) {
            const CFTypeRef *symbol = dlsym(handle, name.UTF8String);
            if (!symbol || !*symbol) return;
            keys[name] = (__bridge id)*symbol;
        }
        MTSnapshotKeys = [keys copy];
    });
}
static NSError *MTSnapshotError(NSString *message) {
    return [NSError errorWithDomain:@"com.lindo.metis.context-snapshot" code:1
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSNumber *MTWindowContext(UIWindow *window) {
    @try {
        // Same layer.context.contextId lookup as Prism's 0x568c0 helper.
        id context = [window.layer valueForKey:@"context"];
        id value = [context valueForKey:@"contextId"];
        if ([value isKindOfClass:NSNumber.class] && [value unsignedLongLongValue] > 0 &&
            [value unsignedLongLongValue] <= UINT32_MAX) return value;
    } @catch (__unused NSException *exception) {}
    return nil;
}
static UIImage *MTCreateContextSnapshot(NSArray<NSNumber *> *contexts, CGSize size, CGFloat scale) {
    MTResolveSnapshot();
    if (!MTRenderSnapshot || MTSnapshotKeys.count != 8 || !contexts.count ||
        !isfinite(size.width) || !isfinite(size.height) ||
        size.width < 1 || size.height < 1 || size.width > 16384 || size.height > 16384 ||
        size.width * size.height > 20000000) return nil;
    size_t width = (size_t)size.width, height = (size_t)size.height;
    size_t stride = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, width * 4);
    if (stride < width * 4 || stride > SIZE_MAX / height) return nil;
    NSDictionary *properties = @{(__bridge id)kIOSurfaceWidth:@(width),
        (__bridge id)kIOSurfaceHeight:@(height), (__bridge id)kIOSurfaceBytesPerElement:@4,
        (__bridge id)kIOSurfaceBytesPerRow:@(stride), (__bridge id)kIOSurfaceAllocSize:@(stride * height),
        (__bridge id)kIOSurfacePixelFormat:@(0x42475241)}; // BGRA
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if (!surface) return nil;
    CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    BOOL locked = NO;
    UIImage *image = nil;
    @try {
        if (color) {
            CFPropertyListRef colorProperties = CGColorSpaceCopyPropertyList(color);
            if (colorProperties) {
                IOSurfaceSetValue(surface, CFSTR("IOSurfaceColorSpace"), colorProperties);
                CFRelease(colorProperties);
                NSMutableArray *descriptors = [NSMutableArray array];
                for (NSNumber *context in contexts)
                    [descriptors addObject:@{MTSnapshotKeys[@"kCASnapshotContextId"]:context}];
                NSDictionary *request = @{
                    MTSnapshotKeys[@"kCASnapshotMode"]:MTSnapshotKeys[@"kCASnapshotModeExcludeContextList"],
                    MTSnapshotKeys[@"kCASnapshotContextList"]:descriptors,
                    MTSnapshotKeys[@"kCASnapshotDisplayName"]:@"LCD",
                    MTSnapshotKeys[@"kCASnapshotDestination"]:(__bridge id)surface,
                    MTSnapshotKeys[@"kCASnapshotSizeWidth"]:@(width),
                    MTSnapshotKeys[@"kCASnapshotSizeHeight"]:@(height)};
                if (MTRenderSnapshot(0, (__bridge CFDictionaryRef)request) &&
                    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL) == 0) {
                    locked = YES;
                    size_t actualStride = IOSurfaceGetBytesPerRow(surface);
                    const void *base = IOSurfaceGetBaseAddress(surface);
                    if (base && actualStride >= width * 4 && actualStride <= SIZE_MAX / height) {
                        // Copy before unlocking. No live IOSurface survives this call.
                        NSData *pixels = [NSData dataWithBytes:base length:actualStride * height];
                        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
                        if (provider) {
                            CGImageRef cg = CGImageCreate(width, height, 8, 32, actualStride, color,
                                kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
                                provider, NULL, false, kCGRenderingIntentDefault);
                            if (cg) { image = [UIImage imageWithCGImage:cg scale:scale orientation:UIImageOrientationUp]; CGImageRelease(cg); }
                            CGDataProviderRelease(provider);
                        }
                    }
                }
            }
        }
    } @catch (__unused NSException *exception) {
        image = nil;
    } @finally {
        if (locked) IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
        if (color) CGColorSpaceRelease(color);
        CFRelease(surface);
    }
    return image;
}

@interface MTContextSnapshotSource () {
    atomic_bool _invalidated;
}
@property (nonatomic, strong) dispatch_queue_t captureQueue;
@end
@implementation MTContextSnapshotSource
- (instancetype)init {
    if ((self = [super init])) {
        atomic_init(&_invalidated, false);
        _captureQueue = dispatch_queue_create("com.lindo.metis.quick.capture", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (void)invalidate { atomic_store(&_invalidated, true); }
- (void)captureExcludingWindows:(NSArray<UIWindow *> *)windows
                    completion:(void (^)(UIImage *, BOOL, NSString *, NSError *))completion {
    NSParameterAssert(NSThread.isMainThread);
    NSString *method = @"CARenderServerSnapshot+exclude-control-context";
    NSMutableArray<NSNumber *> *contexts = [NSMutableArray array];
    NSError *failure = nil;
    for (UIWindow *window in windows) {
        NSNumber *context = MTWindowContext(window);
        if (!context || !window.rootViewController) { failure = MTSnapshotError(@"浮窗捕获上下文尚未就绪"); break; }
        // Refuse a shared context: excluding it could also remove the page being captured.
        for (UIWindow *other in window.windowScene.windows) {
            if ([windows containsObject:other] || other.hidden) continue;
            if ([MTWindowContext(other) isEqual:context]) {
                failure = MTSnapshotError(@"浮窗与页面共享捕获上下文，无法安全排除"); break;
            }
        }
        if (failure) break;
        if (![contexts containsObject:context]) [contexts addObject:context];
    }
    UIScreen *screen = UIScreen.mainScreen;
    // Render server uses the native display orientation. Session guards interface rotation.
    CGSize size = screen.nativeBounds.size;
    CGFloat scale = screen.nativeScale;
    UIInterfaceOrientation orientation = windows.firstObject.windowScene.interfaceOrientation;
    unsigned turns = orientation == UIInterfaceOrientationLandscapeLeft ? 1 :
        (orientation == UIInterfaceOrientationLandscapeRight ? 3 :
        (orientation == UIInterfaceOrientationPortraitUpsideDown ? 2 : 0));
    if (!contexts.count && !failure) failure = MTSnapshotError(@"缺少浮窗捕获上下文");
    if (failure || atomic_load(&_invalidated)) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, NO, method, failure); });
        return;
    }
    NSArray *immutableContexts = [contexts copy];
    dispatch_async(self.captureQueue, ^{ @autoreleasepool {
        if (atomic_load(&self->_invalidated)) return;
        UIImage *image = MTCreateContextSnapshot(immutableContexts, size, scale);
        if (image && turns) {
            CGImageRef oriented = MTNativeCaptureCreateOrientedImage(image.CGImage, turns);
            image = oriented ? [UIImage imageWithCGImage:oriented scale:scale orientation:UIImageOrientationUp] : nil;
            if (oriented) CGImageRelease(oriented);
        }
        NSError *error = image ? nil : MTSnapshotError(@"当前系统无法按上下文排除浮窗抓屏");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!atomic_load(&self->_invalidated)) completion(image, NO, method, error);
        });
    }});
}
@end
