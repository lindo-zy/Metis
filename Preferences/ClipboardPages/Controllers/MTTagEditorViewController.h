//
//  MTTagEditorViewController.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTTag;

NS_ASSUME_NONNULL_BEGIN

@interface MTTagEditorViewController : UIViewController

@property(nonatomic, copy, nullable) void (^completionHandler)(MTTag *tag);
@property(nonatomic, copy, nullable) void (^dismissalTransitionHandler)
    (id<UIViewControllerTransitionCoordinator> _Nullable transitionCoordinator);

- (instancetype)initWithTag:(MTTag *)tag localizationBundle:(NSBundle *)localizationBundle;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
