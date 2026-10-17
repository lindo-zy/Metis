#import <Preferences/PSViewController.h>
#import <Preferences/PSSpecifier.h>
#import "common.h"

@class MTSettingsRow;

@interface MTPManageShortcutsController : PSViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) UITextField *testInputField;
@property (nonatomic, strong) NSMutableArray *currentOrder;
@property (nonatomic, strong) NSArray *fullOrder;
@property(nonatomic, retain) UIBarButtonItem *addBtn;
@property(nonatomic, copy) NSString *shortcutsPreferenceKey;
@property(nonatomic, assign, getter=isTopConfiguration) BOOL topConfiguration;

// Settings rows are built once per page load; every row resolves its
// preference key for this page's toolbar scope.
@property (nonatomic, copy) NSArray<MTSettingsRow *> *appearanceRows;
@property (nonatomic, copy) NSArray<MTSettingsRow *> *panelRows;
@property (nonatomic, copy) NSArray<MTSettingsRow *> *offsetRows;
// 顶部页专属：按钮行距（每行个数在按钮设置分组）。
@property (nonatomic, copy) NSArray<MTSettingsRow *> *multiRowRows;
@end
