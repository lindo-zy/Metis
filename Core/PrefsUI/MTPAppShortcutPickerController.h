#import <Preferences/PSViewController.h>
@class MTPAppShortcutItem;

@interface MTPAppShortcutPickerController : PSViewController
@property (nonatomic, copy) NSString *selectedBundleIdentifier;
@property (nonatomic, copy) NSString *selectedShortcutType;
@property (nonatomic, copy) void (^completion)(NSString *bundleIdentifier, NSString *appName, MTPAppShortcutItem *item);
@end
