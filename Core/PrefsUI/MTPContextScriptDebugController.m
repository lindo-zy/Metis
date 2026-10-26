#import "MTPContextScriptDebugController.h"
#import "MTContextClassifier.h"
#import "MTContextGroupEngine.h"
#import "MTContextGroupTypes.h"
#import "MTPrefsManager.h"
#import "MTPAIScriptProfile.h"
#import "common.h"
#import "../../Modules/Clipboard/Core/Actions/MTCaptureRuleEngine.h"

static NSString *MTDebugLabel(NSString *key) {
    return NSLocalizedStringFromTableInBundle(key, nil, [NSBundle bundleWithPath:bundlePath], nil);
}

static NSArray<NSString *> *MTDebugContextGroups(void) {
    return @[@"selection", @"copy", @"paste", @"typing", @"delete"];
}

@interface MTPContextScriptDebugController () <UITextViewDelegate>
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, strong) UITextView *sampleView;
@property(nonatomic, strong) UILabel *sampleHint;
@property(nonatomic, strong) UISegmentedControl *groupControl;
@property(nonatomic, strong) UIButton *runButton;
@property(nonatomic, strong) UILabel *verdictLabel;
@property(nonatomic, strong) UILabel *timeLabel;
@property(nonatomic, strong) UILabel *sizeLabel;
@property(nonatomic, strong) UITextView *logView;
@property(nonatomic, strong) UILabel *logCountLabel;
@property(nonatomic, strong) UILabel *effectiveLabel;
@property(nonatomic, strong) UILabel *effectiveHintLabel;
@property(nonatomic, strong) UIView *effectiveCard;
@property(nonatomic, assign) BOOL running;
@property(nonatomic, copy) NSString *selectedGroup;
@end

@implementation MTPContextScriptDebugController

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!self.profile) self.profile = [MTPAIScriptProfile contextProfile];
    if (!self.title.length) self.title = MTDebugLabel(@"CTX_DEBUG_TITLE");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.selectedGroup = self.groupKey.length ? self.groupKey : MTDebugContextGroups().firstObject;

    self.scroll = [UIScrollView new];
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.scroll.alwaysBounceVertical = YES;
    [self.view addSubview:self.scroll];
    self.stack = [UIStackView new];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 8;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor constant:12],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.leadingAnchor constant:12],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.trailingAnchor constant:-12]
    ]];

    [self buildSampleSection];
    [self buildContextSection];
    [self buildRunButton];
    [self buildMetrics];
    [self buildLogSection];
    [self buildEffectiveSection];
    [self refreshControls];
}

#pragma mark - Pieces

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = UIColor.secondaryLabelColor;
    return label;
}

- (UIView *)cardWithSubview:(UIView *)subview {
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 10;
    subview.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:subview];
    [NSLayoutConstraint activateConstraints:@[
        [subview.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
        [subview.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
        [subview.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:11],
        [subview.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-11]
    ]];
    return card;
}

- (void)buildSampleSection {
    UILabel *header = [self sectionLabel:MTDebugLabel(@"CTX_DEBUG_SAMPLE")];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *headerRow = [UIView new];
    UIButton *paste = [UIButton buttonWithType:UIButtonTypeSystem];
    [paste setTitle:MTDebugLabel(@"CTX_DEBUG_PASTE") forState:UIControlStateNormal];
    paste.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    [paste addTarget:self action:@selector(fillFromClipboard) forControlEvents:UIControlEventTouchUpInside];
    paste.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:header];
    [headerRow addSubview:paste];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor constant:4],
        [header.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],
        [paste.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor constant:-4],
        [paste.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],
        [paste.leadingAnchor constraintGreaterThanOrEqualToAnchor:header.trailingAnchor constant:8],
        [headerRow.heightAnchor constraintEqualToConstant:24]
    ]];
    [self.stack addArrangedSubview:headerRow];
    [self.stack setCustomSpacing:6 afterView:headerRow];

    self.sampleView = [UITextView new];
    self.sampleView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.sampleView.backgroundColor = UIColor.clearColor;
    self.sampleView.textContainerInset = UIEdgeInsetsZero;
    self.sampleView.textContainer.lineFragmentPadding = 0;
    self.sampleView.delegate = self;
    self.sampleView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.sampleView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.sampleView.text = self.sampleText;
    [self.sampleView.heightAnchor constraintEqualToConstant:72].active = YES;

    self.sampleHint = [UILabel new];
    self.sampleHint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.sampleHint.textColor = UIColor.tertiaryLabelColor;
    self.sampleHint.numberOfLines = 0;

    UIStackView *inner = [UIStackView new];
    inner.axis = UILayoutConstraintAxisVertical;
    inner.spacing = 4;
    [inner addArrangedSubview:self.sampleView];
    [inner addArrangedSubview:self.sampleHint];
    [self.stack addArrangedSubview:[self cardWithSubview:inner]];
    [self.stack setCustomSpacing:14 afterView:self.stack.arrangedSubviews.lastObject];
}

