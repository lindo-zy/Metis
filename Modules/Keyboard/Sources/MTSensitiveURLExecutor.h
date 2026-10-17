#import "MTDarwinOpenChannel.h"

typedef BOOL (^MTSensitiveURLDelivery)(NSURL *url);

// The delivery block is a potentially blocking SBS client RPC, never UIKit.
// The reply runs on the main queue. No retry, no synthetic application launch,
// no main-thread wait: a delivered prefs URL reaches Settings (or an intercepting
// tweak such as ShellX) through the system URL dispatch, which already handles
// foregrounding.
FOUNDATION_EXPORT void MTExecuteSensitiveURL(NSURL *url, NSDate *deadline,
    NSProgress *request, MTSensitiveURLDelivery deliver, MTSystemOpenReply reply);
