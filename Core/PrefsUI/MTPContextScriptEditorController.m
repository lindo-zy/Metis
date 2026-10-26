#import "MTPContextScriptEditorController.h"
#import "MTPAIScriptProfile.h"
#import "MTPAIScriptChatController.h"
#import "MTPJavaScriptCodeStyle.h"
#import "common.h"

static NSString *MTEditorLabel(NSString *key) {
    return NSLocalizedStringFromTableInBundle(key, nil, [NSBundle bundleWithPath:bundlePath], nil);
}

@interface MTPContextScriptEditorController () <UITextViewDelegate>
@property(nonatomic, strong) UITextView *textView;
@property(nonatomic, strong) UIView *gutter;
@property(nonatomic, strong) UILabel *lineNumbers;
@property(nonatomic, strong) UILabel *entryLabel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIView *errorBar;
@property(nonatomic, strong) UILabel *errorLabel;
@property(nonatomic, assign) BOOL highlighting;
@end

@implementation MTPContextScriptEditorController

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!self.profile) self.profile = [MTPAIScriptProfile contextProfile];
    if (!self.title.length) self.title = MTEditorLabel(@"CTX_EDIT_SCRIPT");
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:MTEditorLabel(@"SAVE")
        style:UIBarButtonItemStyleDone target:self action:@selector(doneTapped)];
    UIBarButtonItem *ai = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"sparkles"]
        style:UIBarButtonItemStylePlain target:self action:@selector(aiTapped)];
    ai.accessibilityLabel = MTEditorLabel(@"JS_AI_GENERATE");
    ai.tintColor = UIColor.systemIndigoColor;
    self.navigationItem.rightBarButtonItems = @[done, ai];

    UIStackView *root = [UIStackView new];
    root.axis = UILayoutConstraintAxisVertical;
    root.spacing = 0;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [root.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [root.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor]
    ]];

    [root addArrangedSubview:[self buildStatusBar]];
    [root addArrangedSubview:[self buildEditorArea]];
    [root addArrangedSubview:[self buildErrorBar]];
    [root addArrangedSubview:[self buildToolbar]];

    // 先给 textStorage 带上字体与段落样式：空脚本时没有属性，输入会退回系统默认字体。
    self.textView.font = [MTPJavaScriptCodeStyle codeFont];
    self.textView.attributedText = [MTPJavaScriptCodeStyle attributedStringForSource:self.source ?: @""];
    [self rehighlight];
}

#pragma mark - Pieces

