#import "MTDarwinOpenChannel.h"

FOUNDATION_EXPORT BOOL MTSystemExitActionAvailable(NSString *action);
FOUNDATION_EXPORT MTSystemOpenResult MTPerformSystemAction(NSString *action);
FOUNDATION_EXPORT void MTPerformSystemRecordingAction(NSString *action, MTSystemOpenReply reply);
FOUNDATION_EXPORT BOOL MTConfirmSystemExitAction(NSString *action, NSProgress *operation);
FOUNDATION_EXPORT void MTCancelSystemActionConfirmation(void);
FOUNDATION_EXPORT NSDictionary *MTReadPanelSystemControlState(void);
FOUNDATION_EXPORT MTSystemOpenResult MTPerformPanelSystemControl(NSString *action, NSNumber *value);
