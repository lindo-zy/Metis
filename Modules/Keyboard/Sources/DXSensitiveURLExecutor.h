#import "DXDarwinOpenChannel.h"

typedef BOOL (^DXSensitiveURLDelivery)(NSURL *url);

// The delivery block is a potentially blocking SBS client RPC, never UIKit.
// The reply runs on the main queue. No retry, no synthetic application launch,
// no main-thread wait: a delivered prefs URL reaches Settings (or an intercepting
// tweak such as ShellX) through the system URL dispatch, which already handles
// foregrounding.
FOUNDATION_EXPORT void DXExecuteSensitiveURL(NSURL *url, NSDate *deadline,
    NSProgress *request, DXSensitiveURLDelivery deliver, DXSystemOpenReply reply);
