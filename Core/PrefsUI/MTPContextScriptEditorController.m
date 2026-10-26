#import "MTPContextScriptEditorController.h"
#import "MTPAIScriptProfile.h"
#import "MTPAIScriptChatController.h"
#import "MTPContextScriptDebugController.h"
#import "MTPJavaScriptTestController.h"
#import "MTPJavaScriptCodeStyle.h"
#import "common.h"

static NSString *MTEditorLabel(NSString *key) {
    return NSLocalizedStringFromTableInBundle(key, nil, [NSBundle bundleWithPath:bundlePath], nil);
}

// 底栏只剩一个出口。用 UIControl 而不是 UIButton：命中区域要覆盖整行，
// 而标题必须贴左、chevron 必须贴右，按钮自带的标题布局帮不上忙。
@interface MTPScriptDebugEntryView : UIControl
@property(nonatomic, strong) UILabel *textLabel;
@end

@implementation MTPScriptDebugEntryView {
    UIView *_pressedVeil;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.secondarySystemBackgroundColor;

    UIView *separator = [UIView new];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = UIColor.separatorColor;

    UIView *tile = [UIView new];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    tile.userInteractionEnabled = NO;
    tile.backgroundColor = UIColor.systemIndigoColor;
    tile.layer.cornerRadius = 7;
    tile.layer.cornerCurve = kCACornerCurveContinuous;

    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:9 weight:UIImageSymbolWeightBlack]]];
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    glyph.userInteractionEnabled = NO;
    glyph.tintColor = UIColor.whiteColor;

    self.textLabel = [UILabel new];
    self.textLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.textLabel.textColor = UIColor.labelColor;
    self.textLabel.adjustsFontSizeToFitWidth = YES;
    self.textLabel.minimumScaleFactor = 0.8;

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.userInteractionEnabled = NO;
    chevron.tintColor = UIColor.tertiaryLabelColor;

    _pressedVeil = [UIView new];
    _pressedVeil.translatesAutoresizingMaskIntoConstraints = NO;
    _pressedVeil.userInteractionEnabled = NO;
    _pressedVeil.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.06];
    _pressedVeil.hidden = YES;

    for (UIView *view in @[separator, tile, glyph, self.textLabel, chevron, _pressedVeil]) {
        [self addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [separator.topAnchor constraintEqualToAnchor:self.topAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:1.0 / MAX(1.0, UIScreen.mainScreen.scale)],

        [tile.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [tile.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [tile.widthAnchor constraintEqualToConstant:24],
        [tile.heightAnchor constraintEqualToConstant:24],
        [glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],

        [self.textLabel.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:10],
        [self.textLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.textLabel.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-8],

        [chevron.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [chevron.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_pressedVeil.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_pressedVeil.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_pressedVeil.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_pressedVeil.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    _pressedVeil.hidden = !highlighted;
}

@end

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
    [root addArrangedSubview:[self buildDebugEntry]];

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

// 底栏原本是 Tab / 括号 / 引号 / 分号六个补字符按钮，能补字符却验不了脚本；
// 现在整行只做一件事：拿着当前草稿直接进沙盒调试台。
- (UIView *)buildDebugEntry {
    MTPScriptDebugEntryView *entry = [MTPScriptDebugEntryView new];
    NSString *title = MTEditorLabel(@"CTX_DEBUG_TITLE");
    entry.textLabel.text = title;
    entry.accessibilityLabel = title;
    [entry addTarget:self action:@selector(debugTapped) forControlEvents:UIControlEventTouchUpInside];
    [entry.heightAnchor constraintEqualToConstant:44].active = YES;
    return entry;
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

#pragma mark - Debug

// 两套运行时各有自己的沙箱，不能共用一个调试台：自定义动作走设置进程的
// MTJavaScriptEngine（可联网、可返回动作），底栏规则走键盘进程的 MTContextClassifier
// （纯判定、50 ms 限时）。送进调试台的是编辑器里的草稿，不经过「保存」。
- (void)debugTapped {
    [self.view endEditing:YES];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(rehighlight) object:nil];
    NSString *script = self.textView.text ?: @"";
    UIViewController *debug = nil;
    if (self.profile.runtime != MTPAIScriptRuntimeAction) {
        MTPContextScriptDebugController *controller = [MTPContextScriptDebugController new];
        controller.source = script;
        controller.profile = self.profile;
        controller.groupKey = self.groupKey;
        controller.typeID = self.typeID;
        debug = controller;
    } else {
        MTPJavaScriptTestController *controller = [MTPJavaScriptTestController new];
        controller.source = script;
        debug = controller;
    }
    [self.navigationController pushViewController:debug animated:YES];
}

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
