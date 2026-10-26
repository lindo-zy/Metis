#import "MTPJavaScriptTestController.h"
#import "MTJavaScriptEngine.h"
#import "MTPAIScriptProfile.h"
#import "common.h"

@interface MTPJavaScriptTestController () <UITextViewDelegate>
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UITextView *output;
@property (nonatomic, strong) UITextView *resultView;
@property (nonatomic, strong) UILabel *sampleHint;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) MTJavaScriptEngine *engine;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) NSTimeInterval startedAt;
@end

@implementation MTPJavaScriptTestController
- (NSString *)label:(NSString *)key {
    return NSLocalizedStringFromTableInBundle(key, nil, [NSBundle bundleWithPath:bundlePath], nil);
}

- (UILabel *)labelWithText:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = UIColor.secondaryLabelColor;
    return label;
}

- (UIView *)card:(UIView *)content {
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 10;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:11],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-11]
    ]];
    return card;
}

- (UITextView *)textViewWithHeight:(CGFloat)height editable:(BOOL)editable {
    UITextView *text = [UITextView new];
    text.editable = editable;
    text.backgroundColor = UIColor.clearColor;
    text.font = editable ? [UIFont preferredFontForTextStyle:UIFontTextStyleBody]
        : [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    text.textColor = UIColor.labelColor;
    text.textContainerInset = UIEdgeInsetsZero;
    text.textContainer.lineFragmentPadding = 0;
    text.autocorrectionType = UITextAutocorrectionTypeNo;
    text.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [text.heightAnchor constraintEqualToConstant:height].active = YES;
    return text;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self label:@"CTX_DEBUG_TITLE"];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scroll];
    self.stack = [UIStackView new];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 12;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [self.stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [self.stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:12],
        [self.stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-12]
    ]];

    UIStackView *header = [UIStackView new];
    header.axis = UILayoutConstraintAxisHorizontal;
    [header addArrangedSubview:[self labelWithText:[self label:@"CTX_DEBUG_SAMPLE"]]];
    [header addArrangedSubview:[UIView new]];
    UIButton *paste = [UIButton buttonWithType:UIButtonTypeSystem];
    [paste setTitle:[self label:@"CTX_DEBUG_PASTE"] forState:UIControlStateNormal];
    [paste addTarget:self action:@selector(fillFromClipboard) forControlEvents:UIControlEventTouchUpInside];
    [paste setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [paste setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [header addArrangedSubview:paste];
    [self.stack addArrangedSubview:header];
    self.input = [self textViewWithHeight:84 editable:YES];
    self.input.text = @"Hello MetisKeyboard";
    self.input.delegate = self;
    self.sampleHint = [self labelWithText:@""];
    self.sampleHint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    UIStackView *sample = [UIStackView new];
    sample.axis = UILayoutConstraintAxisVertical;
    sample.spacing = 4;
    [sample addArrangedSubview:self.input];
    [sample addArrangedSubview:self.sampleHint];
    [self.stack addArrangedSubview:[self card:sample]];
    [self updateSampleHint];
    [self.stack addArrangedSubview:[self labelWithText:[self label:@"JS_TEST_HINT"]]];

    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = [self label:@"JS_RUN"];
    config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    config.baseBackgroundColor = UIColor.systemBlueColor;
    self.runButton.configuration = config;
    [self.runButton addTarget:self action:@selector(run) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:self.runButton];
    UIStackView *metrics = [UIStackView new];
    metrics.axis = UILayoutConstraintAxisHorizontal;
    metrics.spacing = 7;
    metrics.distribution = UIStackViewDistributionFillEqually;
    self.stateLabel = [self labelWithText:@""];
    self.timeLabel = [self labelWithText:@""];
    self.sizeLabel = [self labelWithText:@""];
    for (UILabel *label in @[self.stateLabel, self.timeLabel, self.sizeLabel]) {
        [metrics addArrangedSubview:[self card:label]];
    }
    [self metric:self.stateLabel title:@"JS_DEBUG_STATUS" value:@"—"];
    [self metric:self.timeLabel title:@"CTX_DEBUG_MS" value:@"—"];
    [self metric:self.sizeLabel title:@"CTX_DEBUG_SIZE"
          value:[[MTPAIScriptProfile actionProfile] byteUsageTextForScript:self.source ?: @""]];
    [self.stack addArrangedSubview:metrics];
    [self.stack addArrangedSubview:[self labelWithText:[self label:@"JS_RESULT"]]];
    self.resultView = [self textViewWithHeight:128 editable:NO];
    self.resultView.text = @"—";
    [self.stack addArrangedSubview:[self card:self.resultView]];
    [self.stack addArrangedSubview:[self labelWithText:[self label:@"CTX_DEBUG_LOGS"]]];
    self.output = [self textViewWithHeight:112 editable:NO];
    self.output.text = [self label:@"CTX_DEBUG_NO_LOGS"];
    [self.stack addArrangedSubview:[self card:self.output]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemStop target:self action:@selector(stopTapped)];
    [self refreshControls];
}

- (void)metric:(UILabel *)label title:(NSString *)key value:(NSString *)value {
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:
        [NSString stringWithFormat:@"%@\n", [self label:key]] attributes:@{
            NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1],
            NSForegroundColorAttributeName: UIColor.secondaryLabelColor}];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:value attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: UIColor.labelColor}]];
    label.attributedText = text;
}

