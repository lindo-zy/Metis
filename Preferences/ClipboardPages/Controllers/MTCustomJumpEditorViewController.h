//
//  MTCustomJumpEditorViewController.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTCustomJump;

NS_ASSUME_NONNULL_BEGIN

@interface MTCustomJumpEditorViewController : UIViewController

@property(nonatomic, copy, nullable) void (^completionHandler)(MTCustomJump *jump);

- (instancetype)initWithJump:(MTCustomJump *)jump localizationBundle:(NSBundle *)localizationBundle;
- (instancetype)initWithJump:(MTCustomJump *)jump
            localizationBundle:(NSBundle *)localizationBundle
                isImageAction:(BOOL)isImageAction;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
