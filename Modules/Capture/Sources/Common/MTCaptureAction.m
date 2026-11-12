#import "MTCaptureAction.h"
#import "MTConstants.h"

@implementation MTCaptureAction

- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title
                     notification:(CFStringRef)notification URLRoute:(CFStringRef)route {
    if ((self = [super init])) {
        _identifier = [identifier copy];
        _title = [title copy];
        _notificationName = [(__bridge NSString *)notification copy];
        _URLRoute = [(__bridge NSString *)route copy];
    }
    return self;
}

@end

NSArray<MTCaptureAction *> *MTCaptureActions(void) {
    static NSArray<MTCaptureAction *> *actions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        actions = @[
            [[MTCaptureAction alloc] initWithIdentifier:@"capture.test.frame" title:@"套壳截图"
                notification:MTDarwinCaptureFrame URLRoute:MTURLRouteFrame],
            [[MTCaptureAction alloc] initWithIdentifier:@"capture.test.full" title:@"全屏截图"
                notification:MTDarwinCaptureFull URLRoute:MTURLRouteFull],
            [[MTCaptureAction alloc] initWithIdentifier:@"capture.test.area" title:@"区域截图"
                notification:MTDarwinCaptureArea URLRoute:MTURLRouteArea],
            [[MTCaptureAction alloc] initWithIdentifier:@"capture.test.markup" title:@"全屏标记"
                notification:MTDarwinCaptureMarkup URLRoute:MTURLRouteMarkup],
            [[MTCaptureAction alloc] initWithIdentifier:@"capture.test.long" title:@"滚动截图"
                notification:MTDarwinCaptureLong URLRoute:MTURLRouteLong],
            [[MTCaptureAction alloc] initWithIdentifier:@"capture.test.ocr" title:@"识别文字"
                notification:MTDarwinCaptureOCR URLRoute:MTURLRouteOCR],
            [[MTCaptureAction alloc] initWithIdentifier:@"capture.test.scan" title:@"全图扫码"
                notification:MTDarwinCaptureScan URLRoute:MTURLRouteScan],
            [[MTCaptureAction alloc] initWithIdentifier:@"capture.test.imageai" title:@"图片问答"
                notification:MTDarwinCaptureImageAI URLRoute:MTURLRouteImageAI],
            [[MTCaptureAction alloc] initWithIdentifier:@"capture.test.edit" title:@"图片编辑"
                notification:MTDarwinEditClipboard URLRoute:MTURLRouteEditClipboard],
        ];
    });
    return actions;
}

MTCaptureAction *MTCaptureActionForIdentifier(NSString *identifier) {
    for (MTCaptureAction *action in MTCaptureActions()) {
        if ([action.identifier isEqualToString:identifier]) return action;
    }
    return nil;
}

NSString *MTCaptureRouteRoot(NSURL *URL) {
    if (![URL isKindOfClass:NSURL.class] || ![URL.scheme.lowercaseString isEqualToString:@"prefs"]) return nil;
    if (URL.query.length || URL.fragment.length || (URL.host.length && URL.path.length)) return nil;
    NSString *spec = URL.host.length ? URL.host : URL.resourceSpecifier;
    if ([spec hasPrefix:@"//"]) spec = [spec substringFromIndex:2];
    for (NSString *part in [spec componentsSeparatedByString:@"&"]) {
        if ([part hasPrefix:@"root="]) {
            return [[part substringFromIndex:5] stringByRemovingPercentEncoding].lowercaseString;
        }
    }
    return nil;
}

MTCaptureAction *MTCaptureActionForURL(NSURL *URL) {
    NSString *root = MTCaptureRouteRoot(URL);
    if (!root.length) return nil;
    for (MTCaptureAction *action in MTCaptureActions()) {
        if (action.URLRoute && [MTCaptureRouteRoot([NSURL URLWithString:action.URLRoute]) isEqualToString:root]) {
            return action;
        }
    }
    return nil;
}