- (void)updateSampleHint {
    self.sampleHint.text = [NSString stringWithFormat:[self label:@"CTX_DEBUG_SAMPLE_HINT"],
        (unsigned long)MIN(self.input.text.length, (NSUInteger)2000)];
}
- (NSString *)boundedSample:(NSString *)text {
    if (text.length <= 2000) return text;
    // 截断边界不切开 emoji 或输入法组合字符。
    return [text substringToIndex:[text rangeOfComposedCharacterSequenceAtIndex:2000].location];
}
- (void)textViewDidChange:(UITextView *)textView {
    if (!textView.markedTextRange && textView.text.length > 2000) textView.text = [self boundedSample:textView.text];
    [self updateSampleHint];
}
- (void)fillFromClipboard {
    self.input.text = [self boundedSample:UIPasteboard.generalPasteboard.string ?: @""];
    [self updateSampleHint];
}
- (void)refreshControls {
    self.runButton.enabled = !self.running;
    self.navigationItem.rightBarButtonItem.enabled = self.engine != nil;
}
- (void)append:(NSString *)text {
    NSString *current = [self.output.text isEqual:[self label:@"CTX_DEBUG_NO_LOGS"]] ? @"" : self.output.text;
    NSString *combined = [current stringByAppendingFormat:@"%@\n", text];
    self.output.text = combined.length > 32768 ? [combined substringFromIndex:combined.length - 32768] : combined;
}
- (void)appendResult:(NSString *)text {
    NSString *combined = [self.resultView.text stringByAppendingFormat:@"%@\n", text];
    self.resultView.text = combined.length > 32768 ? [combined substringToIndex:32768] : combined;
}
- (void)updateTime {
    [self metric:self.timeLabel title:@"CTX_DEBUG_MS"
          value:[NSString stringWithFormat:@"%.1f ms", (NSProcessInfo.processInfo.systemUptime - self.startedAt) * 1000.0]];
}
- (void)stop {
    self.generation++;
    [self.engine cancel];
    self.engine = nil;
    self.running = NO;
    [self refreshControls];
}
- (void)stopTapped {
    if (self.running) [self updateTime];
    [self stop];
    [self metric:self.stateLabel title:@"JS_DEBUG_STATUS" value:[self label:@"JS_DEBUG_STOPPED"]];
}
- (void)finish {
    [self updateTime];
    [self metric:self.stateLabel title:@"JS_DEBUG_STATUS" value:[self label:@"JS_DEBUG_DONE"]];
    [self stop];
}
- (void)run {
    [self stop];
    [self.view endEditing:YES];
    self.output.text = [self label:@"CTX_DEBUG_NO_LOGS"];
    self.resultView.text = @"";
    self.startedAt = NSProcessInfo.processInfo.systemUptime;
    [self metric:self.timeLabel title:@"CTX_DEBUG_MS" value:@"—"];
    self.running = YES;
    [self metric:self.stateLabel title:@"JS_DEBUG_STATUS" value:[self label:@"CTX_DEBUG_RUNNING"]];
    self.engine = [MTJavaScriptEngine new];
    [self refreshControls];
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    self.engine.logHandler = ^(NSString *message) {
        typeof(self) owner = weakSelf;
        if (owner && owner.generation == generation) [owner append:message];
    };
    self.engine.actionHandler = ^(NSDictionary *action) {
        typeof(self) owner = weakSelf;
        if (!owner || owner.generation != generation) return;
        [owner appendResult:[NSString stringWithFormat:@"[%@]\n%@", action[@"type"], action[@"content"]]];
        // Direct navigation is terminal, but sandbox testing never opens the target.
        [owner finish];
    };
    self.engine.resultHandler = ^(NSArray *actions, NSError *error) {
        typeof(self) owner = weakSelf;
        if (!owner || owner.generation != generation) return;
        [owner updateTime];
        if (error) {
            [owner appendResult:error.localizedDescription];
            [owner metric:owner.stateLabel title:@"JS_DEBUG_STATUS" value:[owner label:@"JS_DEBUG_FAILED"]];
            [owner stop];
            return;
        }
        if (!actions.count) { [owner appendResult:@"null / undefined"]; [owner finish]; return; }
        if (actions.count == 1) { [owner preview:actions.firstObject]; return; }
        owner.running = NO;
        [owner refreshControls];
        [owner metric:owner.stateLabel title:@"JS_DEBUG_STATUS" value:[owner label:@"JS_DEBUG_CHOOSE"]];
        UIAlertController *menu = [UIAlertController alertControllerWithTitle:[owner label:@"JS_RESULT"]
            message:nil preferredStyle:UIAlertControllerStyleAlert];
        for (NSDictionary *action in actions) {
            [owner appendResult:[NSString stringWithFormat:@"[%@] %@", action[@"type"], action[@"title"]]];
            [menu addAction:[UIAlertAction actionWithTitle:[action[@"title"] length] ? action[@"title"] : @"∅"
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *item) {
                    typeof(self) current = weakSelf;
                    if (current && current.generation == generation) [current preview:action];
                }]];
        }
        [menu addAction:[UIAlertAction actionWithTitle:[owner label:@"ANSWER_CANCEL"] style:UIAlertActionStyleCancel
            handler:^(__unused UIAlertAction *item) {
                typeof(self) current = weakSelf;
                if (current && current.generation == generation) [current stopTapped];
            }]];
        [owner presentViewController:menu animated:YES completion:nil];
    };
    NSString *input = self.input.text ?: @"";
    self.input.text = [self boundedSample:input];
    [self updateSampleHint];
    [self.engine runSource:self.source input:self.input.text];
}
- (void)preview:(NSDictionary *)action {
    if ([action[@"type"] isEqual:@"function"]) {
        self.running = YES;
        self.startedAt = NSProcessInfo.processInfo.systemUptime;
        [self metric:self.stateLabel title:@"JS_DEBUG_STATUS" value:[self label:@"CTX_DEBUG_RUNNING"]];
        [self refreshControls];
        [self.engine callFunction:action[@"content"] arguments:action[@"args"]];
    } else {
        [self appendResult:[NSString stringWithFormat:@"[%@]\n%@", action[@"type"], action[@"content"]]];
        [self finish];
    }
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self stop]; }
- (void)dealloc { [_engine cancel]; }
@end
