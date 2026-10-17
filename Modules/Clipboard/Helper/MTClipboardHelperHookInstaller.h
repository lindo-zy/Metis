//
//  MTClipboardHelperHookInstaller.h
//  Mt
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTClipboardHelperHookInstaller : NSObject
+ (void)installApplicationHooksWithActivationMethod:(NSUInteger)activationMethod;
+ (void)installSpringBoardActivationHooksWithActivationMethod:(NSUInteger)activationMethod;
+ (void)installKeyboardExtensionHooksWithActivationMethod:(NSUInteger)activationMethod
                                     spotlightSwipeUpOnly:(BOOL)spotlightSwipeUpOnly;
@end

@interface MTClipboardHelperHookInstaller (PredictionBar)
+ (void)installPredictionBarHooks;
@end

@interface MTClipboardHelperHookInstaller (CalloutMenu)
+ (void)installCalloutBarHooks;
@end

@interface MTClipboardHelperHookInstaller (InputSwitcher)
+ (void)installInputSwitcherHooks;
@end

@interface MTClipboardHelperHookInstaller (Dictation)
+ (void)installDictationHooks;
@end

@interface MTClipboardHelperHookInstaller (SwipeUp)
+ (void)installSwipeUpHooks;
+ (void)installKeyboardExtensionSwipeUpHooksForSpotlightOnly:(BOOL)spotlightOnly;
@end

@interface MTClipboardHelperHookInstaller (URLOpen)
@end

NS_ASSUME_NONNULL_END
