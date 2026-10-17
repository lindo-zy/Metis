#import <Foundation/Foundation.h>
#import <notify.h>
#import "DXSystemActionCatalog.h"
#import "DXDarwinOpenChannel.h"

// Callers resolve this path through DX_ROOT_PATH_NS. Preferences and URL
// scheme registration cannot prove installation of this SpringBoard tweak.
static NSString *const DXCaptureDylibPath = @"/Library/MobileSubstrate/DynamicLibraries/MetisSpringBoard.dylib";

static inline BOOL DXCaptureInstalledAtPath(NSString *path) {
    BOOL directory = NO;
    return path.length && [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] && !directory;
}

static inline DXSystemOpenResult DXPostCaptureSystemAction(NSString *action, NSString *dylibPath) {
    NSString *name = DXSystemActionDefinition(action)[@"pixpinNotification"];
    if (!name.length) return DXSystemOpenInvalid;
    if (!DXCaptureInstalledAtPath(dylibPath)) {
        NSLog(@"[MetisKeyboard][MetisCapture] unavailable id=%@ reason=not-installed", action);
        return DXSystemOpenUnavailable;
    }
    uint32_t status = notify_post(name.UTF8String);
    NSLog(@"[MetisKeyboard][MetisCapture] request id=%@ notify-status=%u", action, (unsigned)status);
    // MetisCapture's public channel has no completion reply. Success only confirms
    // that one request was posted; disabled/busy/injection checks remain its own.
    return status == NOTIFY_STATUS_OK ? DXSystemOpenSucceeded : DXSystemOpenFailed;
}
