#import "MTDarwinOpenChannel.h"

// The client APIs live in MTSystemOpenBroker. These entry points execute only
// in SpringBoard on the main queue; they never call another tweak's API.
FOUNDATION_EXPORT void MTStartFloatingAppHost(void);
FOUNDATION_EXPORT void MTPresentFloatingApplication(NSString *bundleIdentifier, NSURL *url,
                                                   NSDate *deadline, MTSystemOpenReply reply);
FOUNDATION_EXPORT NSString *MTFloatingBundleIdentifierForURL(NSURL *url);

FOUNDATION_EXPORT void MTRestoreFloatingAppFromShelf(NSString *identifier, uint64_t revision, NSDate *deadline, MTSystemOpenReply reply);