- (void)buildContextSection {
    UIView *headerRow = [UIView new];
    BOOL clipboard = self.profile.runtime == MTPAIScriptRuntimeClipboard;
    UILabel *header = [self sectionLabel:clipboard ? @"剪切板内容类型（meta.kind）" : MTDebugLabel(@"CTX_DEBUG_CONTEXT")];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:header];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor constant:4],
        [header.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],
        [headerRow.heightAnchor constraintEqualToConstant:24]
    ]];
    [self.stack addArrangedSubview:headerRow];
    [self.stack setCustomSpacing:6 afterView:headerRow];

    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSString *group in MTDebugContextGroups()) {
        [titles addObject:MTDebugLabel([@"CTX_DEBUG_GROUP_" stringByAppendingString:group.uppercaseString])];
    }
    if (clipboard) titles = [@[@"文本", @"图片"] mutableCopy];
    self.groupControl = [[UISegmentedControl alloc] initWithItems:titles];
    NSUInteger index = [MTDebugContextGroups() indexOfObject:self.selectedGroup];
    self.groupControl.selectedSegmentIndex = index == NSNotFound ? 0 : index;
    self.groupControl.apportionsSegmentWidthsByContent = YES;
    [self.groupControl addTarget:self action:@selector(groupChanged) forControlEvents:UIControlEventValueChanged];
    self.groupControl.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 10;
    [card addSubview:self.groupControl];
    [NSLayoutConstraint activateConstraints:@[
        [self.groupControl.topAnchor constraintEqualToAnchor:card.topAnchor constant:6],
        [self.groupControl.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-6],
        [self.groupControl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:6],
        [self.groupControl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-6]
    ]];
    [self.stack addArrangedSubview:card];
    [self.stack setCustomSpacing:14 afterView:card];
}

- (void)buildRunButton {
    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = MTDebugLabel(@"CTX_DEBUG_RUN");
    config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    config.baseBackgroundColor = UIColor.systemBlueColor;
    self.runButton.configuration = config;
    [self.runButton addTarget:self action:@selector(runTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:self.runButton];
    [self.stack setCustomSpacing:14 afterView:self.runButton];
}

- (NSAttributedString *)metricText:(NSString *)title value:(NSString *)value color:(UIColor *)color {
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.minimumLineHeight = 15;
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:
        [NSString stringWithFormat:@"%@\n", title] attributes:@{
            NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1],
            NSForegroundColorAttributeName: UIColor.secondaryLabelColor, NSParagraphStyleAttributeName: paragraph}];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:value ?: @"—" attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: paragraph}]];
    return text;
}

- (UILabel *)metricLabel {
    UILabel *label = [UILabel new];
    label.numberOfLines = 2;
    return label;
}

- (void)buildMetrics {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 7;
    UIColor *plain = UIColor.labelColor;
    self.verdictLabel = [self metricLabel];
    self.timeLabel = [self metricLabel];
    self.sizeLabel = [self metricLabel];
    self.verdictLabel.attributedText = [self metricText:MTDebugLabel(@"CTX_DEBUG_VERDICT") value:@"—" color:plain];
    self.timeLabel.attributedText = [self metricText:MTDebugLabel(@"CTX_DEBUG_MS") value:@"—" color:plain];
    self.sizeLabel.attributedText = [self metricText:MTDebugLabel(@"CTX_DEBUG_SIZE") value:@"—" color:plain];
    for (UILabel *label in @[self.verdictLabel, self.timeLabel, self.sizeLabel]) {
        UIView *card = [UIView new];
        card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        card.layer.cornerRadius = 9;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:card.topAnchor constant:8],
            [label.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8],
            [label.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:9],
            [label.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-9]
        ]];
        [row addArrangedSubview:card];
    }
    [self.stack addArrangedSubview:row];
    [self.stack setCustomSpacing:14 afterView:row];
}

