#import <Preferences/PSListController.h>

@interface MTOCRSettingsController : PSListController
@end
@implementation MTOCRSettingsController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"OCR" target:self];
    return _specifiers;
}
@end
