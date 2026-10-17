//
//  MTSystemTranslationPresenter.h
//  Mt
//

#import <Foundation/Foundation.h>

@class UIViewController;
@class UIView;

NS_ASSUME_NONNULL_BEGIN

@interface MTSystemTranslationPresenter : NSObject

@property(nonatomic, assign, readonly, getter=isAvailable) BOOL available;

- (BOOL)presentTranslationForText:(NSString *)text
                   fromController:(UIViewController *)controller
                       anchorView:(nullable UIView *)anchorView;
- (void)dismissTranslationAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
