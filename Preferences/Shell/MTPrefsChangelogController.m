#import "MTPrefsChangelogController.h"
#import "MTLog.h"

static const CGFloat MTChangelogHeaderHeight = 58.0;
static const CGFloat MTChangelogHorizontalInset = 16.0;
static const CGFloat MTChangelogCloseSide = 32.0;
static const CGFloat MTChangelogBlockSpacing = 16.0;
static const CGFloat MTChangelogItemSpacing = 7.0;

// 语义色的可读变体：系统亮色 (#34C759 / #FF3B30 / #FF9500) 承载 15pt 正文对比度
// 不足，亮色模式改用深一档，深色模式回到系统亮色。
static UIColor *MTChangelogColor(NSUInteger red, NSUInteger green, NSUInteger blue,
                                 NSUInteger darkRed, NSUInteger darkGreen, NSUInteger darkBlue) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        BOOL dark = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
        return [UIColor colorWithRed:(dark ? darkRed : red) / 255.0
                               green:(dark ? darkGreen : green) / 255.0
                                blue:(dark ? darkBlue : blue) / 255.0
                               alpha:1.0];
    }];
}

static UIColor *MTChangelogAddedColor(void) {    // #248A3D / #30D158
    return MTChangelogColor(36, 138, 61, 48, 209, 88);
}

static UIColor *MTChangelogImprovedColor(void) { // #B25000 / #FF9F0A
    return MTChangelogColor(178, 80, 0, 255, 159, 10);
}

static UIColor *MTChangelogFixedColor(void) {    // #D70015 / #FF453A
    return MTChangelogColor(215, 0, 21, 255, 69, 58);
}

static UIColor *MTChangelogChangedColor(void) {  // 未知标签：次要文字色
    return [UIColor secondaryLabelColor];
}

static UIColor *MTChangelogBodyColor(void) {     // #3C3C43 / 深色下 0.92 白
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.92 green:0.92 blue:0.96 alpha:1.0]
            : [UIColor colorWithRed:0.235 green:0.235 blue:0.263 alpha:1.0];
    }];
}

static UIColor *MTChangelogTagColor(MTChangelogTag tag) {
    switch (tag) {
        case MTChangelogTagAdded: return MTChangelogAddedColor();
        case MTChangelogTagImproved: return MTChangelogImprovedColor();
        case MTChangelogTagFixed: return MTChangelogFixedColor();
        case MTChangelogTagChanged: return MTChangelogChangedColor();
    }
    return MTChangelogChangedColor();
}

static CGFloat MTHairlineWidth(void) {
    CGFloat scale = UIScreen.mainScreen.scale;
    return scale > 1.0 ? 1.0 / scale : 1.0;
}

@implementation MTPrefsChangelogController {
    NSArray<MTChangelogEntry *> *_entries;
    NSString *_sheetTitle;
    CGFloat _tagColumnWidth;
}

+ (instancetype)controllerWithEntries:(NSArray<MTChangelogEntry *> *)entries
                                title:(NSString *)title {
    return [[self alloc] initWithEntries:entries title:title];
}

- (instancetype)initWithEntries:(NSArray<MTChangelogEntry *> *)entries title:(NSString *)title {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _entries = [entries copy] ?: @[];
        _sheetTitle = [title copy] ?: @"";
        // iPhone 上 pageSheet 才会挂载 sheetPresentationController（入口方据此配置 detents）。
        self.modalPresentationStyle = UIModalPresentationPageSheet;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self mtBuildLayout];
    MTLogInfo(MTLogModulePrefs, @"state=changelog-presented entries=%lu",
              (unsigned long)_entries.count);
}

#pragma mark - Layout

- (void)mtBuildLayout {
    UIView *header = [self mtBuildHeader];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    scrollView.showsVerticalScrollIndicator = YES;
    scrollView.contentInset = UIEdgeInsetsMake(4.0, MTChangelogHorizontalInset,
                                               MTChangelogHorizontalInset + 10.0,
                                               MTChangelogHorizontalInset);
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:[self mtBuildBlocks]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    // 版本块之间固定 16pt；首块顶部由 scrollView 的 contentInset 提供。
    stack.spacing = MTChangelogBlockSpacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:MTChangelogHeaderHeight],

        [scrollView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor
                                          constant:-2.0 * MTChangelogHorizontalInset],
    ]];
}

- (UIView *)mtBuildHeader {
    UIView *header = [[UIView alloc] init];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *chevron = [UIImage systemImageNamed:@"chevron.down"];
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:14.0
                                                        weight:UIImageSymbolWeightSemibold];
    [closeButton setImage:[chevron imageByApplyingSymbolConfiguration:configuration]
                 forState:UIControlStateNormal];
    closeButton.tintColor = UIColor.labelColor;
    closeButton.backgroundColor = UIColor.tertiarySystemFillColor;
    closeButton.layer.cornerRadius = MTChangelogCloseSide / 2.0;
    closeButton.layer.cornerCurve = kCACornerCurveContinuous;
    closeButton.accessibilityLabel = @"关闭";
    [closeButton addTarget:self
                    action:@selector(mtDismiss:)
          forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeButton];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = _sheetTitle;
    titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline]
        scaledFontForFont:[UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold]];
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 1;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.8;
    titleLabel.accessibilityTraits |= UIAccessibilityTraitHeader;
    [header addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [closeButton.leadingAnchor constraintEqualToAnchor:header.leadingAnchor
                                                  constant:MTChangelogHorizontalInset],
        [closeButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [closeButton.widthAnchor constraintEqualToConstant:MTChangelogCloseSide],
        [closeButton.heightAnchor constraintEqualToConstant:MTChangelogCloseSide],

        [titleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:closeButton.trailingAnchor
                                                               constant:8.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor
                                                            constant:-MTChangelogHorizontalInset],
    ]];
    return header;
}

