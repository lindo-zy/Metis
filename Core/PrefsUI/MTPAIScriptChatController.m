#import "MTPAIScriptChatController.h"
#import "MTPAIScriptGenerator.h"
#import "MTPJavaScriptTestController.h"
#import "MTAIEngine.h"
#import "common.h"
#import <syslog.h>

static NSString *MTAIScriptLabel(NSString *key) {
    return NSLocalizedStringFromTableInBundle(key, nil, [NSBundle bundleWithPath:bundlePath], nil);
}

@interface MTPAIScriptChatController () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UILabel *inputHint;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *history;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *versions;
@property (nonatomic, strong) MTAIChatRequest *request;
@property (nonatomic, assign) NSUInteger requestID;
@property (nonatomic, assign) NSInteger selectedVersion;
@property (nonatomic, assign) BOOL generating;
@property (nonatomic, assign) BOOL refreshScheduled;
@property (nonatomic, copy) NSString *pendingRequirement;
@property (nonatomic, copy) NSString *streamedText;
@property (nonatomic, copy) NSString *requestError;
@end

@implementation MTPAIScriptChatController
- (UILabel *)label:(NSString *)text color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.text = text; label.textColor = color; label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    return label;
}
- (UIButton *)button:(NSString *)key action:(SEL)action tag:(NSInteger)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = [UIButtonConfiguration tintedButtonConfiguration];
    config.title = MTAIScriptLabel(key); config.baseForegroundColor = UIColor.systemIndigoColor;
    config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    button.configuration = config; button.tag = tag;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTAIScriptLabel(@"JS_AI_CHAT_TITLE");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.history = [NSMutableArray array]; self.versions = [NSMutableArray array];
    self.selectedVersion = NSNotFound;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:MTAIScriptLabel(@"JS_AI_CLEAR")
        style:UIBarButtonItemStylePlain target:self action:@selector(clearTapped)];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.dataSource = self; self.table.delegate = self;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.table.rowHeight = UITableViewAutomaticDimension; self.table.estimatedRowHeight = 160;
    [self.view addSubview:self.table];

    UIView *bar = [UIView new]; bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    [self.view addSubview:bar];
    self.input = [UITextView new]; self.input.translatesAutoresizingMaskIntoConstraints = NO;
    self.input.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; self.input.delegate = self;
    self.input.backgroundColor = UIColor.tertiarySystemFillColor; self.input.layer.cornerRadius = 16;
    self.input.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    self.input.autocorrectionType = UITextAutocorrectionTypeNo;
    self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.input.smartQuotesType = UITextSmartQuotesTypeNo; self.input.smartDashesType = UITextSmartDashesTypeNo;
    [bar addSubview:self.input];
    self.inputHint = [self label:MTAIScriptLabel(@"JS_AI_INPUT_HINT") color:UIColor.placeholderTextColor];
    self.inputHint.font = self.input.font; self.inputHint.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputHint.userInteractionEnabled = NO; [self.input addSubview:self.inputHint];
    self.sendButton = [self button:@"JS_AI_SEND" action:@selector(sendTapped) tag:0];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO; [bar addSubview:self.sendButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:bar.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [self.input.topAnchor constraintEqualToAnchor:bar.topAnchor constant:10],
        [self.input.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-10],
        [self.input.leadingAnchor constraintEqualToAnchor:bar.safeAreaLayoutGuide.leadingAnchor constant:12],
        [self.input.heightAnchor constraintEqualToConstant:76],
        [self.inputHint.topAnchor constraintEqualToAnchor:self.input.topAnchor constant:10],
        [self.inputHint.leadingAnchor constraintEqualToAnchor:self.input.leadingAnchor constant:15],
        [self.inputHint.trailingAnchor constraintEqualToAnchor:self.input.trailingAnchor constant:-12],
        [self.sendButton.leadingAnchor constraintEqualToAnchor:self.input.trailingAnchor constant:8],
        [self.sendButton.trailingAnchor constraintEqualToAnchor:bar.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:self.input.centerYAnchor],
        [self.sendButton.widthAnchor constraintEqualToConstant:64]
    ]];
    NSString *source = self.currentScript ?: @"";
    if (source.length <= 200 && ![source containsString:@"function"] && ![source containsString:@"main("] &&
        ![source containsString:@"{"] && ![source containsString:@"}"]) self.input.text = source;
    [self refreshControls];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.table reloadData]; [self refreshControls];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // A debug/settings push retains the conversation. Other exits cancel immediately.
    BOOL pushedChild = [self.navigationController.viewControllers containsObject:self] &&
        self.navigationController.topViewController != self && !self.navigationController.isBeingDismissed;
    if (!pushedChild) [self stopRequest];
}
- (void)dealloc { [_request cancel]; }
- (NSString *)configurationError {
    MTAIEngineInfo *engine = [MTAIEngine currentEngine];
    if (!engine || ![MTAIEngine apiKeyForEngine:engine].length) return MTAIScriptLabel(@"JS_AI_NO_KEY");
    if (![MTAIEngine selectedModelForEngine:engine].length) return MTAIScriptLabel(@"JS_AI_NO_MODEL");
    return nil;
}
- (void)refreshControls {
    self.input.editable = !self.generating;
    self.inputHint.text = MTAIScriptLabel(self.versions.count ? @"JS_AI_MODIFY_HINT" : @"JS_AI_INPUT_HINT");
    self.inputHint.hidden = self.input.text.length > 0;
    UIButtonConfiguration *config = self.sendButton.configuration;
    config.title = MTAIScriptLabel(self.generating ? @"JS_AI_STOP" : @"JS_AI_SEND");
    self.sendButton.configuration = config;
    self.sendButton.enabled = self.generating ||
        (!self.configurationError && [self.input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0);
}
- (void)textViewDidChange:(UITextView *)textView { [self refreshControls]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1 + self.versions.count + (self.pendingRequirement.length ? 1 : 0);
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : 2;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIStackView *stack = [UIStackView new]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-14],
        [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor]
    ]];
    if (path.section == 0) {
        MTAIEngineInfo *engine = [MTAIEngine currentEngine];
        [stack addArrangedSubview:[self label:[NSString stringWithFormat:MTAIScriptLabel(@"JS_AI_ENGINE_CARD"), engine.displayName ?: @"—"] color:UIColor.labelColor]];
        NSString *error = self.configurationError;
        UILabel *detail = [self label:error ?: [NSString stringWithFormat:MTAIScriptLabel(@"JS_AI_ENGINE_DETAIL"),
            [MTAIEngine selectedModelForEngine:engine] ?: @"—"] color:error ? UIColor.systemRedColor : UIColor.secondaryLabelColor];
        detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        [stack addArrangedSubview:detail]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", engine.displayName, detail.text];
        return cell;
    }
    NSInteger index = path.section - 1;
    BOOL pending = index == (NSInteger)self.versions.count;
    NSDictionary *version = pending ? nil : self.versions[index];
    if (path.row == 0) {
        [stack addArrangedSubview:[self label:pending ? self.pendingRequirement : version[@"requirement"] color:UIColor.labelColor]];
        return cell;
    }
    if (pending) {
        [stack addArrangedSubview:[self label:self.requestError ?: MTAIScriptLabel(@"JS_AI_GENERATING")
            color:self.requestError ? UIColor.systemRedColor : UIColor.systemIndigoColor]];
        if (self.requestError) [stack addArrangedSubview:[self button:@"JS_AI_RETRY" action:@selector(sendTapped) tag:0]];
        else if (self.streamedText.length) {
            UILabel *preview = [self label:[self.streamedText substringFromIndex:self.streamedText.length > 1200 ? self.streamedText.length - 1200 : 0]
                color:UIColor.secondaryLabelColor];
            preview.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            preview.numberOfLines = 8; [stack addArrangedSubview:preview];
        }
        return cell;
    }
    BOOL active = index == self.selectedVersion;
    UILabel *header = [self label:[NSString stringWithFormat:MTAIScriptLabel(active ? @"JS_AI_VERSION_ACTIVE" : @"JS_AI_VERSION"), (long)index + 1]
        color:active ? UIColor.systemIndigoColor : UIColor.secondaryLabelColor];
    header.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; [stack addArrangedSubview:header];
    NSString *error = version[@"error"];
    if (error.length) [stack addArrangedSubview:[self label:[NSString stringWithFormat:MTAIScriptLabel(@"JS_AI_PRECHECK_FAILED"), error] color:UIColor.systemRedColor]];
    NSString *script = version[@"script"];
    if (active) {
        UITextView *code = [UITextView new]; code.text = script; code.editable = NO;
        code.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
        code.textColor = UIColor.labelColor; code.backgroundColor = UIColor.clearColor;
        code.textContainerInset = UIEdgeInsetsZero;
        CGFloat width = MAX(160, tableView.bounds.size.width - 80);
        CGFloat height = MIN(360, MAX(100, [code sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height));
        [code.heightAnchor constraintEqualToConstant:height].active = YES; [stack addArrangedSubview:code];
    } else {
        UILabel *preview = [self label:script color:UIColor.secondaryLabelColor]; preview.numberOfLines = 3;
        preview.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; [stack addArrangedSubview:preview];
    }
    if (active) {
        UIStackView *actions = [UIStackView new]; actions.axis = UILayoutConstraintAxisVertical; actions.spacing = 8;
        UIButton *debug = [self button:@"JS_AI_DEBUG" action:@selector(debugTapped:) tag:index];
        UIButton *adopt = [self button:@"JS_AI_ADOPT" action:@selector(adoptTapped:) tag:index];
        debug.enabled = adopt.enabled = !self.generating && !error.length;
        [actions addArrangedSubview:debug]; [actions addArrangedSubview:adopt]; [stack addArrangedSubview:actions];
    } else {
        UIButton *rollback = [self button:@"JS_AI_ROLLBACK" action:@selector(rollbackTapped:) tag:index];
        rollback.enabled = !self.generating && !error.length; [stack addArrangedSubview:rollback];
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section != 0 || self.generating) return;
    // Core is also used by Clipboard preferences; load the keyboard bundle before class lookup.
    [[NSBundle bundleWithPath:bundlePath] load];
    Class settings = NSClassFromString(@"MTPAIChatController");
    if (settings && [settings isSubclassOfClass:UIViewController.class]) {
        [self.view endEditing:YES];
        [self.navigationController pushViewController:[settings new] animated:YES];
    }
}
- (void)reloadAtBottom:(BOOL)bottom {
    [self.table reloadData];
    if (bottom && self.table.numberOfSections > 1) {
        [self.table layoutIfNeeded];
        [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:self.table.numberOfSections - 1]
            atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    }
}
- (void)sendTapped {
    if (self.generating) { [self stopRequest]; return; }
    NSString *configurationError = self.configurationError;
    if (configurationError) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title message:configurationError preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:MTAIScriptLabel(@"ANSWER_OK") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    NSString *requirement = [self.input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!requirement.length) return;
    NSString *requestText = requirement;
    if (self.selectedVersion != NSNotFound) {
        requestText = [NSString stringWithFormat:@"【当前版本脚本：第 %ld 版】\n%@\n【本轮需求】\n%@",
            (long)self.selectedVersion + 1, self.versions[self.selectedVersion][@"script"], requirement];
    }
    NSArray *messages = [MTPAIScriptGenerator messagesForHistory:self.history requirement:requestText
        currentScript:self.history.count == 0 && self.selectedVersion == NSNotFound ? self.currentScript : nil];
    MTAIEngineInfo *engine = [MTAIEngine currentEngine];
    NSString *model = [MTAIEngine selectedModelForEngine:engine];
    self.pendingRequirement = requirement; self.streamedText = @""; self.requestError = nil;
    self.generating = YES; NSUInteger requestID = ++self.requestID;
    [self.view endEditing:YES]; [self refreshControls]; [self reloadAtBottom:YES];
    syslog(LOG_INFO, "[MetisKeyboard][AIScript] generation started");
    __weak typeof(self) weakSelf = self;
    self.request = [MTAIEngine sendChatWithMessages:messages engine:engine model:model onDelta:^(NSString *piece) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) owner = weakSelf;
            if (!owner || owner.requestID != requestID || !owner.generating) return;
            // Bound preview memory; final full text remains authoritative for precheck.
            NSString *combined = [owner.streamedText stringByAppendingString:piece];
            owner.streamedText = combined.length > 4096 ? [combined substringFromIndex:combined.length - 4096] : combined;
            if (owner.refreshScheduled) return;
            owner.refreshScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                typeof(self) view = weakSelf;
                if (!view || view.requestID != requestID) return;
                view.refreshScheduled = NO;
                if (view.generating) [view reloadAtBottom:YES];
            });
        });
    } onDone:^(NSString *fullText, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) owner = weakSelf;
            if (!owner || owner.requestID != requestID || !owner.generating) return;
            owner.request = nil; owner.generating = NO; owner.refreshScheduled = NO;
            if (error.code == NSURLErrorCancelled) { [owner stopRequest]; return; }
            if (error) {
                owner.requestError = error.localizedDescription;
                syslog(LOG_INFO, "[MetisKeyboard][AIScript] generation failed code=%ld", (long)error.code);
            } else {
                NSString *script = [MTPAIScriptGenerator scriptFromReply:fullText];
                NSString *check = script.length ? [MTPAIScriptGenerator precheckErrorForScript:script] : MTAIScriptLabel(@"JS_AI_EMPTY_RESULT");
                [owner.versions addObject:@{@"script": script, @"error": check ?: @"", @"requirement": requirement}];
                owner.selectedVersion = owner.versions.count - 1;
                [owner.history addObjectsFromArray:@[@{@"role": @"user", @"content": requirement}, @{@"role": @"assistant", @"content": script}]];
                if (owner.history.count > 20) [owner.history removeObjectsInRange:NSMakeRange(0, owner.history.count - 20)];
                owner.pendingRequirement = nil; owner.input.text = @"";
                syslog(LOG_INFO, "[MetisKeyboard][AIScript] generation finished precheck=%s", check ? "failed" : "passed");
            }
            [owner refreshControls]; [owner reloadAtBottom:YES];
        });
    }];
}
- (void)stopRequest {
    ++self.requestID; [self.request cancel]; self.request = nil;
    self.generating = NO; self.refreshScheduled = NO;
    self.pendingRequirement = nil; self.requestError = nil; self.streamedText = @"";
    [self refreshControls]; [self reloadAtBottom:NO];
}
- (NSString *)validatedScriptForButton:(UIButton *)button {
    if (self.generating || button.tag < 0 || button.tag >= (NSInteger)self.versions.count || button.tag != self.selectedVersion) return nil;
    NSString *script = self.versions[button.tag][@"script"];
    return [MTPAIScriptGenerator precheckErrorForScript:script] ? nil : script;
}
- (void)debugTapped:(UIButton *)button {
    NSString *script = [self validatedScriptForButton:button]; if (!script) return;
    [self.view endEditing:YES];
    MTPJavaScriptTestController *test = [MTPJavaScriptTestController new]; test.source = script;
    test.navigationItem.prompt = [NSString stringWithFormat:MTAIScriptLabel(@"JS_AI_DEBUG_TARGET"), (long)button.tag + 1];
    [self.navigationController pushViewController:test animated:YES];
}
- (void)adoptTapped:(UIButton *)button {
    NSString *script = [self validatedScriptForButton:button]; if (!script) return;
    if (self.completion) self.completion(script);
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)rollbackTapped:(UIButton *)button {
    if (self.generating || button.tag < 0 || button.tag >= (NSInteger)self.versions.count || [self.versions[button.tag][@"error"] length]) return;
    self.selectedVersion = button.tag; [self reloadAtBottom:NO];
    [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:button.tag + 1]
        atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
}
- (void)clearTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTAIScriptLabel(@"JS_AI_CLEAR")
        message:MTAIScriptLabel(@"JS_AI_CLEAR_CONFIRM") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:MTAIScriptLabel(@"ANSWER_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:MTAIScriptLabel(@"JS_AI_CLEAR") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        typeof(self) owner = weakSelf; if (!owner) return;
        [owner stopRequest]; [owner.history removeAllObjects]; [owner.versions removeAllObjects];
        owner.selectedVersion = NSNotFound; owner.input.text = @"";
        [owner refreshControls]; [owner reloadAtBottom:NO];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
