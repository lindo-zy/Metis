#import "DXPLauncherAppsController.h"
#import "DXPOpenAppPickerController.h"
#import "DXPAppInfo.h"
#import "common.h"

static NSString *DXLSettings(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}
@interface DXPLauncherAppsController ()
@property(nonatomic, strong) NSMutableArray<NSString *> *identifiers;
@property(nonatomic, strong) NSMutableDictionary *aliases;
@property(nonatomic, copy) NSArray<NSString *> *aliasOnly;
@end
@implementation DXPLauncherAppsController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = DXLSettings(@"QUICK_MANAGE");
    self.tableView.rowHeight = 58;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
        target:self action:@selector(addApplications)];
    NSDictionary *prefs = DXPrefsManager.sharedInstance.readPrefs;
    NSArray *selected = DXKbdHandleAppsFromPreferences(prefs);
    self.identifiers = [NSMutableArray array];
    id order = prefs[kKbdLauncherOrderKey];
    if ([order isKindOfClass:NSArray.class]) for (id identifier in order) {
        if ([identifier isKindOfClass:NSString.class] && [selected containsObject:identifier] &&
            ![self.identifiers containsObject:identifier]) [self.identifiers addObject:identifier];
    }
    NSArray *remaining = [selected sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [([DXPAppInfo displayNameForBundleID:a] ?: a) localizedStandardCompare:([DXPAppInfo displayNameForBundleID:b] ?: b)];
    }];
    for (NSString *identifier in remaining) if (![self.identifiers containsObject:identifier]) [self.identifiers addObject:identifier];
    id aliases = prefs[kKbdLauncherAliasesKey];
    self.aliases = [NSMutableDictionary dictionary];
    if ([aliases isKindOfClass:NSDictionary.class]) for (id identifier in aliases) {
        if (DXIsValidBundleIdentifier(identifier) && [aliases[identifier] isKindOfClass:NSArray.class]) {
            NSMutableArray *values = [NSMutableArray array];
            for (id value in aliases[identifier]) if ([value isKindOfClass:NSString.class] && [value length] && [value length] <= 128 && values.count < 8) [values addObject:value];
            if (values.count) self.aliases[identifier] = values;
        }
    }
    [self updateAliasOnly]; self.tableView.allowsSelectionDuringEditing = YES;
    [self.tableView setEditing:YES animated:NO];
}
- (void)updateAliasOnly {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSString *identifier in self.aliases) if (![self.identifiers containsObject:identifier]) [ids addObject:identifier];
    self.aliasOnly = [ids sortedArrayUsingSelector:@selector(compare:)];
}
- (void)save {
    DXPrefsManager *manager = DXPrefsManager.sharedInstance;
    // One read-modify-write avoids three notifications and preserves unrelated preferences.
    NSMutableDictionary *prefs = [manager.readPrefs mutableCopy] ?: [NSMutableDictionary dictionary];
    prefs[kKbdHandleAppsKey] = [self.identifiers copy]; prefs[kKbdLauncherOrderKey] = [self.identifiers copy];
    prefs[kKbdLauncherAliasesKey] = [self.aliases copy]; [manager writePrefs:prefs];
    [self updateAliasOnly];
}
- (void)addApplications {
    DXPOpenAppPickerController *picker = [DXPOpenAppPickerController new]; picker.allowsMultipleSelection = YES;
    __weak typeof(self) weakSelf = self;
    picker.multiSelectionCompletion = ^(NSArray<DXPAppInfo *> *apps) {
        DXPLauncherAppsController *controller = weakSelf;
        if (!controller) return;
        for (DXPAppInfo *app in apps) if (DXIsValidBundleIdentifier(app.bundleID) && ![controller.identifiers containsObject:app.bundleID]) [controller.identifiers addObject:app.bundleID];
        [controller save]; [controller.tableView reloadData];
    };
    [self.navigationController pushViewController:picker animated:YES];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.identifiers.count : self.aliasOnly.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return DXLSettings(section == 0 ? @"QUICK_FAVORITES" : @"QUICK_ALIAS_ONLY");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? DXLSettings(@"QUICK_MANAGE_FOOTER") : DXLSettings(@"QUICK_ALIAS_FOOTER");
}
- (NSString *)identifierAtPath:(NSIndexPath *)path {
    NSArray *pool = path.section == 0 ? self.identifiers : self.aliasOnly;
    return path.row >= 0 && (NSUInteger)path.row < pool.count ? pool[path.row] : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    NSString *identifier = [self identifierAtPath:path];
    cell.textLabel.text = [DXPAppInfo displayNameForBundleID:identifier] ?: identifier;
    cell.detailTextLabel.text = [self.aliases[identifier] count] ? [self.aliases[identifier] componentsJoinedByString:@", "] : DXLSettings(@"QUICK_EDIT_ALIAS");
    cell.imageView.image = [DXPAppInfo iconForBundleID:identifier]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.showsReorderControl = path.section == 0; return cell;
}
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path { return path.section == 0; }
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)target {
    return target.section == 0 ? target : [NSIndexPath indexPathForRow:MAX(0, (NSInteger)self.identifiers.count - 1) inSection:0];
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)target {
    if (source.section || target.section || source.row >= self.identifiers.count || target.row >= self.identifiers.count) return;
    NSString *identifier = self.identifiers[source.row]; [self.identifiers removeObjectAtIndex:source.row];
    [self.identifiers insertObject:identifier atIndex:target.row]; [self save];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    NSString *identifier = [self identifierAtPath:path]; if (!identifier) return;
    if (path.section == 0) [self.identifiers removeObject:identifier]; else [self.aliases removeObjectForKey:identifier];
    [self save]; [tableView reloadData];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSString *identifier = [self identifierAtPath:path]; if (!identifier) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[DXPAppInfo displayNameForBundleID:identifier] ?: identifier
        message:DXLSettings(@"QUICK_ALIAS_MESSAGE") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [self.aliases[identifier] componentsJoinedByString:@", "];
        field.placeholder = @"xhs, 948"; field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:DXLSettings(@"QUICK_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:DXLSettings(@"QUICK_SAVE") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        DXPLauncherAppsController *controller = weakSelf; if (!controller) return;
        NSString *text = [weakAlert.textFields.firstObject.text stringByReplacingOccurrencesOfString:@"，" withString:@","];
        NSMutableOrderedSet *values = [NSMutableOrderedSet orderedSet];
        for (NSString *part in [text componentsSeparatedByString:@","]) {
            NSString *alias = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (alias.length && alias.length <= 128 && values.count < 8) [values addObject:alias];
        }
        if (values.count) controller.aliases[identifier] = values.array; else [controller.aliases removeObjectForKey:identifier];
        [controller save]; [controller.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
