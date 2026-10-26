#import "MTPJavaScriptRuleController.h"
#import "MTPContextScriptEditorController.h"
#import "MTPContextScriptDebugController.h"
#import "MTPAIScriptChatController.h"
#import "MTPAIScriptProfile.h"
#import "MTPJavaScriptCodeStyle.h"
#import "MTAIEngine.h"
#import "MTPrefsManager.h"

@interface MTPJavaScriptRuleController ()
@property(nonatomic, copy) NSString *cachedSource;
@property(nonatomic, copy) NSString *cachedError;
@property(nonatomic, copy) NSString *cachedUsage;
@end

@implementation MTPJavaScriptRuleController

- (MTPAIScriptProfile *)profile { return [MTPAIScriptProfile contextProfile]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.cachedSource = nil; // 从编辑器或 AI 页返回后重新校验一次
    [self refreshValidation];
}

// 预检要建 JSContext，不能每次 cellForRow 都跑；按源码内容缓存一份结果。
- (void)refreshValidation {
    NSString *source = self.type.source ?: @"";
    if (self.cachedSource && [self.cachedSource isEqualToString:source]) return;
    self.cachedSource = source;
    self.cachedError = [self.profile precheckErrorForScript:source] ?: @"";
    self.cachedUsage = [self.profile byteUsageTextForScript:source];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : (section == 1 ? 3 : self.type.actions.count + 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return MTPCTX(@[@"CTX_RULE", @"CTX_SCRIPT", @"CTX_ACTIONS"][section]);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return MTPCTX(@"CTX_SCRIPT_FOOTER");
    if (section == 2) return [NSString stringWithFormat:MTPCTX(@"CTX_CAPACITY"), (unsigned long)self.slots];
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 2) return [self actionCellAtIndex:path.row];
    if (path.section == 1) {
        if (path.row == 0) return [self previewCell];
        if (path.row == 1) return [self aiCell];
        return [self debugCell];
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.text = MTPCTX(@[@"CTX_NAME", @"CTX_SOURCE", @"CTX_ENABLED"][path.row]);
    if (path.row == 0) {
        cell.detailTextLabel.text = self.type.name;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    if (path.row == 1) cell.detailTextLabel.text = MTPCTX(@"CTX_CUSTOM_JS");
    if (path.row == 2) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = self.type.enabled;
        [toggle addTarget:self action:@selector(changeEnabled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.editingAccessoryView = toggle;
    }
    cell.editingAccessoryType = cell.accessoryType;
    return cell;
}

- (UITableViewCell *)previewCell {
    [self refreshValidation];
    NSString *source = self.type.source ?: @"";
    NSArray<NSString *> *lines = [source componentsSeparatedByString:@"\n"];
    NSUInteger limit = 7;
    NSString *snippet = [[lines subarrayWithRange:NSMakeRange(0, MIN(limit, lines.count))]
        componentsJoinedByString:@"\n"];
    if (lines.count > limit) snippet = [snippet stringByAppendingString:@"\n…"];
    if (!snippet.length) snippet = MTPCTX(@"CTX_SCRIPT_EMPTY");

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.attributedText = [MTPJavaScriptCodeStyle attributedStringForSource:snippet];
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

    BOOL broken = [self.profile isScriptOversized:source] || self.cachedError.length;
    NSString *detail = [self.cachedUsage stringByAppendingFormat:@" · %@",
        MTPCTX(broken ? @"CTX_SCRIPT_FAIL" : @"CTX_EDIT_SCRIPT")];
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.detailTextLabel.textColor = broken ? UIColor.systemRedColor : UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)aiCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = MTPCTX(@"JS_AI_GENERATE");
    cell.textLabel.textColor = UIColor.systemIndigoColor;
    cell.imageView.image = [UIImage systemImageNamed:@"sparkles"];
    cell.imageView.tintColor = UIColor.systemIndigoColor;
    cell.detailTextLabel.numberOfLines = 0;
    MTAIEngineInfo *engine = [MTAIEngine currentEngine];
    NSString *model = [MTAIEngine selectedModelForEngine:engine];
    BOOL configured = [MTAIEngine apiKeyForEngine:engine].length && model.length;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@ · %@",
        MTPCTX(@"JS_AI_SUBTITLE_CONTEXT"), engine.displayName ?: @"—",
        model.length ? model : MTPCTX(@"JS_AI_UNCONFIGURED")];
    cell.detailTextLabel.textColor = configured ? UIColor.secondaryLabelColor : UIColor.systemRedColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)debugCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = MTPCTX(@"CTX_DEBUG_TITLE");
    cell.imageView.image = [UIImage systemImageNamed:@"play.circle"];
    cell.imageView.tintColor = UIColor.systemGreenColor;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.text = MTPCTX(@"CTX_DEBUG_SUBTITLE");
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)changeEnabled:(UISwitch *)sender {
    self.type.enabled = sender.on;
    [self saveType];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 2) {
        if (path.row == self.type.actions.count) [self addAction];
        return;
    }
    if (path.section == 0) {
        if (path.row == 0) [self renameRule];
        return;
    }
    if (path.row == 0) { [self openEditor]; return; }
    if (path.row == 1) { [self openAIGeneration]; return; }
    [self openDebugger];
}

- (void)renameRule {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTPCTX(@"CTX_NAME")
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = self.type.name; }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:MTPCTX(@"SAVE") style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        typeof(self) owner = weakSelf; if (!owner) return;
        NSString *name = alert.textFields.firstObject.text;
        if (!name.length) return;
        owner.type.name = [name substringToIndex:MIN(name.length, (NSUInteger)128)];
        owner.title = owner.type.name;
        [owner saveType];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:MTPCTX(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openEditor {
    MTPContextScriptEditorController *editor = [MTPContextScriptEditorController new];
    editor.source = self.type.source ?: self.profile.sampleTemplate;
    editor.groupKey = self.groupKey;
    editor.typeID = self.typeID;
    editor.title = MTPCTX(@"CTX_EDIT_SCRIPT");
    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSString *script) {
        typeof(self) owner = weakSelf; if (!owner) return;
        owner.type.source = script ?: @"";
        // 校验失败不再自动停用规则：保存原文，把问题留在编辑器里让人决定。
        [owner saveType];
        owner.cachedSource = nil;
        [owner.table reloadData];
    };
    [self pushPage:editor];
}

- (void)openAIGeneration {
    if ([self.navigationController.topViewController isKindOfClass:MTPAIScriptChatController.class]) return;
    MTPAIScriptChatController *chat = [MTPAIScriptChatController new];
    chat.profile = self.profile;
    chat.currentScript = self.type.source ?: @"";
    chat.groupKey = self.groupKey;
    chat.typeID = self.typeID;
    __weak typeof(self) weakSelf = self;
    chat.completion = ^(NSString *script) {
        typeof(self) owner = weakSelf; if (!owner || ![script isKindOfClass:NSString.class]) return;
        owner.type.source = script;
        [owner saveType];
        owner.cachedSource = nil;
        [owner.table reloadData];
    };
    [self pushPage:chat];
}

- (void)openDebugger {
    MTPContextScriptDebugController *debug = [MTPContextScriptDebugController new];
    debug.source = self.type.source ?: @"";
    debug.groupKey = self.groupKey;
    debug.typeID = self.typeID;
    debug.title = MTPCTX(@"CTX_DEBUG_TITLE");
    [self pushPage:debug];
}

@end
