#import <Preferences/PSViewController.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>
#import "../../Modules/Capture/Sources/Watermark/MTWatermarkRenderer.h"
#import "../../Modules/Capture/Sources/Editor/MTDeviceFrameViewController.h"
#import "../../Modules/Capture/Sources/Editor/MTDeviceFrameRenderer.h"
#import "../../Modules/Capture/Sources/Editor/MTDeviceFrameTemplateStore.h"

static UIColor *MTWatermarkAccent(void) { return [UIColor colorWithRed:1 green:0.78 blue:0.08 alpha:1]; }
static UIColor *MTWatermarkCard(void) { return [UIColor colorWithWhite:0.14 alpha:1]; }

@interface MTWatermarkSettingsController : PSViewController <PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) MTWatermarkConfiguration *style;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UIImageView *mark;
@property (nonatomic, strong) UIStackView *materialsStack;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISegmentedControl *previewMode;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) NSMutableArray<UISlider *> *sliders;
@property (nonatomic, strong) NSMutableArray<UILabel *> *values;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UILabel *libraryTitle;
@property (nonatomic, strong) UILabel *libraryEmpty;
@property (nonatomic, strong) UILabel *summary;
@property (nonatomic, strong) UIButton *adjustButton;
@property (nonatomic, strong) UIStackView *parameters;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIColor *previousNavigationTint;
@property (nonatomic, strong) NSMutableArray<UIButton *> *positionButtons;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIView *selection;
@property (nonatomic, strong) UILabel *previewEmpty;
@property (nonatomic, strong) NSLayoutConstraint *previewHeight;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSUInteger materialGeneration;
@property (nonatomic) BOOL importing;
@property (nonatomic) CGPoint dragOrigin;
@property (nonatomic, strong) dispatch_queue_t renderQueue;
@end

