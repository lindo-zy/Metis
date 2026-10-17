//
//  KayokoCustomJumpEditorViewController.h
//  Kayoko
//

#import <UIKit/UIKit.h>

@class KayokoCustomJump;

NS_ASSUME_NONNULL_BEGIN

@interface KayokoCustomJumpEditorViewController : UIViewController

@property(nonatomic, copy, nullable) void (^completionHandler)(KayokoCustomJump *jump);

- (instancetype)initWithJump:(KayokoCustomJump *)jump localizationBundle:(NSBundle *)localizationBundle;
- (instancetype)initWithJump:(KayokoCustomJump *)jump
            localizationBundle:(NSBundle *)localizationBundle
                isImageAction:(BOOL)isImageAction;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
