#import "MTPathResolver.h"

#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#import <roothide.h>
#define MT_JBROOT(path) jbroot(path)
#else
#define MT_JBROOT(path) (path)
#endif

NSString *MTResolvePath(NSString *logicalPath) {
    if (!logicalPath.length) return logicalPath;
    return MT_JBROOT(logicalPath);
}

NSString *MTPrivateDataRoot(void) {
    return MTResolvePath(@"/var/mobile/Library/Metis/");
}

NSString *MTPublicConfigDirectory(void) {
    return MTResolvePath(@"/Library/Metis/Config/");
}

NSString *MTGateSnapshotPath(void) {
    return [MTPublicConfigDirectory() stringByAppendingPathComponent:@"gate.plist"];
}
