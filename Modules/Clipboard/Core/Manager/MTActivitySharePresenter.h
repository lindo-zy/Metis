//
//  MTActivitySharePresenter.h
//  Mt
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTActivitySharePresenter : NSObject

- (BOOL)presentActivityItems:(NSArray *)items
              fromController:(UIViewController *)controller
                  anchorView:(nullable UIView *)anchorView;
- (void)dismissActivityAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
