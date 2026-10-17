//
//  MTMainViewController.h
//  Mt
//

#import <UIKit/UIKit.h>

#import "MTPanelPresentationMode.h"
#import "MTPreferenceKeys.h"

NS_ASSUME_NONNULL_BEGIN

@class MTMainViewController;
@class MTPasteboardItem;

@protocol MTMainViewControllerDelegate <NSObject>

- (void)mainViewControllerDidRequestFocusRestore:(MTMainViewController *)viewController;
- (void)mainViewControllerDidHide:(MTMainViewController *)viewController;

@end

@interface MTMainViewController : UIViewController

@property(nonatomic, weak, nullable) id<MTMainViewControllerDelegate> delegate;
@property(nonatomic, assign) BOOL automaticallyPaste;
@property(nonatomic, assign) BOOL privacyMode;
@property(nonatomic, assign) BOOL dismissOnOutsideTouch;
@property(nonatomic, assign) BOOL swipeToSelectWords;
@property(nonatomic, assign) MTInitialViewMode initialViewMode;
@property(nonatomic, assign) BOOL alwaysScrollToTop;
@property(nonatomic, assign) MTClearButtonMode clearButtonMode;
@property(nonatomic, assign) NSUInteger previewLineCount;
@property(nonatomic, assign) MTItemDetailsMode itemDetailsMode;
@property(nonatomic, assign) BOOL shouldPlayFeedback;
@property(nonatomic, assign) MTPanelPresentationMode presentationMode;
@property(nonatomic, assign) UIInterfaceOrientationMask mtSupportedInterfaceOrientations;

- (instancetype)initWithFrame:(CGRect)frame;

- (BOOL)isHidden;
- (void)setOutsideDismissOverlayView:(nullable UIControl *)outsideDismissOverlayView;
- (void)applyUserInterfaceStyle:(UIUserInterfaceStyle)style;

- (void)handleHistoryChanged;
- (void)handleApplicationMetadataChanged;
- (void)preloadHistoryIfNeeded;
- (BOOL)isFullscreenSearchActive;
- (BOOL)isNoteEditing;
- (BOOL)isPreviewTextEditing;
- (BOOL)isEditingAnyContent;
- (BOOL)shouldSuppressSystemMultitaskingGesture;
- (void)show;
- (void)showWithCompletion:(nullable void (^)(void))completion;
- (void)showQuickPreviewForItem:(MTPasteboardItem *)item;
- (void)hide;
- (void)hideRestoringFocus;
- (void)hideWithStandardDismissAnimation;
- (void)hideWithCompletion:(nullable void (^)(void))completion;
- (void)hideWithAnimationStyle:(MTPanelHideAnimationStyle)animationStyle
                    completion:(nullable void (^)(void))completion;
- (void)hideForExternalRequestWithAnimationStyle:(MTPanelHideAnimationStyle)animationStyle
                                      completion:(nullable void (^)(void))completion;
- (void)hideImmediately;
- (void)reload;

@end

NS_ASSUME_NONNULL_END