- (void)buildLogSection {
    UIView *headerRow = [UIView new];
    UILabel *header = [self sectionLabel:MTDebugLabel(@"CTX_DEBUG_LOGS")];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    self.logCountLabel = [UILabel new];
    self.logCountLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.logCountLabel.textColor = UIColor.tertiaryLabelColor;
    self.logCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:header];
    [headerRow addSubview:self.logCountLabel];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor constant:4],
        [header.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],
        [self.logCountLabel.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor constant:-4],
        [self.logCountLabel.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],
        [headerRow.heightAnchor constraintEqualToConstant:24]
    ]];
    [self.stack addArrangedSubview:headerRow];
    [self.stack setCustomSpacing:6 afterView:headerRow];

    self.logView = [UITextView new];
    self.logView.editable = NO;
    self.logView.scrollEnabled = YES;
    self.logView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.logView.textColor = UIColor.labelColor;
    self.logView.backgroundColor = UIColor.clearColor;
    self.logView.textContainerInset = UIEdgeInsetsZero;
    self.logView.textContainer.lineFragmentPadding = 0;
    self.logView.text = MTDebugLabel(@"CTX_DEBUG_NO_LOGS");
    [self.logView.heightAnchor constraintEqualToConstant:96].active = YES;

    UIView *card = [self cardWithSubview:self.logView];
    [self.stack addArrangedSubview:card];
    [self.stack setCustomSpacing:14 afterView:card];
}

- (void)buildEffectiveSection {
    self.effectiveLabel = [UILabel new];
    self.effectiveLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.effectiveLabel.numberOfLines = 0;
    self.effectiveLabel.text = @"—";
    self.effectiveHintLabel = [UILabel new];
    self.effectiveHintLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.effectiveHintLabel.textColor = UIColor.secondaryLabelColor;
    self.effectiveHintLabel.numberOfLines = 0;
    self.effectiveHintLabel.text = MTDebugLabel(@"CTX_DEBUG_EFFECTIVE_HINT");

    UIStackView *inner = [UIStackView new];
    inner.axis = UILayoutConstraintAxisVertical;
    inner.spacing = 3;
    [inner addArrangedSubview:[self sectionLabel:MTDebugLabel(@"CTX_DEBUG_EFFECTIVE")]];
    [inner addArrangedSubview:self.effectiveLabel];
    [inner addArrangedSubview:self.effectiveHintLabel];
    self.effectiveCard = [self cardWithSubview:inner];
    self.effectiveCard.hidden = self.profile.runtime == MTPAIScriptRuntimeClipboard || !(self.groupKey.length && self.typeID.length);
    [self.stack addArrangedSubview:self.effectiveCard];
}

#pragma mark - Actions

- (void)fillFromClipboard {
    NSString *text = UIPasteboard.generalPasteboard.string;
    if (!text.length) return;
    self.sampleView.text = [text substringToIndex:MIN(text.length, (NSUInteger)2000)];
    [self refreshControls];
}

- (void)groupChanged {
    NSArray<NSString *> *groups = MTDebugContextGroups();
    NSInteger index = self.groupControl.selectedSegmentIndex;
    if (index >= 0 && index < (NSInteger)groups.count) self.selectedGroup = groups[index];
    [self.view endEditing:YES];
    [self runTapped];
}

