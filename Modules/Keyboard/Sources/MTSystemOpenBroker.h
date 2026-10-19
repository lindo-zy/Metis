#import "MTDarwinOpenChannel.h"

FOUNDATION_EXPORT BOOL MTIsSensitiveOpenScheme(NSString *scheme);
FOUNDATION_EXPORT void MTOpenSystemApplication(NSString *bundleIdentifier, MTSystemOpenReply reply);
FOUNDATION_EXPORT void MTOpenFloatingApplication(NSString *bundleIdentifier, MTSystemOpenReply reply);
FOUNDATION_EXPORT void MTOpenFloatingURL(NSURL *url, MTSystemOpenReply reply);
FOUNDATION_EXPORT void MTOpenSensitiveSystemURL(NSURL *url, MTSystemOpenReply reply);
FOUNDATION_EXPORT void MTOpenSystemShortcut(NSString *bundleIdentifier, NSString *shortcutType, MTSystemOpenReply reply);
FOUNDATION_EXPORT BOOL MTStartSystemOpenBroker(void);
FOUNDATION_EXPORT void MTRunSystemAction(NSString *identifier, MTSystemOpenReply reply);
FOUNDATION_EXPORT void MTRequestStatusBarGesture(NSString *slot, NSString *expectedSelector, BOOL landscape, MTSystemOpenReply reply);
FOUNDATION_EXPORT void MTRequestCornerGesture(NSString *slot, NSString *expectedSelector, MTSystemOpenReply reply);
typedef void (^MTPanelSystemControlReply)(MTSystemOpenResult result, NSDictionary *state);
FOUNDATION_EXPORT NSProgress *MTRequestPanelSystemControl(NSString *action, NSNumber *value, NSString *source, MTPanelSystemControlReply reply);

FOUNDATION_EXPORT void MTRestoreFloatingApplication(NSString *identifier, uint64_t revision, MTSystemOpenReply reply);
