#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@protocol MTQuickScrollHUDDelegate <NSObject>
- (void)quickScrollDidRequestCopy;
- (void)quickScrollDidRequestSave;
- (void)quickScrollDidDragBy:(CGPoint)translation;
@end

/// Compact phone-shaped viewport, matching the supplied recording.
@interface MTQuickScrollHUD : UIView
@property (nonatomic, weak) id<MTQuickScrollHUDDelegate> delegate;
- (void)setPreviewImage:(UIImage *)image;
- (void)setStatus:(NSString *)status paused:(BOOL)paused;
- (void)setFinishing;
- (void)setRetryMessage:(NSString *)message;
@end
NS_ASSUME_NONNULL_END
