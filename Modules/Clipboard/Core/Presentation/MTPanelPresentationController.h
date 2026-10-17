//
//  MTPanelPresentationController.h
//  Mt
//

#import <UIKit/UIKit.h>

#import "MTPanelPresentationMode.h"

@class MTPanelPresentationController;
@class MTHeaderView;
@class MTMainView;

NS_ASSUME_NONNULL_BEGIN

@protocol MTPanelPresentationControllerDelegate <NSObject>

- (void)panelPresentationControllerDidRequestDismiss:(MTPanelPresentationController *)controller;
- (void)panelPresentationControllerDidTapGrabberArea:(MTPanelPresentationController *)controller;
- (void)panelPresentationControllerDidDoubleTapHeaderArea:(MTPanelPresentationController *)controller;
- (BOOL)panelPresentationControllerShouldHandleFullscreenSearchPan:(MTPanelPresentationController *)controller;
- (BOOL)panelPresentationController:(MTPanelPresentationController *)controller
    shouldBeginExpandedPanelPanFromView:(nullable UIView *)view
                               velocity:(CGPoint)velocity;
- (void)panelPresentationController:(MTPanelPresentationController *)controller
    handleFullscreenSearchPanGestureRecognizer:(UIPanGestureRecognizer *)recognizer
                                    headerView:(nullable MTHeaderView *)headerView;

@end

@interface MTPanelPresentationController : NSObject

@property(nonatomic, weak, nullable) id<MTPanelPresentationControllerDelegate> delegate;
@property(nonatomic, assign, getter=isDismissOnOutsideTouch) BOOL dismissOnOutsideTouch;
@property(nonatomic, assign) BOOL shouldPlayFeedback;
@property(nonatomic, assign) MTPanelPresentationMode presentationMode;
@property(nonatomic, strong, readonly) UIPanGestureRecognizer *panGestureRecognizer;
@property(nonatomic, assign, readonly, getter=isAnimating) BOOL animating;

- (instancetype)initWithPanelView:(MTMainView *)panelView;
- (void)registerHeaderView:(MTHeaderView *)headerView;
- (void)setOutsideDismissOverlayView:(nullable UIControl *)outsideDismissOverlayView;
- (void)prepareStandardDismissAnimation;
- (void)showPanelWithCompletion:(nullable void (^)(void))completion;
- (void)hidePanelWithCompletion:(nullable void (^)(void))completion;
- (void)hidePanelWithAnimationStyle:(MTPanelHideAnimationStyle)animationStyle
                         completion:(nullable void (^)(void))completion;
- (void)hidePanelImmediatelyWithCompletion:(nullable void (^)(void))completion;
- (void)finishOutsideDismissOverlayShow;
- (void)triggerHapticFeedbackWithStyle:(UIImpactFeedbackStyle)style;

@end

NS_ASSUME_NONNULL_END
