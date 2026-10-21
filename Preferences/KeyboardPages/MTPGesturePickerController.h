#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface MTPGesturePickerController : PSListController{
    UILabel *_label;
}
@property (nonatomic,readwrite) NSString *identifier;
@property (nonatomic, strong) NSArray *fullOrder;
@property (nonatomic, copy) NSString *configuration;
// YES when pushed from the "+" button: the button itself does not exist yet.
// Name/icon input and gesture choices are staged, then written automatically
// as soon as one gesture carries a selection (no Save button on this page).
@property (nonatomic, assign) BOOL pendingNewEntry;
// Pending (unsaved) name/icon typed on the new-button page.
@property (nonatomic, copy) NSString *pendingName;
@property (nonatomic, copy) NSString *pendingIcon;
@end

@interface PSSpecifier (MTPGesturePickerController)
-(void)setValues:(id)arg1 titles:(id)arg2;
@end
