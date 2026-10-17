#import "DXDarwinOpenChannel.h"

// Main-queue single-flight guard for ReplayKit's asynchronous system actions.
// The executor supplies the native recorder only from SpringBoard.
@interface DXSystemRecordingSession : NSObject
- (void)toggleRecorder:(id)recorder microphoneEnabled:(BOOL)enabled reply:(DXSystemOpenReply)reply;
@end