- (NSArray<UIView *> *)mtBuildBlocks {
    if (_entries.count == 0) {
        UILabel *empty = [[UILabel alloc] init];
        empty.text = @"暂无更新说明";
        empty.textAlignment = NSTextAlignmentCenter;
        empty.numberOfLines = 0;
        empty.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline]
            scaledFontForFont:[UIFont systemFontOfSize:15.0]];
        empty.adjustsFontForContentSizeCategory = YES;
        empty.textColor = UIColor.secondaryLabelColor;
        return @[empty];
    }

    _tagColumnWidth = [self mtTagColumnWidth];
    NSMutableArray<UIView *> *blocks = [NSMutableArray arrayWithCapacity:_entries.count];
    for (MTChangelogEntry *entry in _entries) {
        [blocks addObject:[self mtBuildBlockForEntry:entry]];
    }
    return blocks;
}

- (CGFloat)mtTagColumnWidth {
    UIFont *font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]];
    CGFloat width = 0.0;
    for (NSString *name in @[@"新增", @"优化", @"修复", @"调整"]) {
        CGFloat candidate = [name sizeWithAttributes:@{NSFontAttributeName: font}].width;
        width = MAX(width, candidate);
    }
    return ceil(width) + 8.0;
}

- (UIView *)mtBuildBlockForEntry:(MTChangelogEntry *)entry {
    UIStackView *block = [[UIStackView alloc] init];
    block.axis = UILayoutConstraintAxisVertical;
    block.alignment = UIStackViewAlignmentFill;
    block.spacing = 0.0;

    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = [NSString stringWithFormat:@"Metis %@", entry.version];
    versionLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:16.0 weight:UIFontWeightBold]];
    versionLabel.adjustsFontForContentSizeCategory = YES;
    versionLabel.textColor = MTChangelogAddedColor();
    versionLabel.numberOfLines = 1;

    UIView *rule = [[UIView alloc] init];
    rule.backgroundColor = UIColor.separatorColor;
    [rule.heightAnchor constraintEqualToConstant:MTHairlineWidth()].active = YES;

    [block addArrangedSubview:versionLabel];
    [block setCustomSpacing:8.0 afterView:versionLabel];
    [block addArrangedSubview:rule];
    [block setCustomSpacing:10.0 afterView:rule];

    for (MTChangelogItem *item in entry.items) {
        UIView *row = [self mtBuildRowForItem:item];
        [block addArrangedSubview:row];
        [block setCustomSpacing:MTChangelogItemSpacing afterView:row];
    }
    // 末条之后的间距由版本块间距负责，这里回退为 0 避免叠加。
    if (block.arrangedSubviews.count) {
        [block setCustomSpacing:0.0 afterView:block.arrangedSubviews.lastObject];
    }
    return block;
}

- (UIView *)mtBuildRowForItem:(MTChangelogItem *)item {
    UIFont *tagFont = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]];
    UIFont *bodyFont = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:15.0]];

    UILabel *tagLabel = [[UILabel alloc] init];
    tagLabel.text = item.tagDisplayName;
    tagLabel.font = tagFont;
    tagLabel.adjustsFontForContentSizeCategory = YES;
    tagLabel.textColor = MTChangelogTagColor(item.tag);
    tagLabel.numberOfLines = 1;
    [tagLabel setContentHuggingPriority:UILayoutPriorityRequired
                                forAxis:UILayoutConstraintAxisHorizontal];
    [tagLabel.widthAnchor constraintEqualToConstant:_tagColumnWidth].active = YES;

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 3.0;
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    UILabel *bodyLabel = [[UILabel alloc] init];
    bodyLabel.numberOfLines = 0;
    bodyLabel.font = bodyFont;
    bodyLabel.adjustsFontForContentSizeCategory = YES;
    bodyLabel.attributedText = [[NSAttributedString alloc] initWithString:item.text
                                                              attributes:@{
        NSFontAttributeName: bodyFont,
        NSForegroundColorAttributeName: MTChangelogBodyColor(),
        NSParagraphStyleAttributeName: paragraph,
    }];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[tagLabel, bodyLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentTop;
    row.spacing = 0.0;
    // 标签列宽已含 8pt 间距，正文列从标签右侧开始并自然悬挂缩进。
    row.isAccessibilityElement = YES;
    row.accessibilityLabel = [NSString stringWithFormat:@"%@，%@",
                              item.tagDisplayName, item.text];
    row.accessibilityTraits = UIAccessibilityTraitStaticText;
    return row;
}

#pragma mark - Actions

- (void)mtDismiss:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
