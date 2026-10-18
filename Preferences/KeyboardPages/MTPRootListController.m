#import "MTPRootListController.h"
#import "common.h"
#import "MTHelper.h"
#import "MTSettingsSearch.h"

static NSBundle *mtpLocalBundle;

@interface MTPRootListController () <UISearchResultsUpdating>
@property(nonatomic, strong) UISearchController *settingsSearch;
@property(nonatomic, copy) NSArray<PSSpecifier *> *allSettingsSpecifiers;
@end


@implementation MTPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        
        self.allSettingsSpecifiers = [_specifiers copy];
        self.dynamicSpecifiers = (!self.dynamicSpecifiers) ? [[NSMutableDictionary alloc] init] : self.dynamicSpecifiers;
    }
    
    
    return _specifiers;
}

#pragma mark - 生效应用（AltList 多选页 get/set）

// 历史版本把 pasteimagechipapps 存成 bundleID→@YES 字典，AltList 多选页存
// 已开启 bundleID 数组。读取侧统一规整成数组（只在内存转换，不回写，首次
// 拨动开关时自然落盘为新格式）；tweak 侧（MTPasteChip）两种格式都认。
- (id)mtp_pasteChipAppsRead:(PSSpecifier *)specifier {
    id value = [self readPreferenceValue:specifier];
    if ([value isKindOfClass:[NSArray class]]) return value;
    if (![value isKindOfClass:[NSDictionary class]]) return @[];

    NSMutableArray<NSString *> *enabled = [NSMutableArray array];
    for (NSString *bundleID in value) {
        NSNumber *flag = value[bundleID];
        if ([bundleID isKindOfClass:[NSString class]] &&
            [flag isKindOfClass:[NSNumber class]] && flag.boolValue) {
            [enabled addObject:bundleID];
        }
    }
    return enabled;
}

// setPreferenceValue:specifier: 负责域写入；这里显式补发 prefschanged，
// 保证键盘进程立刻感知（与各开关的 PostNotification 等效，双发无害）。
- (void)mtp_pasteChipAppsWrite:(id)value specifier:(PSSpecifier *)specifier {
    [self setPreferenceValue:value specifier:specifier];

    CFStringRef notificationName = (__bridge CFStringRef)kPrefsChangedIdentifier;
    if (notificationName) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), notificationName, NULL, NULL, YES);
    }
}

-(void)viewDidLoad  {
    mtpLocalBundle = [NSBundle bundleWithPath:bundlePath];
    [mtpLocalBundle load];
    [super viewDidLoad];

    // 模块内不再挂品牌 logo 头（2026-10-17 需求）：品牌只在系统设置首页出现，
    // 这里只保留搜索框与 Respring 按钮。

    //search bar
    
    self.settingsSearch = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.settingsSearch.searchResultsUpdater = self;
    self.settingsSearch.searchBar.delegate = self;
    self.definesPresentationContext = YES;
    self.settingsSearch.definesPresentationContext = YES;
    self.settingsSearch.hidesNavigationBarDuringPresentation = NO;
    
    self.settingsSearch.searchBar.placeholder = LOCALIZED(@"SEARCHBAR_PLACEHOLDER");
    [self.settingsSearch.searchBar setImage:[MTHelper imageForTypeXWithPlaceholder:YES] forSearchBarIcon:UISearchBarIconSearch state:UIControlStateNormal];

    self.settingsSearch.obscuresBackgroundDuringPresentation = NO;
    
    if (@available(iOS 11.0, *)){
        self.navigationItem.searchController = self.settingsSearch;
        self.navigationItem.hidesSearchBarWhenScrolling = YES;
    }
    //search bar

    self.respringBtn = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"RESPRING") style:UIBarButtonItemStylePlain target:self action:@selector(respring)];
    //self.addSnippetBtn.tintColor = [UIColor blackColor];
    self.navigationItem.rightBarButtonItem = self.respringBtn;
    
}

-(id)readPreferenceValue:(PSSpecifier*)specifier{
    NSString *key = [specifier propertyForKey:@"key"];
    id value = [super readPreferenceValue:specifier];
    if (key.length > 0) {
        id storedValue = [[MTPrefsManager sharedInstance] getValueForKey:key];
        if (storedValue != nil) value = storedValue;
    }
    return value;
}


- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier{
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length > 0) {
        // Keep PreferenceLoader UI writes on the same CFPreferences/plist path
        // used by SpringBoard and the keyboard process.
        [[MTPrefsManager sharedInstance] setValue:value forKey:key];
    } else {
        [super setPreferenceValue:value specifier:specifier];
    }
}

- (void)respring {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MetisKeyboard" message:LOCALIZED(@"RESPRING_MESSAGE") preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *respringAction = [UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_YES") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        
        NSURL *relaunchURL = [NSURL URLWithString:@"prefs:root=MetisKeyboard"];
        SBSRelaunchAction *restartAction = [NSClassFromString(@"SBSRelaunchAction") actionWithReason:@"RestartRenderServer" options:4 targetURL:relaunchURL];
        [[NSClassFromString(@"FBSSystemService") sharedService] sendActions:[NSSet setWithObject:restartAction] withResult:nil];
        
        /*
         pid_t pid;
         int status;
         const char *args[] = {"killall", "-9", "SpringBoard", NULL};
         posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char * const *)args, NULL);
         waitpid(pid, &status, WEXITED);
         */
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_NO") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
    
    [alert addAction:respringAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSArray *all = self.allSettingsSpecifiers ?: [self.specifiers copy];
    NSMutableArray *rows = [NSMutableArray array];
    for (PSSpecifier *specifier in all) {
        NSString *text = [NSString stringWithFormat:@"%@ %@", specifier.name ?: @"", [specifier propertyForKey:@"footerText"] ?: @""];
        [rows addObject:@{@"group": @(specifier.cellType == PSGroupCell), @"text": text}];
    }
    NSIndexSet *matches = MTSettingsSearchIndices(rows, controller.searchBar.text ?: @"");
    self.specifiers = [[all objectsAtIndexes:matches] mutableCopy];
    [self.table reloadData];
}
- (void)viewWillDisappear:(BOOL)animated {
    self.settingsSearch.active = NO;
    self.settingsSearch.searchBar.text = @"";
    [self updateSearchResultsForSearchController:self.settingsSearch];
    [self.view endEditing:YES];
    [super viewWillDisappear:animated];
}
-(BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar{
    MTPrefsManager *prefsManager = [MTPrefsManager sharedInstance];
    NSUInteger tappedCount = [[prefsManager getValueForKey:@"searchedc"] longValue];
    [prefsManager setValue:@(tappedCount + 1) forKey:@"searchedc"];
    if (tappedCount + 1 == searchedCountEaster){
        [MTHelper showSearchCountEasterAlertFor:self searchController:self.settingsSearch count:tappedCount+1 delay:0.5];
    }
    return YES;
}

@end