- (UIView *)buildStatusBar {
    UIView *bar = [UIView new];
    bar.backgroundColor = UIColor.secondarySystemBackgroundColor;

    self.entryLabel = [UILabel new];
    self.entryLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.entryLabel.adjustsFontSizeToFitWidth = YES;
    self.entryLabel.minimumScaleFactor = 0.75;
    self.entryLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.entryLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
        forAxis:UILayoutConstraintAxisHorizontal];
    self.entryLabel.textColor = UIColor.secondaryLabelColor;
    self.entryLabel.text = self.profile.entrySignature;
    self.statusLabel = [UILabel new];
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.statusLabel.textAlignment = NSTextAlignmentRight;
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    for (UILabel *label in @[self.entryLabel, self.statusLabel]) {
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [bar addSubview:label];
    }
    [NSLayoutConstraint activateConstraints:@[
        [bar.heightAnchor constraintEqualToConstant:30],
        [self.entryLabel.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [self.entryLabel.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [self.statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.entryLabel.trailingAnchor constant:8]
    ]];
    return bar;
}

- (UIView *)buildEditorArea {
    UIView *container = [UIView new];
    [container setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [container setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [container.heightAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;

    self.gutter = [UIView new];
    self.gutter.translatesAutoresizingMaskIntoConstraints = NO;
    self.gutter.backgroundColor = UIColor.systemBackgroundColor;
    self.gutter.clipsToBounds = YES;
    [container addSubview:self.gutter];

    self.lineNumbers = [UILabel new];
    self.lineNumbers.numberOfLines = 0;
    self.lineNumbers.textAlignment = NSTextAlignmentRight;
    self.lineNumbers.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.lineNumbers.textColor = UIColor.tertiaryLabelColor;
    [self.gutter addSubview:self.lineNumbers];

    self.textView = [UITextView new];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.delegate = self;
    self.textView.backgroundColor = UIColor.systemBackgroundColor;
    self.textView.textContainerInset = UIEdgeInsetsMake(10, 6, 14, 10);
    self.textView.textContainer.lineFragmentPadding = 0;
    self.textView.alwaysBounceVertical = YES;
    self.textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.smartQuotesType = UITextSmartQuotesTypeNo;
    self.textView.smartDashesType = UITextSmartDashesTypeNo;
    self.textView.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
    self.textView.spellCheckingType = UITextSpellCheckingTypeNo;
    [container addSubview:self.textView];

    [NSLayoutConstraint activateConstraints:@[
        [self.gutter.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.gutter.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [self.gutter.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.gutter.widthAnchor constraintEqualToConstant:26],
        [self.textView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.gutter.trailingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor]
    ]];
    return container;
}

- (UIView *)buildErrorBar {
    self.errorBar = [UIView new];
    self.errorBar.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.10];
    self.errorBar.hidden = YES;

    self.errorLabel = [UILabel new];
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.errorLabel.textColor = UIColor.systemRedColor;
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.errorBar addSubview:self.errorLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.errorLabel.topAnchor constraintEqualToAnchor:self.errorBar.topAnchor constant:8],
        [self.errorLabel.bottomAnchor constraintEqualToAnchor:self.errorBar.bottomAnchor constant:-8],
        [self.errorLabel.leadingAnchor constraintEqualToAnchor:self.errorBar.leadingAnchor constant:12],
        [self.errorLabel.trailingAnchor constraintEqualToAnchor:self.errorBar.trailingAnchor constant:-12]
    ]];
    return self.errorBar;
}

- (UIButton *)toolButton:(NSString *)title action:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    button.backgroundColor = UIColor.secondarySystemFillColor;
    button.layer.cornerRadius = 6;
    [button.heightAnchor constraintEqualToConstant:32].active = YES;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIView *)buildToolbar {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 6;
    [row addArrangedSubview:[self toolButton:@"Tab" action:@selector(insertTab)]];
    [row addArrangedSubview:[self toolButton:@"{ }" action:@selector(insertBraces)]];
    [row addArrangedSubview:[self toolButton:@"( )" action:@selector(insertParens)]];
    [row addArrangedSubview:[self toolButton:@"\" \"" action:@selector(insertQuotes)]];
    [row addArrangedSubview:[self toolButton:@";" action:@selector(insertSemicolon)]];
    [row addArrangedSubview:[self toolButton:@"⌫" action:@selector(deleteBackward)]];

    UIView *bar = [UIView new];
    bar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [bar.heightAnchor constraintEqualToConstant:44],
        [row.topAnchor constraintEqualToAnchor:bar.topAnchor constant:6],
        [row.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-6],
        [row.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:8],
        [row.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-8]
    ]];
    return bar;
}

#pragma mark - Highlight

- (void)rehighlight {
    if (!self.textView) return;
    // 输入法组合期间改写 textStorage 会打断候选词，等组合结束后的 didChange 再重排。
    if (self.textView.markedTextRange) return;
    if (self.highlighting) return;
    self.highlighting = YES;
    NSMutableAttributedString *storage = self.textView.textStorage;
    [storage beginEditing];
    [MTPJavaScriptCodeStyle applyToStorage:storage];
    [storage endEditing];
    self.textView.typingAttributes = [MTPJavaScriptCodeStyle baseAttributes];
    self.highlighting = NO;
    [self updateLineNumbers];
    [self updateStatus];
}

- (void)scheduleHighlight {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(rehighlight) object:nil];
    [self performSelector:@selector(rehighlight) withObject:nil afterDelay:0.06];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutLineNumbers];
}

