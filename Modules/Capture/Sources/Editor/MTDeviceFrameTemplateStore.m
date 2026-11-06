#import "MTDeviceFrameTemplateStore.h"
#import "../../../../Core/MTPathResolver.h"
#import <ImageIO/ImageIO.h>

static NSString *MTFrameStoreRoot(void) {
    return [MTPrivateDataRoot() stringByAppendingPathComponent:@"Capture/DeviceFrames"];
}
static NSError *MTFrameImportError(NSString *message) {
    return [NSError errorWithDomain:@"com.lindo.metis.capture.frame" code:1
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}
static MTDeviceFrameTemplate *MTFrameLoadTemplate(NSString *directory, NSString *identifier) {
    NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"config.json"]];
    NSString *path = [directory stringByAppendingPathComponent:@"overlay.png"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [MTDeviceFrameTemplate customTemplateWithDictionary:[MTDeviceFrameTemplate parseConfigurationData:data]
                                                   identifier:identifier overlayPath:path];
}

@implementation MTDeviceFrameTemplateStore
+ (NSArray<MTDeviceFrameTemplate *> *)templates {
    NSMutableArray *result = [[MTDeviceFrameTemplate builtInTemplates] mutableCopy];
    NSArray *entries = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:MTFrameStoreRoot() error:nil]
                        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *entry in entries) {
        if (result.count >= 35) break;
        if (![[NSUUID alloc] initWithUUIDString:entry]) continue;
        MTDeviceFrameTemplate *t = MTFrameLoadTemplate([MTFrameStoreRoot() stringByAppendingPathComponent:entry], entry);
        if (t) [result addObject:t];
    }
    return result;
}
+ (MTDeviceFrameTemplate *)templateForIdentifier:(NSString *)identifier {
    for (MTDeviceFrameTemplate *t in self.templates) if ([t.identifier isEqualToString:identifier]) return t;
    return nil;
}
+ (MTDeviceFrameTemplate *)resolveTemplateForConfiguration:(MTDeviceFrameConfiguration *)configuration
                                               templates:(NSArray<MTDeviceFrameTemplate *> *)templates {
    if (configuration.randomize && templates.count) return templates[arc4random_uniform((uint32_t)templates.count)];
    for (MTDeviceFrameTemplate *frame in templates)
        if ([frame.identifier isEqualToString:configuration.templateIdentifier]) return frame;
    return nil;
}
+ (MTDeviceFrameTemplate *)importFiles:(NSArray<NSURL *> *)URLs error:(NSError **)error {
    NSString *failure = @"请选择一个 PNG 和一个 JSON、plist 或 cfg 配置文件";
    NSURL *pngURL = nil, *configURL = nil;
    if (URLs.count != 2) { if (error) *error = MTFrameImportError(failure); return nil; }
    for (NSURL *url in URLs) {
        if (!url.isFileURL) { if (error) *error = MTFrameImportError(failure); return nil; }
        NSString *ext = url.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"png"] && !pngURL) pngURL = url;
        else if ([@[@"json",@"plist",@"cfg"] containsObject:ext] && !configURL) configURL = url;
        else { if (error) *error = MTFrameImportError(failure); return nil; }
    }
    if (!pngURL || !configURL) { if (error) *error = MTFrameImportError(failure); return nil; }
    NSFileManager *fm = NSFileManager.defaultManager;
    unsigned long long pngBytes = [[fm attributesOfItemAtPath:pngURL.path error:nil] fileSize];
    unsigned long long configBytes = [[fm attributesOfItemAtPath:configURL.path error:nil] fileSize];
    if (!pngBytes || pngBytes > 20*1024*1024 || !configBytes || configBytes > 65536) {
        if (error) *error = MTFrameImportError(@"PNG 最大 20MB，配置文件最大 64KB"); return nil;
    }
    NSDictionary *dictionary = [MTDeviceFrameTemplate parseConfigurationData:[NSData dataWithContentsOfURL:configURL]];
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSString *directory = [MTFrameStoreRoot() stringByAppendingPathComponent:identifier];
    MTDeviceFrameTemplate *t = [MTDeviceFrameTemplate customTemplateWithDictionary:dictionary identifier:identifier
        overlayPath:[directory stringByAppendingPathComponent:@"overlay.png"]];
    if (!t) { if (error) *error = MTFrameImportError(@"配置无效：请检查画布尺寸和屏幕四角坐标（左上为原点）"); return nil; }
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)pngURL, NULL);
    NSDictionary *info = source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)) : nil;
    CFStringRef imageType = source ? CGImageSourceGetType(source) : NULL;
    BOOL isPNG = imageType && CFEqual(imageType, CFSTR("public.png"));
    BOOL validImage = isPNG && CGImageSourceGetCount(source) == 1 &&
        [info[(id)kCGImagePropertyPixelWidth] doubleValue] == t.canvasSize.width &&
        [info[(id)kCGImagePropertyPixelHeight] doubleValue] == t.canvasSize.height &&
        [info[(id)kCGImagePropertyHasAlpha] boolValue];
    if (source) CFRelease(source);
    if (!validImage) {
        if (error) *error = MTFrameImportError(@"需要含透明通道的单帧 PNG，像素宽高必须与配置画布一致"); return nil;
    }
    if (self.templates.count >= 35) { if (error) *error = MTFrameImportError(@"自定义素材最多 32 个，请先删除不需要的素材"); return nil; }
    NSString *staging = [MTFrameStoreRoot() stringByAppendingPathComponent:[@".import-" stringByAppendingString:identifier]];
    BOOL ok = [fm createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:error];
    if (ok) ok = [fm copyItemAtURL:pngURL toURL:[NSURL fileURLWithPath:[staging stringByAppendingPathComponent:@"overlay.png"]] error:error];
    if (ok) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:t.dictionaryRepresentation options:NSJSONWritingPrettyPrinted error:error];
        ok = data && [data writeToFile:[staging stringByAppendingPathComponent:@"config.json"] options:NSDataWritingAtomic error:error];
    }
    if (ok) ok = [fm moveItemAtPath:staging toPath:directory error:error];
    if (!ok) { [fm removeItemAtPath:staging error:nil]; return nil; }
    return t;
}
+ (BOOL)removeTemplate:(MTDeviceFrameTemplate *)t error:(NSError **)error {
    if (t.kind != 3 || ![[NSUUID alloc] initWithUUIDString:t.identifier]) return NO;
    return [NSFileManager.defaultManager removeItemAtPath:[MTFrameStoreRoot() stringByAppendingPathComponent:t.identifier] error:error];
}
@end
