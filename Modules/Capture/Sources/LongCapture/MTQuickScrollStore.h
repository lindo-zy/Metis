#import <UIKit/UIKit.h>
#import "MTQuickScrollMatcher.h"
#import "../Common/MTLongShotOptions.h"
#import "../Common/MTLongShotControl.h"

NS_ASSUME_NONNULL_BEGIN
@interface MTQuickScrollResult : NSObject
@property (nonatomic) MTQuickScrollMatch match;
@property (nonatomic) NSInteger count, totalHeight;
@property (nonatomic, strong, nullable) UIImage *preview;
@end

/// Single background queue only. One tracking signature; confirmed strips on disk.
@interface MTQuickScrollStore : NSObject
- (instancetype)initWithDirectory:(NSString *)directory options:(MTLongShotOptions *)options
                     cancellation:(MTLongShotCancellation *)cancellation scale:(CGFloat)scale;
- (nullable MTQuickScrollResult *)consumeImage:(UIImage *)image pixelRect:(CGRect)rect
                                    timestamp:(CFTimeInterval)timestamp final:(BOOL)final error:(NSError **)error;
- (nullable UIImage *)exportToURL:(NSURL *)url error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
