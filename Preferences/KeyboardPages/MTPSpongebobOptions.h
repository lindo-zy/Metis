#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface MTPSpongebobOptions : PSListController <UISearchBarDelegate>
@end

@interface PSSpecifier (MTPSpongebobOptions)
-(void)setValues:(id)arg1 titles:(id)arg2;
@end