@implementation MTWatermarkSettingsController
- (NSArray *)specifiers { return @[]; }
- (UILabel *)label:(NSString *)text size:(CGFloat)size secondary:(BOOL)secondary {
    UILabel *label = [UILabel new]; label.text = text;
    label.font = [UIFont systemFontOfSize:size];
    label.textColor = secondary ? UIColor.secondaryLabelColor : UIColor.whiteColor;
    label.numberOfLines = 0;
    return label;
}
- (UIStackView *)column:(CGFloat)spacing {
    UIStackView *stack = [UIStackView new]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = spacing;
    return stack;
}
- (UIView *)cardWithContent:(UIView *)content {
    UIView *card = [UIView new]; card.backgroundColor = MTWatermarkCard(); card.layer.cornerRadius = 16;
    content.translatesAutoresizingMaskIntoConstraints = NO; [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12]]];
    return card;
}
- (UIStackView *)rowWithView:(UIView *)view control:(UIView *)control {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[view, control]];
    row.alignment = UIStackViewAlignmentCenter; row.spacing = 10;
    [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [control setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return row;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    if (action) [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)styleSegments:(UISegmentedControl *)control accent:(BOOL)accent {
    control.backgroundColor = [UIColor colorWithWhite:0.20 alpha:1];
    control.selectedSegmentTintColor = accent ? MTWatermarkAccent() : [UIColor colorWithWhite:0.32 alpha:1];
    [control setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor,
        NSFontAttributeName:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium]} forState:UIControlStateNormal];
    [control setTitleTextAttributes:@{NSForegroundColorAttributeName:accent ? UIColor.blackColor : MTWatermarkAccent(),
        NSFontAttributeName:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]} forState:UIControlStateSelected];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"水印设置"; self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.style = [MTWatermarkConfiguration rememberedConfiguration];
    self.renderQueue = dispatch_queue_create("com.lindo.metis.watermark.settings", DISPATCH_QUEUE_SERIAL);
    self.sliders = [NSMutableArray new]; self.values = [NSMutableArray new]; self.positionButtons = [NSMutableArray new];
    self.view = [UIView new]; self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    self.view.tintColor = MTWatermarkAccent();
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItem.tintColor = MTWatermarkAccent();
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new]; [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = self.view.backgroundColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName:UIColor.whiteColor};
    appearance.buttonAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName:MTWatermarkAccent()};
    self.navigationItem.standardAppearance = appearance; self.navigationItem.scrollEdgeAppearance = appearance;

    self.scroll = [UIScrollView new]; self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.alwaysBounceVertical = YES; self.scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self.view addSubview:self.scroll];
    UIStackView *stack = [self column:12]; self.contentStack = stack; stack.translatesAutoresizingMaskIntoConstraints = NO; [self.scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-12],
        [stack.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor constant:-32]]];

    UIStackView *settings = [self column:10];
    self.enabledSwitch = [UISwitch new]; self.enabledSwitch.on = self.style.enabled; self.enabledSwitch.onTintColor = MTWatermarkAccent();
    self.enabledSwitch.accessibilityLabel = @"启用截图水印";
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
    [settings addArrangedSubview:[self rowWithView:[self label:@"启用截图水印" size:16 secondary:NO] control:self.enabledSwitch]];
    UIView *separator = [UIView new]; separator.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    [separator.heightAnchor constraintEqualToConstant:0.5].active = YES; [settings addArrangedSubview:separator];
    [settings addArrangedSubview:[self label:@"应用范围" size:12 secondary:YES]];
    UISegmentedControl *scope = [[UISegmentedControl alloc] initWithItems:@[@"所有截图", @"普通截图", @"套壳截图"]];
    scope.selectedSegmentIndex = self.style.scope; [self styleSegments:scope accent:YES]; scope.accessibilityLabel = @"水印应用范围";
    [scope.heightAnchor constraintEqualToConstant:34].active = YES;
    [scope addTarget:self action:@selector(scopeChanged:) forControlEvents:UIControlEventValueChanged];
    [settings addArrangedSubview:scope]; [stack addArrangedSubview:[self cardWithContent:settings]];

    UIStackView *previewContent = [self column:8];
    self.previewMode = [[UISegmentedControl alloc] initWithItems:@[@"普通", @"套壳"]];
    self.previewMode.selectedSegmentIndex = self.style.scope == 2 ? 1 : 0;
    [self styleSegments:self.previewMode accent:NO]; self.previewMode.accessibilityLabel = @"预览类型";
    [self.previewMode.widthAnchor constraintEqualToConstant:112].active = YES;
    [self.previewMode addTarget:self action:@selector(refreshPreview) forControlEvents:UIControlEventValueChanged];
    [previewContent addArrangedSubview:[self rowWithView:[self label:@"实时预览" size:15 secondary:NO] control:self.previewMode]];
    self.preview = [UIImageView new]; self.preview.contentMode = UIViewContentModeScaleAspectFit;
    self.preview.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
    self.preview.layer.cornerRadius = 12; self.preview.clipsToBounds = YES; self.preview.userInteractionEnabled = YES;
    self.preview.accessibilityLabel = @"完整成图预览";
    self.previewHeight = [self.preview.heightAnchor constraintEqualToConstant:260]; self.previewHeight.active = YES;
    [previewContent addArrangedSubview:self.preview];
    self.mark = [UIImageView new]; self.mark.contentMode = UIViewContentModeScaleAspectFit;
    self.mark.isAccessibilityElement = YES; self.mark.accessibilityLabel = @"水印位置预览";
    [self.preview addSubview:self.mark];
    self.selection = [UIView new]; self.selection.userInteractionEnabled = NO;
    self.selection.layer.borderColor = MTWatermarkAccent().CGColor; self.selection.layer.borderWidth = 1;
    for (NSInteger i = 0; i < 4; i++) {
        UIView *handle = [UIView new]; handle.backgroundColor = MTWatermarkAccent(); [self.selection addSubview:handle];
    }
    [self.preview addSubview:self.selection];
    self.previewEmpty = [self label:@"" size:14 secondary:YES]; self.previewEmpty.textAlignment = NSTextAlignmentCenter;
    self.previewEmpty.translatesAutoresizingMaskIntoConstraints = NO; [self.preview addSubview:self.previewEmpty];
    [NSLayoutConstraint activateConstraints:@[
        [self.previewEmpty.centerYAnchor constraintEqualToAnchor:self.preview.centerYAnchor],
        [self.previewEmpty.leadingAnchor constraintEqualToAnchor:self.preview.leadingAnchor constant:16],
        [self.previewEmpty.trailingAnchor constraintEqualToAnchor:self.preview.trailingAnchor constant:-16]]];
    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    drag.delegate = self; [self.preview addGestureRecognizer:drag];
    [self.scroll.panGestureRecognizer requireGestureRecognizerToFail:drag];
    self.status = [self label:@"" size:11 secondary:YES]; self.status.textAlignment = NSTextAlignmentCenter;
    [previewContent addArrangedSubview:self.status]; [stack addArrangedSubview:[self cardWithContent:previewContent]];

    UIStackView *library = [self column:8];
    self.libraryTitle = [self label:@"我的素材" size:17 secondary:NO]; self.libraryTitle.font = [UIFont boldSystemFontOfSize:17];
    self.importButton = [self button:@"导入素材" action:NULL];
    UIButtonConfiguration *importStyle = [UIButtonConfiguration filledButtonConfiguration];
    importStyle.title = @"导入素材"; importStyle.image = [UIImage systemImageNamed:@"photo"]; importStyle.imagePadding = 6;
    importStyle.baseBackgroundColor = MTWatermarkAccent(); importStyle.baseForegroundColor = UIColor.blackColor;
    importStyle.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    importStyle.contentInsets = NSDirectionalEdgeInsetsMake(6, 10, 6, 10); self.importButton.configuration = importStyle;
    __weak typeof(self) weakSelf = self;
    self.importButton.menu = [UIMenu menuWithChildren:@[
        [UIAction actionWithTitle:@"从相册导入" image:[UIImage systemImageNamed:@"photo"] identifier:nil handler:^(UIAction *action) { [weakSelf importPhoto]; }],
        [UIAction actionWithTitle:@"从文件导入" image:[UIImage systemImageNamed:@"doc"] identifier:nil handler:^(UIAction *action) { [weakSelf importFile]; }]]];
    self.importButton.showsMenuAsPrimaryAction = YES;
    [library addArrangedSubview:[self rowWithView:self.libraryTitle control:self.importButton]];
    UIScrollView *materials = [UIScrollView new]; materials.showsHorizontalScrollIndicator = NO;
    [materials.heightAnchor constraintEqualToConstant:90].active = YES;
    self.materialsStack = [UIStackView new]; self.materialsStack.spacing = 10;
    self.materialsStack.translatesAutoresizingMaskIntoConstraints = NO; [materials addSubview:self.materialsStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.materialsStack.leadingAnchor constraintEqualToAnchor:materials.contentLayoutGuide.leadingAnchor],
        [self.materialsStack.trailingAnchor constraintEqualToAnchor:materials.contentLayoutGuide.trailingAnchor],
        [self.materialsStack.topAnchor constraintEqualToAnchor:materials.contentLayoutGuide.topAnchor],
        [self.materialsStack.bottomAnchor constraintEqualToAnchor:materials.contentLayoutGuide.bottomAnchor],
        [self.materialsStack.heightAnchor constraintEqualToAnchor:materials.frameLayoutGuide.heightAnchor]]];
    self.libraryEmpty = [self label:@"导入第一份水印素材\n支持相册图片与文件" size:13 secondary:YES];
    self.libraryEmpty.textAlignment = NSTextAlignmentCenter; self.libraryEmpty.translatesAutoresizingMaskIntoConstraints = NO;
    [materials addSubview:self.libraryEmpty];
    [NSLayoutConstraint activateConstraints:@[
        [self.libraryEmpty.centerXAnchor constraintEqualToAnchor:materials.frameLayoutGuide.centerXAnchor],
        [self.libraryEmpty.centerYAnchor constraintEqualToAnchor:materials.frameLayoutGuide.centerYAnchor],
        [self.libraryEmpty.widthAnchor constraintEqualToAnchor:materials.frameLayoutGuide.widthAnchor]]];
    [library addArrangedSubview:materials]; [library addArrangedSubview:[self label:@"支持透明 PNG · 长按可删除" size:11 secondary:YES]];
    [stack addArrangedSubview:[self cardWithContent:library]];

    UIStackView *summaryText = [self column:4];
    [summaryText addArrangedSubview:[self label:@"位置与样式" size:16 secondary:NO]];
    self.summary = [self label:@"" size:11 secondary:YES]; [summaryText addArrangedSubview:self.summary];
    self.adjustButton = [self button:@"调整  ›" action:@selector(toggleParameters)];
    [stack addArrangedSubview:[self cardWithContent:[self rowWithView:summaryText control:self.adjustButton]]];
    UIStackView *parameters = [self column:12];
    UILabel *parameterTitle = [self label:@"位置与样式" size:17 secondary:NO]; parameterTitle.font = [UIFont boldSystemFontOfSize:17];
    [parameters addArrangedSubview:[self rowWithView:parameterTitle control:[self button:@"重置" action:@selector(resetParameters)]]];
    [parameters addArrangedSubview:[self label:@"拖动预览或使用下方参数精确调整" size:12 secondary:YES]];
    UIStackView *positions = [self column:6];
    NSArray *names = @[@"左上", @"上中", @"右上", @"左中", @"居中", @"右中", @"左下", @"下中", @"右下"];
    NSArray *icons = @[@"arrow.up.left", @"arrow.up", @"arrow.up.right", @"arrow.left", @"dot.square", @"arrow.right", @"arrow.down.left", @"arrow.down", @"arrow.down.right"];
    for (NSInteger row = 0; row < 3; row++) {
        UIStackView *buttons = [UIStackView new]; buttons.distribution = UIStackViewDistributionFillEqually; buttons.spacing = 6;
        for (NSInteger column = 0; column < 3; column++) {
            NSInteger index = row * 3 + column;
            UIButton *button = [self button:names[index] action:@selector(positionTapped:)]; button.tag = index;
            UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
            configuration.title = names[index]; configuration.image = [UIImage systemImageNamed:icons[index]];
            configuration.imagePlacement = NSDirectionalRectEdgeTop; configuration.imagePadding = 4;
            configuration.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:12];
            configuration.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *incoming) {
                NSMutableDictionary *attributes = incoming.mutableCopy; attributes[NSFontAttributeName] = [UIFont systemFontOfSize:12]; return attributes;
            };
            button.configuration = configuration; button.layer.cornerRadius = 8;
            [button.heightAnchor constraintEqualToConstant:58].active = YES;
            [buttons addArrangedSubview:button]; [self.positionButtons addObject:button];
        }
        [positions addArrangedSubview:buttons];
    }
    [parameters addArrangedSubview:positions];
    NSArray *titles = @[@"横向位置", @"纵向位置", @"水印大小", @"不透明度"];
    for (NSInteger index = 0; index < 4; index++) {
        UILabel *title = [self label:titles[index] size:14 secondary:NO];
        [title.widthAnchor constraintEqualToConstant:64].active = YES;
        UILabel *value = [self label:@"" size:13 secondary:NO]; value.textAlignment = NSTextAlignmentRight;
        value.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        [value.widthAnchor constraintEqualToConstant:40].active = YES; [self.values addObject:value];
        UISlider *slider = [UISlider new]; slider.minimumValue = index < 2 ? 0 : 0.05; slider.maximumValue = 1;
        slider.minimumTrackTintColor = MTWatermarkAccent(); slider.maximumTrackTintColor = [UIColor colorWithWhite:0.30 alpha:1];
        slider.tag = index; slider.accessibilityLabel = titles[index];
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [self.sliders addObject:slider];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[title, slider, value]];
        row.spacing = 8; row.alignment = UIStackViewAlignmentCenter;
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES; [parameters addArrangedSubview:row];
    }
    self.parameters = [self column:12];
    [self.parameters addArrangedSubview:[self cardWithContent:parameters]];
    UIStackView *help = [self column:8]; [help addArrangedSubview:[self label:@"使用说明" size:16 secondary:NO]];
    [help addArrangedSubview:[self label:@"支持从相册或文件导入透明 PNG\n套壳水印叠加在完整成图上，可覆盖机壳与背景\n长截图不添加水印\n大小按成图短边计算，素材最长边保存为 2048 像素" size:12 secondary:YES]];
    [self.parameters addArrangedSubview:[self cardWithContent:help]];
    UILabel *footer = [self label:@"点击右上角保存后生效" size:11 secondary:YES]; footer.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:footer];
    [self refreshControls]; [self reloadMaterials]; [self refreshPreview];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.previousNavigationTint = self.navigationController.navigationBar.tintColor;
    self.navigationController.navigationBar.tintColor = MTWatermarkAccent();
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.navigationBar.tintColor = self.previousNavigationTint;
}
- (void)toggleParameters {
    BOOL expanded = self.parameters.superview != nil;
    if (expanded) {
        [self.contentStack removeArrangedSubview:self.parameters]; [self.parameters removeFromSuperview];
    } else {
        [self.contentStack insertArrangedSubview:self.parameters atIndex:self.contentStack.arrangedSubviews.count - 1];
    }
    [self.adjustButton setTitle:expanded ? @"调整  ›" : @"收起  ⌃" forState:UIControlStateNormal];
    self.adjustButton.accessibilityValue = expanded ? @"已收起" : @"已展开";
    if (!expanded) {
        [self.view layoutIfNeeded];
        CGRect rect = [self.parameters convertRect:self.parameters.bounds toView:self.scroll];
        rect.size.height = MIN(rect.size.height, self.scroll.bounds.size.height - 12);
        [self.scroll scrollRectToVisible:rect animated:YES];
    }
}
- (void)resetParameters {
    MTWatermarkConfiguration *defaults = [MTWatermarkConfiguration new];
    self.style.x = defaults.x; self.style.y = defaults.y; self.style.size = defaults.size; self.style.opacity = defaults.opacity;
    [self refreshControls];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Keep a useful preview on small phones and in landscape without making the page excessively tall.
    CGFloat height = MIN(280, MAX(180, self.view.safeAreaLayoutGuide.layoutFrame.size.height * 0.36));
    if (fabs(self.previewHeight.constant - height) > 0.5) self.previewHeight.constant = height;
    [self layoutMark];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (self.mark.hidden || !self.mark.image) return NO;
    CGPoint point = [gestureRecognizer locationInView:self.preview];
    CGPoint translation = [(UIPanGestureRecognizer *)gestureRecognizer translationInView:self.preview];
    CGPoint origin = CGPointMake(point.x - translation.x, point.y - translation.y);
    return CGRectContainsPoint(CGRectInset(self.mark.frame, -22, -22), origin);
}
- (CGRect)imageRect {
    CGSize size = self.preview.image.size, bounds = self.preview.bounds.size;
    if (size.width <= 0 || size.height <= 0) return CGRectZero;
    CGFloat scale = MIN(bounds.width / size.width, bounds.height / size.height);
    return CGRectMake((bounds.width - size.width * scale) / 2, (bounds.height - size.height * scale) / 2, size.width * scale, size.height * scale);
}
- (void)layoutMark {
    CGRect imageRect = [self imageRect];
    CGRect rect = [self.style rectForCanvas:imageRect.size material:self.mark.image.size];
    self.mark.frame = CGRectOffset(rect, imageRect.origin.x, imageRect.origin.y);
    self.mark.alpha = self.style.opacity;
    self.mark.hidden = !self.mark.image || CGRectIsEmpty(imageRect) || CGRectIsEmpty(rect) ||
        ![self.style appliesToFramedImage:self.previewMode.selectedSegmentIndex == 1];
    self.selection.frame = self.mark.frame; self.selection.hidden = self.mark.hidden;
    for (NSUInteger i = 0; i < self.selection.subviews.count; i++) {
        self.selection.subviews[i].frame = CGRectMake((i % 2) ? rect.size.width - 3 : -3,
            (i / 2) ? rect.size.height - 3 : -3, 6, 6);
    }
}
- (void)refreshControls {
    double values[] = {self.style.x, self.style.y, self.style.size, self.style.opacity};
    for (NSInteger index = 0; index < 4; index++) {
        self.sliders[index].value = values[index];
        self.values[index].text = [NSString stringWithFormat:@"%.0f%%", values[index] * 100];
    }
    self.navigationItem.rightBarButtonItem.title = @"保存";
    self.importButton.enabled = !self.importing;
    NSArray *names = @[@"左上", @"上中", @"右上", @"左中", @"居中", @"右中", @"左下", @"下中", @"右下"];
    NSString *position = @"自定义位置";
    for (UIButton *button in self.positionButtons) {
        BOOL selected = fabs(self.style.x - (0.05 + (button.tag % 3) * 0.45)) < 0.005 &&
            fabs(self.style.y - (0.05 + (button.tag / 3) * 0.45)) < 0.005;
        button.selected = selected; button.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
        button.layer.borderWidth = selected ? 2 : 0; button.layer.borderColor = MTWatermarkAccent().CGColor;
        UIButtonConfiguration *configuration = button.configuration;
        configuration.baseForegroundColor = selected ? MTWatermarkAccent() : UIColor.lightGrayColor;
        button.configuration = configuration;
        button.accessibilityValue = selected ? @"已选中" : @"未选中";
        if (selected) position = names[button.tag];
    }
    self.summary.text = [NSString stringWithFormat:@"%@ · 大小 %.0f%% · 不透明度 %.0f%%", position, self.style.size * 100, self.style.opacity * 100];
    if (!self.importing && self.preview.image) {
        self.status.text = !self.mark.image ? @"请导入并选择水印素材" : (!self.style.enabled ? @"启用截图水印后可预览效果" :
            (![self.style appliesToFramedImage:self.previewMode.selectedSegmentIndex == 1] ? @"当前预览类型不在应用范围内" : @"拖动水印可调整位置"));
    }
    [self layoutMark];
}
- (void)enabledChanged:(UISwitch *)sender { self.style.enabled = sender.on; [self refreshControls]; }
- (void)scopeChanged:(UISegmentedControl *)sender { self.style.scope = sender.selectedSegmentIndex; [self refreshControls]; }
- (void)sliderChanged:(UISlider *)sender {
    switch (sender.tag) {
        case 0: self.style.x = sender.value; break;
        case 1: self.style.y = sender.value; break;
        case 2: self.style.size = sender.value; break;
        case 3: self.style.opacity = sender.value; break;
    }
    [self refreshControls];
}
- (void)positionTapped:(UIButton *)sender {
    self.style.x = 0.05 + (sender.tag % 3) * 0.45;
    self.style.y = 0.05 + (sender.tag / 3) * 0.45;
    [self refreshControls];
}
- (void)drag:(UIPanGestureRecognizer *)gesture {
    if (self.mark.hidden || !self.mark.image) return;
    if (gesture.state == UIGestureRecognizerStateBegan) self.dragOrigin = CGPointMake(self.style.x, self.style.y);
    CGPoint translation = [gesture translationInView:self.preview];
    CGRect imageRect = [self imageRect];
    CGFloat width = imageRect.size.width - self.mark.bounds.size.width;
    CGFloat height = imageRect.size.height - self.mark.bounds.size.height;
    self.style.x = MAX(0, MIN(1, self.dragOrigin.x + translation.x / MAX(1, width)));
    self.style.y = MAX(0, MIN(1, self.dragOrigin.y + translation.y / MAX(1, height)));
    [self refreshControls];
}
- (void)refreshPreview {
    NSUInteger generation = ++self.generation;
    self.mark.image = nil; [self layoutMark];
    self.status.text = @"正在生成预览…";
    BOOL framed = self.previewMode.selectedSegmentIndex == 1;
    MTDeviceFrameConfiguration *frameStyle = [MTDeviceFrameConfiguration rememberedConfiguration];
    UIImage *example = [MTDeviceFrameViewController exampleImage];
    NSString *identifier = self.style.materialIdentifier;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.renderQueue, ^{ @autoreleasepool {
        UIImage *base = example;
        if (framed) {
            MTDeviceFrameTemplate *frame = [MTDeviceFrameTemplateStore resolveTemplateForConfiguration:frameStyle templates:MTDeviceFrameTemplateStore.templates];
            base = frame ? [MTDeviceFrameRenderer renderImage:example configuration:frameStyle template:frame previewEdge:900] : nil;
        }
        UIImage *mark = [MTWatermarkRenderer materialForIdentifier:identifier];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.generation != generation) return;
            self.preview.image = base; self.mark.image = mark;
            self.previewEmpty.hidden = base != nil;
            self.previewEmpty.text = @"请先在套壳设置中\n导入并保存可用素材";
            self.status.text = !base ? @"尚无可用的套壳预览" : @"";
            [self refreshControls];
        });
    }});
}
- (void)reloadMaterials {
    NSUInteger generation = ++self.materialGeneration;
    for (UIView *view in self.materialsStack.arrangedSubviews) { [self.materialsStack removeArrangedSubview:view]; [view removeFromSuperview]; }
    NSArray *identifiers = MTWatermarkRenderer.materials;
    self.libraryTitle.text = identifiers.count ? [NSString stringWithFormat:@"我的素材 · %lu", (unsigned long)identifiers.count] : @"我的素材";
    self.libraryEmpty.hidden = identifiers.count > 0;
    NSUInteger index = 0;
    for (NSString *identifier in identifiers) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.accessibilityIdentifier = identifier; button.accessibilityLabel = @"水印素材";
        button.accessibilityValue = [identifier isEqualToString:self.style.materialIdentifier] ? @"已选中" : @"未选中";
        button.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
        button.layer.cornerRadius = 12; button.clipsToBounds = YES;
        UIImageView *materialImage = [UIImageView new]; materialImage.contentMode = UIViewContentModeScaleAspectFit;
        materialImage.translatesAutoresizingMaskIntoConstraints = NO; [button addSubview:materialImage];
        [NSLayoutConstraint activateConstraints:@[
            [materialImage.topAnchor constraintEqualToAnchor:button.topAnchor constant:8],
            [materialImage.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:8],
            [materialImage.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-8],
            [materialImage.bottomAnchor constraintEqualToAnchor:button.bottomAnchor constant:-25]]];
        UILabel *name = [self label:[NSString stringWithFormat:@"素材 %lu", (unsigned long)++index] size:11 secondary:NO];
        name.textAlignment = NSTextAlignmentCenter; name.translatesAutoresizingMaskIntoConstraints = NO;
        name.userInteractionEnabled = NO; [button addSubview:name];
        UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
        check.tintColor = MTWatermarkAccent(); check.backgroundColor = UIColor.blackColor; check.layer.cornerRadius = 9;
        check.hidden = ![identifier isEqualToString:self.style.materialIdentifier]; check.translatesAutoresizingMaskIntoConstraints = NO;
        [button addSubview:check];
        [NSLayoutConstraint activateConstraints:@[
            [name.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:4],
            [name.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-4],
            [name.bottomAnchor constraintEqualToAnchor:button.bottomAnchor constant:-6],
            [check.topAnchor constraintEqualToAnchor:button.topAnchor constant:6],
            [check.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-6],
            [check.widthAnchor constraintEqualToConstant:18], [check.heightAnchor constraintEqualToConstant:18]]];
        [button addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(materialLongPressed:)]];
        button.accessibilityHint = @"轻点选用，长按删除素材";
        __weak typeof(self) weakController = self;
        button.accessibilityCustomActions = @[[[UIAccessibilityCustomAction alloc] initWithName:@"删除素材" actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
            [weakController deleteMaterialIdentifier:identifier]; return YES;
        }]];
        button.layer.borderWidth = [identifier isEqualToString:self.style.materialIdentifier] ? 2 : 0;
        button.layer.borderColor = self.view.tintColor.CGColor;
        [button addTarget:self action:@selector(selectMaterial:) forControlEvents:UIControlEventTouchUpInside];
        [self.materialsStack addArrangedSubview:button];
        UIScrollView *materials = (UIScrollView *)self.materialsStack.superview;
        [button.widthAnchor constraintEqualToAnchor:materials.frameLayoutGuide.widthAnchor multiplier:1.0/3.0 constant:-20.0/3.0].active = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_async(self.renderQueue, ^{ @autoreleasepool {
            UIImage *image = [MTWatermarkRenderer materialForIdentifier:identifier];
            UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new]; format.scale = 1;
            UIImage *thumbnail = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(152, 152) format:format]
                imageWithActions:^(UIGraphicsImageRendererContext *context) {
                    if (!image) return;
                    CGFloat scale = 140 / MAX(image.size.width, image.size.height);
                    CGSize size = CGSizeMake(image.size.width * scale, image.size.height * scale);
                    [image drawInRect:CGRectMake((152-size.width)/2, (152-size.height)/2, size.width, size.height)];
                }];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (weakSelf.materialGeneration == generation) materialImage.image = thumbnail;
            });
        }});
    }
}
- (void)selectMaterial:(UIButton *)sender {
    if (self.importing) return;
    self.style.materialIdentifier = sender.accessibilityIdentifier;
    [self refreshControls]; [self reloadMaterials]; [self refreshPreview];
}
- (void)save {
    if (self.importing) return;
    if (self.style.enabled && !self.mark.image) { [self showError:@"请先选择可用的水印素材"]; return; }
    if (![self.style remember]) { [self showError:@"设置保存失败，请重试"]; return; }
    self.navigationItem.rightBarButtonItem.title = @"已保存";
}
- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"水印设置" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    if (self.view.window && !self.presentedViewController) [self presentViewController:alert animated:YES completion:nil];
}
- (void)importPhoto {
    if (self.importing || self.presentedViewController) return;
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = PHPickerFilter.imagesFilter; configuration.selectionLimit = 1;
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration]; picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)importFile {
    if (self.importing || self.presentedViewController) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}
