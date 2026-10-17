#import <Foundation/Foundation.h>

typedef NS_ENUM(uint64_t, MTSystemOpenResult) {
    MTSystemOpenSucceeded = 1,
    MTSystemOpenFailed,
    MTSystemOpenInvalid,
    MTSystemOpenBusy,
    MTSystemOpenExpired,
    MTSystemOpenUnavailable,
    MTSystemOpenTimedOut,
};

typedef void (^MTSystemOpenReply)(MTSystemOpenResult result);
typedef void (^MTSystemOpenHandler)(NSDictionary *request, MTSystemOpenReply reply);
FOUNDATION_EXPORT NSTimeInterval const MTSystemOpenRequestTTL;

// Handlers and client completions run on the main queue. Each request is sent
// once. A timeout means the outcome is unknown; it must never cause a retry.
FOUNDATION_EXPORT void MTSendDarwinOpenRequest(NSString *kind, NSString *payload, MTSystemOpenReply reply);
FOUNDATION_EXPORT BOOL MTStartDarwinOpenServer(MTSystemOpenHandler handler);
