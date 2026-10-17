#import "DXDarwinOpenChannel.h"

FOUNDATION_EXPORT BOOL DXSystemExitActionAvailable(NSString *action);
FOUNDATION_EXPORT DXSystemOpenResult DXPerformSystemAction(NSString *action);
FOUNDATION_EXPORT void DXPerformSystemRecordingAction(NSString *action, DXSystemOpenReply reply);
FOUNDATION_EXPORT BOOL DXConfirmSystemExitAction(NSString *action, NSProgress *operation);
FOUNDATION_EXPORT void DXCancelSystemActionConfirmation(void);
FOUNDATION_EXPORT NSDictionary *DXReadPanelSystemControlState(void);
FOUNDATION_EXPORT DXSystemOpenResult DXPerformPanelSystemControl(NSString *action, NSNumber *value);
