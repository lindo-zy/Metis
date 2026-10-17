#import <Foundation/Foundation.h>
#import <notify.h>
#import "MTSystemActionCatalog.h"
#import "MTDarwinOpenChannel.h"

// Callers resolve this path through MT_ROOT_PATH_NS. Preferences and URL
// scheme registration cannot prove installation of this SpringBoard tweak.
static NSString *const MTCaptureDylibPath = @"/Library/MobileSubstrate/DynamicLibraries/MetisSpringBoard.dylib";

static inline BOOL MTCaptureInstalledAtPath(NSString *path) {
    BOOL directory = NO;
    return path.length && [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] && !directory;
}

static inline MTSystemOpenResult MTPostCaptureSystemAction(NSString *action, NSString *dylibPath) {
    NSString *name = MTSystemActionDefinition(action)[@"captureNotification"];
    if (!name.length) return MTSystemOpenInvalid;
    if (!MTCaptureInstalledAtPath(dylibPath)) {
        NSLog(@"[MetisKeyboard][MetisCapture] unavailable id=%@ reason=not-installed", action);
        return MTSystemOpenUnavailable;
    }
    uint32_t status = notify_post(name.UTF8String);
    NSLog(@"[MetisKeyboard][MetisCapture] request id=%@ notify-status=%u", action, (unsigned)status);
    // MetisCapture's public channel has no completion reply. Success only confirms
    // that one request was posted; disabled/busy/injection checks remain its own.
    return status == NOTIFY_STATUS_OK ? MTSystemOpenSucceeded : MTSystemOpenFailed;
}