- (void)setImportBusy:(BOOL)busy {
    self.importing = busy; self.navigationItem.rightBarButtonItem.enabled = !busy;
    self.status.text = busy ? @"正在导入素材…" : self.status.text;
    [self refreshControls];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:^{
        NSItemProvider *provider = results.firstObject.itemProvider;
        if (!provider) return;
        [self setImportBusy:YES];
        [provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier completionHandler:^(NSURL *url, NSError *loadError) {
            // provider 的临时 URL 仅在回调期间有效，必须在返回前完成读取与原子入库。
            NSError *error = loadError;
            NSString *identifier = url ? [MTWatermarkRenderer importURL:url error:&error] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{ [self imported:identifier error:error]; });
        }];
    }];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    [controller dismissViewControllerAnimated:YES completion:^{
        [self setImportBusy:YES];
        dispatch_async(self.renderQueue, ^{ @autoreleasepool {
            BOOL scoped = [url startAccessingSecurityScopedResource];
            NSError *error = nil; NSString *identifier = [MTWatermarkRenderer importURL:url error:&error];
            if (scoped) [url stopAccessingSecurityScopedResource];
            dispatch_async(dispatch_get_main_queue(), ^{ [self imported:identifier error:error]; });
        }});
    }];
}
- (void)imported:(NSString *)identifier error:(NSError *)error {
    [self setImportBusy:NO];
    if (!identifier) { [self showError:error.localizedDescription ?: @"素材导入失败，请重试"]; return; }
    self.style.materialIdentifier = identifier;
    self.style.enabled = YES; self.enabledSwitch.on = YES;
    [self refreshControls]; [self reloadMaterials]; [self refreshPreview];
}
- (void)materialLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan)
        [self deleteMaterialIdentifier:gesture.view.accessibilityIdentifier];
}
- (void)deleteMaterialIdentifier:(NSString *)identifier {
    if (self.importing || !identifier.length || self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除水印素材？" message:@"删除当前使用的素材会关闭已保存的水印。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        MTWatermarkConfiguration *saved = [MTWatermarkConfiguration rememberedConfiguration];
        if ([saved.materialIdentifier isEqualToString:identifier]) {
            saved.enabled = NO; saved.materialIdentifier = @"";
            if (![saved remember]) { [self showError:@"设置保存失败，素材已保留"]; return; }
        }
        NSError *error = nil;
        if (![MTWatermarkRenderer removeMaterial:identifier error:&error]) { [self showError:error.localizedDescription]; return; }
        if ([self.style.materialIdentifier isEqualToString:identifier]) {
            self.style.materialIdentifier = @""; self.style.enabled = NO; self.enabledSwitch.on = NO;
        }
        [self refreshControls]; [self reloadMaterials]; [self refreshPreview];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
