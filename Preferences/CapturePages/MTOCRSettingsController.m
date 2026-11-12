#import <Preferences/PSListController.h>
#import <UIKit/UIKit.h>

@interface MTOCRSettingsController : PSListController
@end
@implementation MTOCRSettingsController
- (void)openStudioTokenPage {
    NSURL *url = [NSURL URLWithString:@"https://aistudio.baidu.com/account/accessToken"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"OCR" target:self];
    return _specifiers;
}
@end
