#import <Foundation/Foundation.h>

typedef NS_ENUM(uint64_t, DXSystemOpenResult) {
    DXSystemOpenSucceeded = 1,
    DXSystemOpenFailed,
    DXSystemOpenInvalid,
    DXSystemOpenBusy,
    DXSystemOpenExpired,
    DXSystemOpenUnavailable,
    DXSystemOpenTimedOut,
};

typedef void (^DXSystemOpenReply)(DXSystemOpenResult result);
typedef void (^DXSystemOpenHandler)(NSDictionary *request, DXSystemOpenReply reply);
FOUNDATION_EXPORT NSTimeInterval const DXSystemOpenRequestTTL;

// Handlers and client completions run on the main queue. Each request is sent
// once. A timeout means the outcome is unknown; it must never cause a retry.
FOUNDATION_EXPORT void DXSendDarwinOpenRequest(NSString *kind, NSString *payload, DXSystemOpenReply reply);
FOUNDATION_EXPORT BOOL DXStartDarwinOpenServer(DXSystemOpenHandler handler);
