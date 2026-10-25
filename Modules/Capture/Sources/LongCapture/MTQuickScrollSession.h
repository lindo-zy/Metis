#import "../Capture/MTLongShotSession.h"
NS_ASSUME_NONNULL_BEGIN
/// CADisplayLink-driven manual continuous capture. Starts immediately, no HID driver.
@interface MTQuickScrollSession : NSObject <MTLongShotSessionControl>
+ (nullable instancetype)startWithTask:(MTCaptureTask *)task displayRect:(CGRect)displayRect
                             delegate:(id<MTLongShotSessionDelegate>)delegate;
@end
NS_ASSUME_NONNULL_END
