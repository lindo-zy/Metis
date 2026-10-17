#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface MTPSnippetEntryController : PSListController
@property (nonatomic,readwrite) NSString *entryID;

@end

@interface PSSpecifier (MTPSnippetEntryController)
-(void)setValues:(id)arg1 titles:(id)arg2;
@end
