//
//  KayokoShortcutPickerController.h
//  Kayoko
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Pushed from the custom-action editor to pick one of an app's long-press
// quick actions (static or dynamic); reports the item title, owning bundle
// identifier and the UIApplicationShortcutItemType, then pops back.
@interface KayokoShortcutPickerController : UIViewController

@property(nonatomic, copy, nullable) NSString *currentBundleID;
@property(nonatomic, copy, nullable) NSString *currentType;
@property(nonatomic, copy, nullable) void (^completionHandler)(NSString *title, NSString *bundleID, NSString *type);

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
