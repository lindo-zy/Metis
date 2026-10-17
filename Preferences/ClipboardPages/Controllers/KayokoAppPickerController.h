//
//  KayokoAppPickerController.h
//  Kayoko
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Pushed from the custom-action editor to pick an installed app; reports the
// localized name plus bundle identifier and pops back.
@interface KayokoAppPickerController : UIViewController

@property(nonatomic, copy, nullable) NSString *currentBundleID;
@property(nonatomic, copy, nullable) void (^completionHandler)(NSString *name, NSString *bundleID);

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
