#import "MTExternalRequest.h"
#import "MTConstants.h"

BOOL MTIsExternalURL(NSURL *url) {
    return [url isKindOfClass:NSURL.class] &&
        [url.scheme.lowercaseString isEqualToString:MTExternalURLScheme];
}

NSString *MTNotificationNameForExternalURL(NSURL *url) {
    if (!MTIsExternalURL(url)) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!parts || parts.user != nil || parts.password != nil || parts.port != nil ||
        parts.query != nil || parts.fragment != nil) return nil;

    NSString *host = parts.host.lowercaseString ?: @"";
    NSString *path = parts.percentEncodedPath ?: @"";
    // 不解码路径，避免编码的斜杠、空格等被解释为另一条指令。
    if ((host.length == 0 || [host isEqualToString:@"activate"]) &&
        (path.length == 0 || [path isEqualToString:@"/"])) {
        return (__bridge NSString *)MTDarwinActivate;
    }
    if (![host isEqualToString:@"capture"]) return nil;

    NSDictionary<NSString *, NSString *> *routes = @{
        @"/full": (__bridge NSString *)MTDarwinCaptureFull,
        @"/area": (__bridge NSString *)MTDarwinCaptureArea,
        @"/markup": (__bridge NSString *)MTDarwinCaptureMarkup,
        @"/long": (__bridge NSString *)MTDarwinCaptureLong,
    };
    return routes[path];
}
