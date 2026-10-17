//
//  MTPreviewViewController.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTPreviewView;
@class MTPreviewViewController;
@class MTPasteboardItem;

NS_ASSUME_NONNULL_BEGIN

@protocol MTPreviewViewControllerDelegate <NSObject>
- (void)previewViewControllerDidRequestEdit:(MTPreviewViewController *)controller;
@end

@interface MTPreviewViewController : UIViewController

@property(nonatomic, weak, nullable) id<MTPreviewViewControllerDelegate> delegate;
@property(nonatomic, strong, readonly) MTPreviewView *previewView;
@property(nonatomic, copy, nullable, readonly) NSString *sourceHistoryKey;
@property(nonatomic, strong, nullable, readonly) MTPasteboardItem *previewItem;
@property(nonatomic, copy, nullable) void (^hapticFeedbackHandler)(UIImpactFeedbackStyle style);

- (void)showPreviewWithItem:(MTPasteboardItem *)item sourceHistoryKey:(NSString *)sourceHistoryKey;
- (void)handleActionButtonWithCompletion:(nullable void (^)(BOOL success))completion;
- (void)handleImageActionButtonPressed;
- (void)setEditButtonEnabled:(BOOL)enabled;
- (void)hidePreview;
- (void)resetPreviewState;
- (void)scrollToTopAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