- (void)updateLineNumbers {
    if (!self.textView) return;
    NSString *source = self.textView.text ?: @"";
    NSUInteger lines = 1;
    for (NSUInteger i = 0; i < source.length; i++) {
        if ([source characterAtIndex:i] == '\n') lines++;
    }
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.minimumLineHeight = [MTPJavaScriptCodeStyle lineHeight];
    paragraph.maximumLineHeight = [MTPJavaScriptCodeStyle lineHeight];
    paragraph.alignment = NSTextAlignmentRight;
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger index = 1; index <= lines; index++) {
        [text appendFormat:@"%lu\n", (unsigned long)index];
    }
    self.lineNumbers.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: UIColor.tertiaryLabelColor,
        NSParagraphStyleAttributeName: paragraph}];
    [self layoutLineNumbers];
}

- (void)layoutLineNumbers {
    CGFloat width = MAX(0, CGRectGetWidth(self.gutter.bounds));
    if (width <= 0) return;
    CGSize size = [self.lineNumbers sizeThatFits:CGSizeMake(width - 6, CGFLOAT_MAX)];
    self.lineNumbers.frame = CGRectMake(0, self.textView.textContainerInset.top - self.textView.contentOffset.y,
                                        width - 6, size.height);
}

- (void)updateStatus {
    NSString *source = self.textView.text ?: @"";
    NSString *usage = [self.profile byteUsageTextForScript:source];
    self.entryLabel.text = [NSString stringWithFormat:@"%@ · %@", self.profile.entrySignature, usage];
    BOOL oversized = [self.profile isScriptOversized:source];
    self.entryLabel.textColor = oversized ? UIColor.systemRedColor : UIColor.secondaryLabelColor;

    NSString *error = [self.profile precheckErrorForScript:source];
    if (!error.length) {
        self.statusLabel.text = MTEditorLabel(@"CTX_SCRIPT_OK");
        self.statusLabel.textColor = UIColor.systemGreenColor;
        self.errorBar.hidden = YES;
    } else {
        self.statusLabel.text = MTEditorLabel(@"CTX_SCRIPT_FAIL");
        self.statusLabel.textColor = UIColor.systemRedColor;
        self.errorLabel.text = error;
        self.errorBar.hidden = NO;
    }
}

#pragma mark - UITextViewDelegate / UIScrollViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    [self scheduleHighlight];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.textView) return;
    [self layoutLineNumbers];
}

#pragma mark - Editing helpers

- (void)insertText:(NSString *)text caretOffset:(NSInteger)offset {
    UITextRange *range = self.textView.selectedTextRange;
    if (!range) return;
    [self.textView replaceRange:range withText:text];
    if (offset) {
        UITextPosition *caret = [self.textView positionFromPosition:self.textView.selectedTextRange.start offset:offset];
        if (caret) self.textView.selectedTextRange = [self.textView textRangeFromPosition:caret toPosition:caret];
    }
    [self textViewDidChange:self.textView];
}

- (void)insertTab { [self insertText:@"  " caretOffset:0]; }
- (void)insertBraces { [self insertText:@"{}" caretOffset:-1]; }
- (void)insertParens { [self insertText:@"()" caretOffset:-1]; }
- (void)insertQuotes { [self insertText:@"\"\"" caretOffset:-1]; }
- (void)insertSemicolon { [self insertText:@";" caretOffset:0]; }
- (void)deleteBackward { [self.textView deleteBackward]; [self textViewDidChange:self.textView]; }

#pragma mark - Navigation

- (void)doneTapped {
    [self.view endEditing:YES];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(rehighlight) object:nil];
    if (self.completion) self.completion(self.textView.text ?: @"");
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)aiTapped {
    [self.view endEditing:YES];
    MTPAIScriptChatController *chat = [MTPAIScriptChatController new];
    chat.profile = self.profile;
    chat.currentScript = self.textView.text ?: @"";
    chat.groupKey = self.groupKey;
    chat.typeID = self.typeID;
    __weak typeof(self) weakSelf = self;
    chat.completion = ^(NSString *script) {
        typeof(self) owner = weakSelf;
        if (!owner || ![script isKindOfClass:NSString.class]) return;
        owner.textView.text = script;
        [owner rehighlight];
    };
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

@end
