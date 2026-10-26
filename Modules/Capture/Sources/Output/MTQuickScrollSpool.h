#import <UIKit/UIKit.h>
#import "../Common/MTLongShotControl.h"

NS_ASSUME_NONNULL_BEGIN
/// Disk-backed RGB rows. Appends are transactional; export never allocates a full canvas.
@interface MTQuickScrollSpool : NSObject
@property (nonatomic, readonly) NSInteger height;
@property (nonatomic, copy, nullable) void (^onProgress)(void);
- (instancetype)initWithDirectory:(NSString *)directory cancellation:(MTLongShotCancellation *)cancellation;
- (BOOL)appendImage:(UIImage *)image rect:(CGRect)rect scrubRightColumns:(NSInteger)columns error:(NSError **)error;
- (BOOL)writePNGToURL:(NSURL *)url error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