- (void)runTapped {
    if (self.running) return;
    [self.view endEditing:YES];
    NSString *sample = [self.sampleView.text substringToIndex:MIN(self.sampleView.text.length, (NSUInteger)2000)];
    if (self.profile.runtime == MTPAIScriptRuntimeClipboard && self.groupControl.selectedSegmentIndex == 1) sample = @"";
    if (!sample.length && self.profile.runtime != MTPAIScriptRuntimeClipboard) {
        self.verdictLabel.attributedText = [self metricText:MTDebugLabel(@"CTX_DEBUG_VERDICT")
            value:MTDebugLabel(@"CTX_DEBUG_EMPTY_SAMPLE") color:UIColor.systemOrangeColor];
        return;
    }
    self.running = YES;
    [self refreshControls];
    self.verdictLabel.attributedText = [self metricText:MTDebugLabel(@"CTX_DEBUG_VERDICT")
        value:MTDebugLabel(@"CTX_RUNNING") color:UIColor.systemBlueColor];
    self.logView.text = @"";
    self.logCountLabel.text = @"";
    MTPAIScriptProfile *profile = self.profile;
    self.sizeLabel.attributedText = [self metricText:MTDebugLabel(@"CTX_DEBUG_SIZE")
        value:[profile byteUsageTextForScript:self.source] color:UIColor.labelColor];

    if (self.profile.runtime == MTPAIScriptRuntimeClipboard) {
        NSString *kind = self.groupControl.selectedSegmentIndex == 1 ? @"image" : @"text";
        __weak typeof(self) weakSelf = self;
        [[MTCaptureRuleEngine sharedEngine] testSource:self.source ?: @"" text:sample kind:kind
            completion:^(NSDictionary *result) {
                typeof(self) owner = weakSelf;
                if (!owner) return;
                owner.running = NO;
                [owner applyResult:result sample:sample];
                [owner refreshControls];
            }];
        return;
    }

    // 每次运行都用新的 identifier：调试失败的计数不能累积成「规则已停用」。
    NSString *identifier = [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    __weak typeof(self) weakSelf = self;
    [[MTContextClassifier sharedClassifier] testRule:identifier source:self.source text:sample
        captureLogs:YES completion:^(NSDictionary *result) {
        typeof(self) owner = weakSelf;
        if (!owner) return;
        owner.running = NO;
        [owner applyResult:result sample:sample];
        [owner refreshControls];
    }];
}

- (void)applyResult:(NSDictionary *)result sample:(NSString *)sample {
    NSString *error = [result[@"error"] isKindOfClass:NSString.class] ? result[@"error"] : @"";
    BOOL matched = [result[@"matched"] boolValue];
    if (error.length) {
        self.verdictLabel.attributedText = [self metricText:MTDebugLabel(@"CTX_DEBUG_VERDICT")
            value:(self.profile.runtime == MTPAIScriptRuntimeClipboard
                ? (@{@"CAPTURE_JS_TIMEOUT": @"超时（50 ms）", @"CAPTURE_JS_ERROR": @"脚本运行失败",
                     @"CAPTURE_JS_NO_MATCH": @"缺少 match 函数", @"CAPTURE_JS_UNAVAILABLE": @"沙盒不可用",
                     @"CAPTURE_JS_SOURCE_LIMIT": @"脚本为空或超过 8 KB"}[error] ?: error)
                : MTDebugLabel(error)) color:UIColor.systemRedColor];
    } else {
        self.verdictLabel.attributedText = [self metricText:MTDebugLabel(@"CTX_DEBUG_VERDICT")
            value:MTDebugLabel(matched ? @"CTX_DEBUG_MATCHED" : @"CTX_DEBUG_NOT_MATCHED")
            color:matched ? UIColor.systemGreenColor : UIColor.secondaryLabelColor];
    }
    self.timeLabel.attributedText = [self metricText:MTDebugLabel(@"CTX_DEBUG_MS")
        value:[NSString stringWithFormat:@"%.1f ms", [result[@"ms"] doubleValue]] color:UIColor.labelColor];

    NSArray *logs = [result[@"logs"] isKindOfClass:NSArray.class] ? result[@"logs"] : @[];
    if (logs.count) {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (id entry in logs) {
            if (![entry isKindOfClass:NSString.class]) continue;
            [lines addObject:[@"[log] " stringByAppendingString:entry]];
        }
        self.logView.text = [lines componentsJoinedByString:@"\n"];
        self.logCountLabel.text = [NSString stringWithFormat:MTDebugLabel(@"CTX_DEBUG_LOG_COUNT"), (unsigned long)lines.count];
    } else {
        self.logView.text = MTDebugLabel(@"CTX_DEBUG_NO_LOGS");
        self.logCountLabel.text = @"";
    }

    if (self.profile.runtime == MTPAIScriptRuntimeClipboard || !(self.groupKey.length && self.typeID.length)) return;
    [self resolveEffectiveForSample:sample error:error];
}

// 复用运行期的判定链路：分类 → 快照 → 决策。调试只看结果，不写缓存也不落盘。
- (void)resolveEffectiveForSample:(NSString *)sample error:(NSString *)error {
    MTContextGroupConfig *config = [MTContextGroupConfig configFromPreferences:[MTPrefsManager.sharedInstance readPrefs]];
    __weak typeof(self) weakSelf = self;
    NSString *group = self.groupKey;
    [[MTContextClassifier sharedClassifier] classifyText:sample surface:group flags:@{} group:group
        config:config completion:^(NSDictionary *classification) {
        typeof(self) owner = weakSelf;
        if (!owner) return;
        MTContextSnapshot *snapshot = [MTContextSnapshot new];
        snapshot.inputAvailable = YES;
        snapshot.inputLength = 1;
        snapshot.inputText = sample;
        snapshot.canUndo = YES;
        if ([owner.selectedGroup isEqual:@"selection"]) {
            snapshot.selectionLength = sample.length;
            snapshot.selectionText = sample;
        }
        if ([owner.selectedGroup isEqual:@"copy"]) {
            snapshot.clipboardAvailable = YES;
            snapshot.clipboardAge = 0;
            snapshot.clipboardText = sample;
        }
        if ([owner.selectedGroup isEqual:@"paste"]) {
            snapshot.pastedLength = MAX((NSUInteger)1, sample.length);
            snapshot.pasteAge = 0;
            snapshot.pastedText = sample;
        }
        if ([owner.selectedGroup isEqual:@"delete"]) {
            snapshot.deletedLength = 1;
            snapshot.deleteAge = 0.5;
        }
        snapshot.classification = @{group: classification ?: @{}};
        MTContextDecision *decision = [MTContextGroupEngine decisionForSnapshot:snapshot config:config];
        NSString *winner = MTDebugLabel(@"CTX_NO_ACTIONS");
        for (MTContextType *type in [config typesForGroup:group]) {
            NSString *reason = [NSString stringWithFormat:@"%@-%@", group, type.identifier];
            if ([decision.reason isEqual:reason] ||
                [decision.reason isEqual:[reason stringByAppendingString:@"-pending"]]) {
                winner = [type.kind isEqual:@"js"] ? type.name : MTDebugLabel([@"CTX_" stringByAppendingString:type.identifier.uppercaseString]);
                break;
            }
        }
        owner.effectiveLabel.text = [NSString stringWithFormat:MTDebugLabel(@"CTX_DEBUG_EFFECTIVE_VALUE"),
            winner, (unsigned long)decision.actions.count];
        owner.effectiveLabel.textColor = error.length ? UIColor.secondaryLabelColor : UIColor.labelColor;
    }];
}

- (void)refreshControls {
    self.runButton.enabled = !self.running;
    UIButtonConfiguration *config = self.runButton.configuration;
    config.title = MTDebugLabel(self.running ? @"CTX_DEBUG_RUNNING" : @"CTX_DEBUG_RUN");
    self.runButton.configuration = config;
    BOOL image = self.profile.runtime == MTPAIScriptRuntimeClipboard && self.groupControl.selectedSegmentIndex == 1;
    self.sampleView.editable = !self.running && !image;
    self.groupControl.enabled = !self.running;
    NSString *sample = self.sampleView.text ?: @"";
    self.sampleHint.text = [NSString stringWithFormat:MTDebugLabel(@"CTX_DEBUG_SAMPLE_HINT"),
        (unsigned long)MIN(sample.length, (NSUInteger)2000)];
    if (self.profile.runtime == MTPAIScriptRuntimeClipboard) {
        if (image) self.sampleHint.text = @"图片模式：meta.kind = image，text 为空；上方样例文本只用于文本模式。";
        self.sampleHint.text = [self.sampleHint.text stringByAppendingString:@"\n只测试匹配条件，不执行绑定动作，不写入配置。图片类型可用空文本测试。"];
    }
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    if (textView != self.sampleView) return;
    [self refreshControls];
}

@end
