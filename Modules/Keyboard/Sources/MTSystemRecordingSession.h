#import "MTDarwinOpenChannel.h"

// Main-queue single-flight guard for ReplayKit's asynchronous system actions.
// The executor supplies the native recorder only from SpringBoard.
@interface MTSystemRecordingSession : NSObject
- (void)toggleRecorder:(id)recorder microphoneEnabled:(BOOL)enabled reply:(MTSystemOpenReply)reply;
@end
