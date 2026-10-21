#import "MTPJavaScriptRuleController.h"
#import "MTContextClassifier.h"
#import "MTContextGroupEngine.h"
#import "MTPrefsManager.h"

@interface MTPContextScriptEditor : UIViewController
@property(nonatomic, copy) NSString *source;
@property(nonatomic, strong) UITextView *editor;
@property(nonatomic, copy) void (^completion)(NSString *source, NSDictionary *result);
@end
@implementation MTPContextScriptEditor
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.systemGroupedBackgroundColor; self.title = MTPCTX(@"CTX_EDIT_SCRIPT");
    UILabel *banner = [UILabel new]; banner.text = MTPCTX(@"CTX_SANDBOX"); banner.numberOfLines = 0; banner.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; banner.textColor = UIColor.secondaryLabelColor;
    self.editor = [UITextView new]; self.editor.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular]; self.editor.text = self.source; self.editor.autocorrectionType = UITextAutocorrectionTypeNo; self.editor.autocapitalizationType = UITextAutocapitalizationTypeNone; self.editor.smartQuotesType = UITextSmartQuotesTypeNo; self.editor.smartDashesType = UITextSmartDashesTypeNo;
    for (UIView *view in @[banner, self.editor]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[[banner.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12], [banner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20], [banner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20], [self.editor.topAnchor constraintEqualToAnchor:banner.bottomAnchor constant:12], [self.editor.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12], [self.editor.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12], [self.editor.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-8]]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
}
- (void)save {
    NSString *source = self.editor.text ?: @""; self.navigationItem.rightBarButtonItem.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [[MTContextClassifier sharedClassifier] testRule:NSUUID.UUID.UUIDString source:source text:@"" completion:^(NSDictionary *result) {
        MTPContextScriptEditor *owner = weakSelf; if (!owner) return;
        owner.navigationItem.rightBarButtonItem.enabled = YES;
        if (owner.completion) owner.completion(source, result);
        [owner.navigationController popViewControllerAnimated:YES];
    }];
}
@end
@interface MTPJavaScriptRuleController ()
@property(nonatomic, copy) NSString *sample;
@property(nonatomic, copy) NSString *resultText;
@property(nonatomic, assign) BOOL running;
@end
@implementation MTPJavaScriptRuleController
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 3 : (section == 1 ? 2 : (section == 2 ? 2 : self.type.actions.count + 1)); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return MTPCTX(@[@"CTX_RULE", @"CTX_SCRIPT", @"CTX_TEST", @"CTX_ACTIONS"][section]); }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return section == 1 ? MTPCTX(@"CTX_SANDBOX") : (section == 3 ? [NSString stringWithFormat:MTPCTX(@"CTX_CAPACITY"), (unsigned long)self.slots] : nil); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 3) return [self actionCellAtIndex:path.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil]; cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    if (path.section == 0) {
        cell.textLabel.text = MTPCTX(@[@"CTX_NAME", @"CTX_SOURCE", @"CTX_ENABLED"][path.row]);
        if (path.row == 0) { cell.detailTextLabel.text = self.type.name; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        if (path.row == 1) cell.detailTextLabel.text = MTPCTX(@"CTX_CUSTOM_JS");
        if (path.row == 2) { UISwitch *toggle = [UISwitch new]; toggle.on = self.type.enabled; [toggle addTarget:self action:@selector(changeEnabled:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; cell.editingAccessoryView = toggle; }
    } else if (path.section == 1) {
        cell.textLabel.text = path.row == 0 ? self.type.source : MTPCTX(@"CTX_EDIT_SCRIPT");
        if (path.row == 0) { cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular]; cell.textLabel.numberOfLines = 7; cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor; }
        else cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = path.row == 0 ? (self.sample ?: @"test@metis.app") : (self.resultText ?: MTPCTX(@"CTX_TEST_HINT"));
        if (path.row == 0) { cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.detailTextLabel.text = MTPCTX(@"CTX_RUN"); }
        else cell.textLabel.textColor = UIColor.secondaryLabelColor;
    }
    cell.editingAccessoryType = cell.accessoryType;
    return cell;
}
- (void)changeEnabled:(UISwitch *)sender { self.type.enabled = sender.on; [self saveType]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 3) { if (path.row == self.type.actions.count) [self addAction]; return; }
    if (path.section == 0 && path.row == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTPCTX(@"CTX_NAME") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = self.type.name; }];
        [alert addAction:[UIAlertAction actionWithTitle:MTPCTX(@"SAVE") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { NSString *name = alert.textFields.firstObject.text; if (name.length) { self.type.name = [name substringToIndex:MIN(name.length,(NSUInteger)128)]; self.title = self.type.name; [self saveType]; } }]];
        [alert addAction:[UIAlertAction actionWithTitle:MTPCTX(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
    } else if (path.section == 1 && path.row == 1) {
        MTPContextScriptEditor *editor = [MTPContextScriptEditor new]; editor.source = self.type.source;
        __weak typeof(self) weakSelf = self;
        editor.completion = ^(NSString *source, NSDictionary *result) {
            MTPJavaScriptRuleController *owner = weakSelf; if (!owner) return;
            owner.type.source = source; BOOL valid = ![result[@"error"] length]; if (!valid) owner.type.enabled = NO;
            [owner saveType]; owner.resultText = valid ? nil : MTPCTX(result[@"error"]);
            if ([source containsString:@"fetch"] || [source containsString:@"UIPasteboard"] || [source containsString:@"NSURLSession"]) owner.resultText = MTPCTX(@"CTX_SANDBOX");
        };
        [self pushPage:editor];
    } else if (path.section == 2 && path.row == 0 && !self.running) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTPCTX(@"CTX_TEST") message:MTPCTX(@"CTX_TEST_HINT") preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = self.sample ?: @"test@metis.app"; field.autocorrectionType = UITextAutocorrectionTypeNo; }];
        [alert addAction:[UIAlertAction actionWithTitle:MTPCTX(@"CTX_RUN") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { self.sample = alert.textFields.firstObject.text; [self runTest]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:MTPCTX(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
    }
}
- (void)runTest {
    self.running = YES; self.resultText = MTPCTX(@"CTX_RUNNING"); [self.table reloadData];
    __weak typeof(self) weakSelf = self;
    [[MTContextClassifier sharedClassifier] testRule:self.typeID source:self.type.source text:self.sample completion:^(NSDictionary *result) {
        MTPJavaScriptRuleController *owner = weakSelf; if (!owner) return;
        owner.running = NO;
        if ([result[@"error"] length]) { owner.resultText = MTPCTX(result[@"error"]); [owner.table reloadData]; return; }
        MTContextGroupConfig *config = [MTContextGroupConfig configFromPreferences:[MTPrefsManager.sharedInstance readPrefs]];
        [[MTContextClassifier sharedClassifier] classifyText:owner.sample surface:owner.groupKey flags:@{} group:owner.groupKey config:config completion:^(NSDictionary *classification) {
            MTPJavaScriptRuleController *page = weakSelf; if (!page) return;
            MTContextSnapshot *snapshot = [MTContextSnapshot new]; snapshot.inputAvailable = YES; snapshot.inputLength = 1; snapshot.inputText = page.sample; snapshot.canUndo = YES;
            if ([page.groupKey isEqual:@"selection"]) { snapshot.selectionLength = page.sample.length; snapshot.selectionText = page.sample; }
            if ([page.groupKey isEqual:@"copy"]) { snapshot.clipboardAvailable = YES; snapshot.clipboardAge = 0; snapshot.clipboardText = page.sample; }
            if ([page.groupKey isEqual:@"paste"]) { snapshot.pastedLength = MAX((NSUInteger)1,page.sample.length); snapshot.pasteAge = 0; snapshot.pastedText = page.sample; }
            if ([page.groupKey isEqual:@"delete"]) { snapshot.deletedLength = 1; snapshot.deleteAge = 0.5; }
            snapshot.classification = @{page.groupKey:classification};
            MTContextDecision *decision = [MTContextGroupEngine decisionForSnapshot:snapshot config:config];
            NSString *winner = MTPCTX(@"CTX_NO_ACTIONS");
            for (MTContextType *type in [config typesForGroup:page.groupKey]) {
                NSString *reason = [NSString stringWithFormat:@"%@-%@", page.groupKey, type.identifier];
                if ([decision.reason isEqual:reason] || [decision.reason isEqual:[reason stringByAppendingString:@"-pending"]]) { winner = MTPCTXTypeName(type); break; }
            }
            page.resultText = [NSString stringWithFormat:MTPCTX(@"CTX_TEST_RESULT"), MTPCTX([result[@"matched"] boolValue] ? @"CTX_MATCHED" : @"CTX_NOT_MATCHED"), [result[@"ms"] doubleValue], winner, (unsigned long)decision.actions.count];
            [page.table reloadData];
        }];
    }];
}
@end
