//
//  MTExternalHideCoordinator.h
//  Mt
//

#import <Foundation/Foundation.h>

#import "MTPanelPresentationMode.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTExternalHideRequest : NSObject

@property(nonatomic, assign, readonly) MTPanelHideAnimationStyle animationStyle;
@property(nonatomic, copy, readonly, nullable) void (^completion)(void);

- (instancetype)initWithAnimationStyle:(MTPanelHideAnimationStyle)animationStyle
                            completion:(nullable void (^)(void))completion;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MTExternalHideCoordinator : NSObject

@property(nonatomic, assign, readonly, getter=isSearchInputTransitionSuppressed) BOOL searchInputTransitionSuppressed;
@property(nonatomic, assign, readonly, getter=hasPendingExternalHideRequest) BOOL pendingExternalHideRequest;

- (void)beginSearchInputTransitionSuppressionWithDuration:(NSTimeInterval)duration
                                        expirationHandler:(nullable void (^)(void))expirationHandler;
- (void)endSearchInputTransitionSuppression;
- (BOOL)shouldSuppressExternalHide;
- (BOOL)recordPendingExternalHideRequestWithAnimationStyle:(MTPanelHideAnimationStyle)animationStyle
                                                completion:(nullable void (^)(void))completion;
- (nullable MTExternalHideRequest *)takePendingExternalHideRequest;
- (void)clear;

@end

NS_ASSUME_NONNULL_END
