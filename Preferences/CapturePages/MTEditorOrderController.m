#import "MTEditorOrderController.h"
#import "MTEditorButtonEditController.h"
#import "../../Modules/Capture/Sources/Common/MTConstants.h"
#import "../../Modules/Capture/Sources/Common/MTEditorOrder.h"
#import "../../Modules/Capture/Sources/Common/MTSelectionToolbar.h"
#import "../../Modules/Capture/Sources/Common/MTPanelAppearance.h"
#import "../../Modules/Capture/Sources/Common/MTCaptureLog.h"
#import "../../Modules/Capture/Sources/Editor/MTEditorLayout.h"
#import <QuartzCore/QuartzCore.h>

@interface MTEditorOrderController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) CGFloat previewWidth;
@property (nonatomic, assign) CGFloat previewPanelWidth;
// 必须 strong：copy 语义会把 NSMutableArray 存成不可变 NSArray，拖动时 removeObjectAtIndex 直接崩溃。
@property (nonatomic, strong) NSMutableArray<NSString *> *actionOrder;
@property (nonatomic, strong) NSMutableArray<NSString *> *toolOrder;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectionOrder;
@property (nonatomic, strong) NSMutableSet<NSString *> *actionHidden;
@property (nonatomic, strong) NSMutableSet<NSString *> *toolHidden;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectionHidden;
@property (nonatomic, weak) UILabel *sizeValueLabel;
@end

@implementation MTEditorOrderController

// 三个入口共用行交互，sectionKinds 只列出当前页面实际拥有的分组。
// kind：0=编辑操作 1=标记工具 2=截图按钮 3=外观滑杆 4=截图按钮显示样式 5=截图按钮排布。
// 外观滑杆三页都放在预览下方：所有按钮图标共用一个大小，任意页面均可滑动调整。
- (BOOL)mtFullscreen { return NO; }
- (BOOL)mtRegion { return NO; }
- (NSArray<NSNumber *> *)mtSectionKinds {
    if ([self mtRegion]) return @[@3, @5, @2, @4];
    return @[@3, @0, @1];
}
- (NSInteger)mtKindForSection:(NSInteger)section {
    return [self mtSectionKinds][section].integerValue;
}

- (NSArray<NSNumber *> *)mtSelectionStyles {
    return @[@(MTSelectionButtonStyleIcon), @(MTSelectionButtonStyleText), @(MTSelectionButtonStyleIconAndText)];
}

- (NSString *)mtTitleForSelectionStyle:(MTSelectionButtonStyle)style {
    if (style == MTSelectionButtonStyleText) return @"文字";
    if (style == MTSelectionButtonStyleIconAndText) return @"图标＋文字";
    return @"图标";
}

- (void)loadView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.view = self.tableView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self mtRegion] ? @"截图按钮" : ([self mtFullscreen] ? @"全屏标记按钮" : @"图片编辑按钮");
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"恢复默认" style:UIBarButtonItemStylePlain
                                      target:self action:@selector(mtResetTapped:)];
    [self mtReloadFromPreferences];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64.0;
    // 编辑模式使用 editingAccessoryView，保留右侧拖动手柄。
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
    MTCaptureLogInfo(@"prefs button settings opened: %@", self.title);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    BOOL panelWidthChanged = ![self mtRegion] &&
        fabs([self mtPanelReferenceWidth] - self.previewPanelWidth) > 0.5;
    if (width > 0 && (fabs(width - self.previewWidth) > 0.5 || panelWidthChanged)) [self mtRefreshPreview];
}

- (void)mtReloadFromPreferences {
    self.actionOrder = [[MTEditorOrder currentActionOrderForFullscreenMarkup:[self mtFullscreen]] mutableCopy];
    self.toolOrder = [[MTEditorOrder currentToolOrderForFullscreenMarkup:[self mtFullscreen]] mutableCopy];
    // 写死的四角键（关闭/撤销/完成）不进设置列表：不可排序、不可显隐、不可改图标。
    [self.actionOrder removeObjectsInArray:[MTEditorOrder fixedActionIdentifiers]];
    if ([self mtFullscreen]) {
        [self.actionOrder removeObject:@"crop"];
    } else {
        [self.actionOrder removeObject:@"dock"];
        [self.actionOrder removeObject:@"collapse"];
    }
    self.selectionOrder = [[MTEditorOrder currentSelectionOrder] mutableCopy];
    self.actionHidden = [[NSMutableSet alloc] initWithArray:[MTEditorOrder currentActionHiddenForFullscreenMarkup:[self mtFullscreen]]];
    // 历史上隐藏过的四角键一并清出：编辑器已写死常驻，避免陈旧偏好滞留。
    NSMutableSet<NSString *> *fixedIds = [NSMutableSet setWithArray:[MTEditorOrder fixedActionIdentifiers]];
    [self.actionHidden minusSet:fixedIds];
    self.toolHidden = [[NSMutableSet alloc] initWithArray:[MTEditorOrder currentToolHiddenForFullscreenMarkup:[self mtFullscreen]]];
    // 选区出口按钮在设置页始终呈现为开启（编辑器四角键已整体写死，不在列表内）。
    // confirm 已随 2.0.8 移除：陈旧偏好经 currentSelectionHidden 的目录过滤自动剔除。
    self.selectionHidden = [[NSMutableSet alloc] initWithArray:[MTEditorOrder currentSelectionHidden]];
    [self.selectionHidden removeObject:@"cancel"];
}

#pragma mark - 数据源

// SHELLX 未安装时，其外调按钮在实际截图界面上永远不会出现：列表与预览同口径剔除，
// 避免用户配置一堆无效条目。只过滤展示用副本，selectionOrder 保持完整，保存时不丢配置。
- (NSArray<NSString *> *)mtSelectionDisplayOrder {
    NSArray<NSString *> *order = self.selectionOrder ?: @[];
    if ([MTEditorOrder shellXInstalled]) return order;
    NSMutableArray<NSString *> *filtered = [order mutableCopy];
    [filtered removeObjectsInArray:[MTEditorOrder shellxSelectionIdentifiers]];
    return [filtered copy];
}

// 按实际编辑器宽度排版，再整体缩入设置页，避免页边距改变真实面板的列数。
- (CGFloat)mtPanelReferenceWidth {
    UIWindow *window = self.view.window;
    CGFloat width = window ? CGRectGetWidth(window.bounds) : CGRectGetWidth(self.view.bounds);
    UIEdgeInsets safe = window ? window.safeAreaInsets : self.view.safeAreaInsets;
    CGFloat panelWidth = MAX(1.0, width - safe.left - safe.right - 24.0);
    return [self mtFullscreen] ? MIN(600.0, panelWidth) : panelWidth;
}

- (UIButton *)mtPanelPreviewButtonForIdentifier:(NSString *)identifier
                                          tool:(BOOL)tool
                                      iconSize:(CGFloat)iconSize {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    NSString *name = tool ? [MTEditorOrder displayNameForToolIdentifier:identifier]
                          : [MTEditorOrder displayNameForActionIdentifier:identifier];
    NSString *symbol = tool ? [MTEditorOrder iconNameForToolIdentifier:identifier]
                            : [MTEditorOrder iconNameForActionIdentifier:identifier];
    UIImage *icon = symbol.length ? [UIImage systemImageNamed:symbol] : nil;
    if (icon) {
        [button setImage:[icon imageWithConfiguration:[UIImageSymbolConfiguration
            configurationWithPointSize:iconSize weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    } else {
        [button setTitle:name forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:(tool ? 11.0 : 10.0) * iconSize / 17.0
                                                  weight:tool ? UIFontWeightMedium : UIFontWeightRegular];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
    }
    button.tintColor = UIColor.whiteColor;
    button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:tool ? 0.10 : 0.08];
    button.layer.cornerRadius = 9.0 * iconSize / 17.0;
    button.accessibilityLabel = name;
    button.accessibilityTraits = UIAccessibilityTraitImage;
    if (!tool && ([identifier isEqualToString:@"undo"] || [identifier isEqualToString:@"redo"] ||
                  [identifier isEqualToString:@"delete"] || [identifier isEqualToString:@"front"])) {
        button.enabled = NO;
        button.alpha = ([identifier isEqualToString:@"undo"] || [identifier isEqualToString:@"redo"]) ? 0.4 : 0.35;
    }
    return button;
}

- (UIView *)mtColorPreviewWithFrame:(CGRect)frame iconSize:(CGFloat)iconSize fullscreen:(BOOL)fullscreen {
    CGFloat scale = iconSize / 17.0;
    UIView *colorButton = [[UIView alloc] initWithFrame:frame];
    colorButton.isAccessibilityElement = YES;
    colorButton.accessibilityLabel = @"自定义颜色";
    colorButton.accessibilityTraits = UIAccessibilityTraitImage;
    CAGradientLayer *rainbow = [CAGradientLayer layer];
    rainbow.type = kCAGradientLayerConic;
    NSMutableArray<id> *colors = [NSMutableArray array];
    for (NSUInteger i = 0; i <= 6; i++) {
        [colors addObject:(id)[UIColor colorWithHue:(CGFloat)i / 6.0 saturation:0.75 brightness:1.0 alpha:1.0].CGColor];
    }
    rainbow.colors = colors;
    CGFloat ringInset = (fullscreen ? 5.0 : 2.0) * scale;
    rainbow.frame = CGRectInset(colorButton.bounds, ringInset, ringInset);
    rainbow.cornerRadius = CGRectGetWidth(rainbow.bounds) / 2.0;
    [colorButton.layer addSublayer:rainbow];
    CGFloat swatchInset = (fullscreen ? 10.0 : 7.0) * scale;
    UIView *swatch = [[UIView alloc] initWithFrame:CGRectInset(colorButton.bounds, swatchInset, swatchInset)];
    swatch.backgroundColor = UIColor.redColor;
    swatch.layer.cornerRadius = CGRectGetWidth(swatch.bounds) / 2.0;
    [colorButton addSubview:swatch];
    return colorButton;
}

- (UIView *)mtEditorPanelPreviewWithTools:(NSArray<NSString *> *)tools
                                 actions:(NSArray<NSString *> *)actions
                                   width:(CGFloat)width
                                iconSize:(CGFloat)iconSize {
    CGFloat scale = iconSize / 17.0;
    MTEditorGridLayout actionLayout = MTEditorGridMakeScaled(width, actions.count, 8, scale);
    MTEditorGridLayout toolLayout = MTEditorGridMakeScaled(width, tools.count + 1, 8, scale);
    CGFloat topHeight = actionLayout.height + 14.0 * scale;
    CGFloat gridY = MTEditorPanelPadTop + MTEditorRowSliderHeight + MTEditorPanelRowGap;
    CGFloat bottomHeight = gridY + toolLayout.height + MTEditorPanelPadBottom;
    // 预览压缩图片区域，只展示上下两组控件；各组内部尺寸和位置沿用实际编辑器。
    CGFloat bottomY = topHeight + MTEditorPanelRowGap;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, bottomY + bottomHeight)];
    panel.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    panel.layer.cornerRadius = 28.0;
    panel.clipsToBounds = YES;
    panel.userInteractionEnabled = NO;
    for (NSUInteger i = 0; i < actions.count; i++) {
        UIButton *button = [self mtPanelPreviewButtonForIdentifier:actions[i] tool:NO iconSize:iconSize];
        button.frame = CGRectOffset(MTEditorGridFrame(actionLayout, i), 0, 7.0 * scale);
        if ([actions[i] isEqualToString:@"close"]) button.tintColor = UIColor.systemRedColor;
        if ([actions[i] isEqualToString:@"done"]) button.tintColor = UIColor.systemGreenColor;
        [panel addSubview:button];
    }
    UIView *bottom = [[UIView alloc] initWithFrame:CGRectMake(0, bottomY, width, bottomHeight)];
    bottom.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1.0];
    [panel addSubview:bottom];
    UIView *widthRow = [[UIView alloc] initWithFrame:CGRectMake(0, MTEditorPanelPadTop, width, MTEditorRowSliderHeight)];
    NSArray<NSString *> *widthTools = @[@"brush", @"highlight", @"line", @"arrow", @"rect", @"oval",
                                       @"rectSolid", @"ovalSolid", @"mosaic"];
    BOOL widthEnabled = [widthTools containsObject:tools.firstObject];
    widthRow.alpha = widthEnabled ? 1.0 : 0.35;
    [bottom addSubview:widthRow];
    NSArray<NSString *> *hintSymbols = @[@"circle.inset.filled", @"circle.fill"];
    for (NSUInteger i = 0; i < hintSymbols.count; i++) {
        UIImage *icon = [UIImage systemImageNamed:hintSymbols[i]];
        UIImageView *hint = [[UIImageView alloc] initWithImage:[icon imageWithConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular]]];
        hint.tintColor = UIColor.whiteColor;
        hint.frame = CGRectMake(i == 0 ? 16.0 : width - 38.0, 11.0, 22.0, 22.0);
        [widthRow addSubview:hint];
    }
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(48.0, 0, MAX(40.0, width - 92.0), MTEditorRowSliderHeight)];
    slider.minimumTrackTintColor = UIColor.whiteColor;
    slider.maximumTrackTintColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    slider.thumbTintColor = UIColor.whiteColor;
    [slider setThumbImage:[MTPanelAppearance editorSliderThumbImage] forState:UIControlStateNormal];
    // 线宽随编辑图片尺寸变化，静态按钮预览以面板宽度作为示例图片短边。
    slider.minimumValue = 2.0;
    slider.maximumValue = MAX(8.0, width / 6.0);
    slider.value = MAX(MTDefaultEditorLineWidth, width / 100.0);
    slider.enabled = widthEnabled;
    slider.accessibilityLabel = @"画笔粗细预览";
    [widthRow addSubview:slider];
    for (NSUInteger i = 0; i < tools.count; i++) {
        UIButton *button = [self mtPanelPreviewButtonForIdentifier:tools[i] tool:YES iconSize:iconSize];
        button.frame = CGRectOffset(MTEditorGridFrame(toolLayout, i), 0, gridY);
        if (i == 0) {
            button.tintColor = [UIColor colorWithRed:1.0 green:0.78 blue:0.08 alpha:1.0];
            button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
        }
        [bottom addSubview:button];
    }
    CGRect colorFrame = CGRectOffset(MTEditorGridFrame(toolLayout, tools.count), 0, gridY);
    [bottom addSubview:[self mtColorPreviewWithFrame:colorFrame iconSize:iconSize fullscreen:NO]];
    return panel;
}

- (UIView *)mtMarkupPanelPreviewWithTools:(NSArray<NSString *> *)tools
                                 actions:(NSArray<NSString *> *)actions
                                   width:(CGFloat)width
                                iconSize:(CGFloat)iconSize {
    CGFloat scale = iconSize / 17.0;
    MTEditorMarkupGridLayout layout = MTEditorMarkupGridMakeScaled(width, tools.count + actions.count,
        MTEditorPanelSideMargin, scale);
    CGFloat gridY = MTEditorPanelPadTop + MTEditorPanelGripHeight;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width,
        gridY + layout.grid.height + MTEditorPanelPadBottom)];
    panel.layer.cornerRadius = 24.0;
    panel.userInteractionEnabled = NO;
    [MTPanelAppearance installBackgroundInView:panel];

    UIView *grip = [[UIView alloc] initWithFrame:CGRectMake((width - 38.0) / 2.0,
        MTEditorPanelGripHeight / 2.0 - 2.0, 38.0, 4.0)];
    grip.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    grip.layer.cornerRadius = 2.0;
    [panel addSubview:grip];
    NSArray<NSString *> *items = [tools arrayByAddingObjectsFromArray:actions];
    for (NSUInteger i = 0; i < items.count; i++) {
        BOOL tool = i < tools.count;
        UIButton *button = [self mtPanelPreviewButtonForIdentifier:items[i] tool:tool iconSize:iconSize];
        button.frame = CGRectOffset(MTEditorMarkupGridFrame(layout, i), 0, gridY);
        if (tool && i == 0) {
            button.tintColor = [UIColor colorWithRed:1.0 green:0.78 blue:0.08 alpha:1.0];
            button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
        }
        [panel addSubview:button];
    }
    MTEditorMarkupCornerFrames corners = MTEditorMarkupCornerFramesMake(layout.grid, width, gridY, layout.grid.height);
    NSArray<NSString *> *cornerIDs = @[@"close", @"undo", @"done"];
    CGRect frames[] = { corners.close, corners.undo, corners.done };
    for (NSUInteger i = 0; i < cornerIDs.count; i++) {
        UIButton *button = [self mtPanelPreviewButtonForIdentifier:cornerIDs[i] tool:NO iconSize:iconSize];
        button.frame = frames[i];
        button.backgroundColor = UIColor.clearColor;
        if (i == 0) button.tintColor = UIColor.systemRedColor;
        if (i == 2) button.tintColor = UIColor.systemGreenColor;
        [panel addSubview:button];
    }
    [panel addSubview:[self mtColorPreviewWithFrame:corners.color iconSize:iconSize fullscreen:YES]];
    return panel;
}

// 普通编辑与全屏标记展示各自的完整按钮面板；截图按钮复用选区工具栏。
// 和编辑器共用顺序、显隐、模式过滤、图标来源、网格与四角布局。
// 不创建截图窗口、不启动编辑任务，所有更新由 UIKit 主线程事件驱动。
- (void)mtRefreshPreview {
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;
    self.previewWidth = width;
    CGFloat inset = MAX(16.0, self.tableView.safeAreaInsets.left + 16.0);
    CGFloat rightInset = MAX(16.0, self.tableView.safeAreaInsets.right + 16.0);
    CGFloat contentWidth = MAX(1.0, width - inset - rightInset);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 1)];

    // 固定键先补回再过滤显隐，与实际面板保持一致；所有可排序操作关闭时不误触发全量回退。
    NSArray<NSString *> *actionOrder = [self mtRegion] ? self.actionOrder
        : [MTEditorOrder orderWithFixedActionButtonsPinned:self.actionOrder];
    NSArray<NSString *> *actions = [MTEditorOrder visibleActionOrderForOrder:actionOrder
                                                                    hidden:self.actionHidden.allObjects
                                                          fullscreenMarkup:[self mtFullscreen]];
    if ([self mtFullscreen]) {
        // 固定键在完整面板四角单独展示，不占网格项。
        NSMutableArray<NSString *> *grid = [actions mutableCopy];
        [grid removeObjectsInArray:[MTEditorOrder fixedActionIdentifiers]];
        actions = grid;
    } else {
        // 普通编辑网格包含写死的固定键（钉在目录默认位），预览与编辑器保持一致。
        actions = [MTEditorOrder orderWithFixedActionButtonsPinned:actions];
    }
    NSArray<NSString *> *tools = [MTEditorOrder visibleOrderForOrder:self.toolOrder hidden:self.toolHidden.allObjects];
    // 预览与实际截图界面同口径：SHELLX 未安装时其按钮不会出现，这里也不画。
    NSArray<NSString *> *selection = [MTEditorOrder visibleSelectionOrderForOrder:[self mtSelectionDisplayOrder]
                                                                          hidden:self.selectionHidden.allObjects
                                                                         instant:NO];
    CGFloat y = 12.0;
    CGFloat iconSize = [MTEditorOrder buttonIconPointSize];
    if (![self mtRegion]) {
        UILabel *caption = [[UILabel alloc] initWithFrame:CGRectMake(inset + 4, y, contentWidth - 8, 22)];
        caption.text = [self mtFullscreen] ? @"全屏标记面板预览" : @"图片编辑面板预览";
        caption.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        caption.textColor = UIColor.secondaryLabelColor;
        [header addSubview:caption];
        y += 28.0;
        self.previewPanelWidth = [self mtPanelReferenceWidth];
        UIView *panel = [self mtFullscreen]
            ? [self mtMarkupPanelPreviewWithTools:tools actions:actions width:self.previewPanelWidth iconSize:iconSize]
            : [self mtEditorPanelPreviewWithTools:tools actions:actions width:self.previewPanelWidth iconSize:iconSize];
        CGFloat scale = MIN(1.0, contentWidth / self.previewPanelWidth);
        CGFloat previewHeight = CGRectGetHeight(panel.bounds) * scale;
        panel.transform = CGAffineTransformMakeScale(scale, scale);
        panel.center = CGPointMake(inset + contentWidth / 2.0, y + previewHeight / 2.0);
        [header addSubview:panel];
        y += previewHeight + 14.0;
    }
    if ([self mtRegion]) {
        UILabel *caption = [[UILabel alloc] initWithFrame:CGRectMake(inset + 4, y, contentWidth - 8, 22)];
        caption.text = @"截图按钮预览";
        caption.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        caption.textColor = UIColor.secondaryLabelColor;
        [header addSubview:caption];
        y += 28;
        // 直接展示实际工具栏：图文排列、分隔线及大小调整与截图界面一致。
        MTSelectionToolbar *toolbar = [[MTSelectionToolbar alloc] initWithIdentifiers:selection
            style:[MTEditorOrder selectionButtonStyle] iconPointSize:iconSize
            arrangement:[MTEditorOrder selectionToolbarArrangement]];
        CGFloat toolbarWidth = [toolbar preferredWidthForAvailableWidth:contentWidth];
        CGFloat toolbarHeight = [toolbar preferredHeightForAvailableWidth:toolbarWidth];
        toolbar.frame = CGRectMake(inset + (contentWidth - toolbarWidth) / 2.0, y,
                                   toolbarWidth, toolbarHeight);
        // 保留滚动手势，禁用按钮点击，便于直接预览滑动排布。
        for (UIButton *button in toolbar.buttons) button.userInteractionEnabled = NO;
        for (UIButton *button in toolbar.buttons) button.accessibilityTraits = UIAccessibilityTraitImage;
        [header addSubview:toolbar];
        y += toolbarHeight + 14.0;
    }
    UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(inset + 4, y, contentWidth - 8, 0)];
    note.text = [self mtRegion]
        ? @"拖动手柄排序，开关控制截图按钮显隐，点击行修改名称与图标。“按钮排布”可选多排或单排横向滑动，默认多排；“显示样式”可选图标、文字、图标＋文字（上图下字），预览与大小调整同步。修改即时保存，下次打开生效；冻结截图共用此配置，即时模式仅显示 取消、全屏。大小与编辑器共用。"
        : ([self mtFullscreen] ? @"预览显示面板的初始按钮状态，排序、开关、图标名称和大小即时更新；关闭、取色、撤销、完成固定为四角键，不参与修改。仅设置全屏标记的顺序与显隐，与截图按钮和普通图片编辑相互独立。名称、图标和大小与普通图片编辑共用，修改即时保存，实际面板下次打开生效。"
                              : @"预览按实际顶部操作栏、线宽条和工具网格排列，展示初始按钮状态；排序、开关、图标名称和大小即时更新。名称、图标和大小仍与全屏标记共用，顺序与显隐相互独立。修改即时保存，实际编辑器下次打开生效。");
    note.font = [UIFont systemFontOfSize:12];
    note.textColor = UIColor.secondaryLabelColor;
    note.numberOfLines = 0;
    CGSize noteSize = [note sizeThatFits:CGSizeMake(contentWidth - 8, CGFLOAT_MAX)];
    note.frame = CGRectMake(inset + 4, y, contentWidth - 8, noteSize.height);
    [header addSubview:note];
    header.frame = CGRectMake(0, 0, width, y + noteSize.height + 8);
    self.tableView.tableHeaderView = header;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self mtSectionKinds].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    section = [self mtKindForSection:section];
    if (section == 0) return self.actionOrder.count;
    if (section == 1) return self.toolOrder.count;
    if (section == 2) return [self mtSelectionDisplayOrder].count;
    if (section == 4) return [self mtSelectionStyles].count;
    if (section == 5) return 2;
    return 1;   // 外观：图标大小
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    section = [self mtKindForSection:section];
    if (section == 0) return @"编辑操作图标";
    if (section == 1) return @"标记工具图标";
    if (section == 2) return @"截图按钮";
    if (section == 4) return @"显示样式";
    if (section == 5) return @"按钮排布";
    return @"外观";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    section = [self mtKindForSection:section];
    if (section == 0) {
        return [self mtFullscreen]
            ? @"拖动排序，开关控制全屏标记操作按钮显隐，点击行修改共用名称与图标（与图片编辑同步）；关闭、取色、撤销、完成已固定为面板四角键，不参与排序、显隐与图标修改。"
            : @"拖动排序，开关控制普通图片编辑按钮显隐，点击行修改共用图标与名称；关闭、撤销、完成已写死固定，不可修改。";
    }
    if (section == 1) {
        return @"工具排序与显隐仅影响当前页面对应的编辑模式。全部工具关闭时回退显示全部工具，打开编辑器默认选中排序后的第一个工具。";
    }
    if (section == 2) {
        return @"截图/冻结截图选区工具栏的按钮排序与显隐；“取消”始终显示，“悬浮”把选区结果以可拖动悬浮窗常驻屏幕，“全屏标记”无视当前框选直接对全屏标记。即时模式仅显示 取消/全屏。点击行可修改名称与图标。";
    }
    if (section == 5) return @"默认多排，宽度不足时换行；滑动模式只占一排，横向滑动查看其余按钮。预览可直接滑动，下次打开截图生效。";
    if (section == 4) {
        return @"可选图标、文字、图标＋文字；图标＋文字采用上图下字。预览即时更新，下次打开截图生效；三种样式均支持自定义名称和大小调整。";
    }
    return @"大小范围为 10–20pt，三个按钮设置页共用同一数值；截图按钮三种样式的图标、文字、间距和工具栏尺寸同步调整。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger kind = [self mtKindForSection:indexPath.section];
    if (kind == 3) {
        return [self mtSliderCellForTableView:tableView];
    }
    if (kind == 5) {
        return [self mtArrangementCellForTableView:tableView indexPath:indexPath];
    }
    if (kind == 4) {
        return [self mtStyleCellForTableView:tableView indexPath:indexPath];
    }

    NSString *reuse = @"MTEditorOrderCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    NSString *identifier = [self identifierAtIndexPath:indexPath];
    NSString *displayName = [self displayNameForIdentifier:identifier section:indexPath.section];
    cell.textLabel.text = displayName;
    cell.detailTextLabel.text = @"拖动右侧排序 · 点击修改图标";
    NSString *iconName = kind == 0
        ? [MTEditorOrder iconNameForActionIdentifier:identifier]
        : (kind == 1
            ? [MTEditorOrder iconNameForToolIdentifier:identifier]
            : [MTEditorOrder iconNameForSelectionIdentifier:identifier]);
    cell.imageView.image = iconName.length ? [UIImage systemImageNamed:iconName] : nil;

    UISwitch *toggle = (UISwitch *)cell.accessoryView;
    if (![toggle isKindOfClass:[UISwitch class]]) {
        toggle = [[UISwitch alloc] init];
        [toggle addTarget:self action:@selector(mtVisibilityChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    cell.editingAccessoryView = toggle;
    // 复用会换行，开关的无障碍名称必须每次随行重设。
    toggle.accessibilityLabel = [NSString stringWithFormat:@"显示%@", displayName ?: @""];
    BOOL alwaysVisible = [self isAlwaysVisibleIdentifier:identifier section:indexPath.section];
    toggle.on = ![self isHiddenIdentifier:identifier section:indexPath.section];
    toggle.enabled = !alwaysVisible;
    cell.showsReorderControl = YES;
    return cell;
}

- (UITableViewCell *)mtSliderCellForTableView:(UITableView *)tableView {
    NSString *reuse = @"MTEditorSizeCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuse];
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 31)];
        slider.minimumValue = 10.0;
        slider.maximumValue = 20.0;
        [slider addTarget:self action:@selector(mtIconSizeChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = slider;
        self.sizeValueLabel = cell.detailTextLabel;
    }
    UISlider *slider = (UISlider *)cell.accessoryView;
    cell.textLabel.text = [self mtRegion] ? @"按钮大小" : @"按钮图标大小";
    cell.editingAccessoryView = slider;
    CGFloat size = [MTEditorOrder buttonIconPointSize];
    if (slider.value != size) slider.value = size;   // 拖动中重入时避免打断
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0fpt", size];
    // 复用路径也会走这里，弱引用必须每次重绑到当前 cell 的标签。
    self.sizeValueLabel = cell.detailTextLabel;
    cell.showsReorderControl = NO;
    return cell;
}

// 三种显示样式以单选行展示，兼容排序页的 editingAccessoryType。
- (UITableViewCell *)mtStyleCellForTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
    NSString *reuse = @"MTEditorSelectionStyleCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
    }
    MTSelectionButtonStyle style = [self mtSelectionStyles][indexPath.row].integerValue;
    BOOL selected = style == [MTEditorOrder selectionButtonStyle];
    cell.textLabel.text = [self mtTitleForSelectionStyle:style];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.editingAccessoryType = cell.accessoryType;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    cell.showsReorderControl = NO;
    return cell;
}

- (UITableViewCell *)mtArrangementCellForTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
    NSString *reuse = @"MTSelectionArrangementCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
    BOOL selected = indexPath.row == (NSInteger)[MTEditorOrder selectionToolbarArrangement];
    cell.textLabel.text = indexPath.row == 0 ? @"多排" : @"滑动";
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.editingAccessoryType = cell.accessoryType;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    cell.showsReorderControl = NO;
    return cell;
}

- (NSString *)identifierAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger kind = [self mtKindForSection:indexPath.section];
    if (kind == 0) return self.actionOrder[indexPath.row];
    if (kind == 1) return self.toolOrder[indexPath.row];
    if (kind == 2) return [self mtSelectionDisplayOrder][indexPath.row];
    return @"";
}

- (NSString *)displayNameForIdentifier:(NSString *)identifier section:(NSInteger)section {
    return [self mtDisplayNameForIdentifier:identifier kind:[self mtKindForSection:section]];
}

- (NSString *)mtDisplayNameForIdentifier:(NSString *)identifier kind:(NSInteger)section {
    if (section == 0) return [MTEditorOrder displayNameForActionIdentifier:identifier];
    if (section == 1) return [MTEditorOrder displayNameForToolIdentifier:identifier];
    return [MTEditorOrder displayNameForSelectionIdentifier:identifier];
}

- (NSMutableSet<NSString *> *)hiddenSetForSection:(NSInteger)section {
    section = [self mtKindForSection:section];
    if (section == 0) return self.actionHidden;
    if (section == 1) return self.toolHidden;
    return self.selectionHidden;
}

- (BOOL)isHiddenIdentifier:(NSString *)identifier section:(NSInteger)section {
    return [[self hiddenSetForSection:section] containsObject:identifier];
}

/// 出口按钮（选区 取消）不提供隐藏开关；编辑器四角键（关闭/撤销/完成）已整体写死，
/// 不再出现在操作按钮列表，无需在此兜底。
- (BOOL)isAlwaysVisibleIdentifier:(NSString *)identifier section:(NSInteger)section {
    section = [self mtKindForSection:section];
    if (section == 2) return [identifier isEqualToString:@"cancel"];
    return NO;
}

#pragma mark - 行点击：编辑图标与名称

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    NSInteger kind = [self mtKindForSection:indexPath.section];
    if (kind == 5) {
        [MTEditorOrder saveSelectionToolbarArrangement:(MTSelectionToolbarArrangement)indexPath.row];
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section]
                 withRowAnimation:UITableViewRowAnimationNone];
        [self mtRefreshPreview];
        return;
    }
    if (kind == 4) {
        MTSelectionButtonStyle style = [self mtSelectionStyles][indexPath.row].integerValue;
        [MTEditorOrder saveSelectionButtonStyle:style];
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section]
                 withRowAnimation:UITableViewRowAnimationNone];
        [self mtRefreshPreview];
        MTCaptureLogInfo(@"prefs selection button style saved: %ld", (long)style);
        return;
    }
    // 外观/样式行不进编辑页；全屏标记页的名称图标与普通编辑共用同一存储，点击行同样可改。
    if (kind >= 3) return;
    [self.view endEditing:YES];

    NSString *identifier = [self identifierAtIndexPath:indexPath];
    // 按目录 kind 分流，不能按 indexPath.section：外观组在首位，按钮分组因页面而异。
    BOOL isAction = kind == 0;
    BOOL isSelection = kind == 2;
    NSString *defaultIcon = isAction
        ? [MTEditorOrder defaultIconNameForActionIdentifier:identifier]
        : (isSelection
            ? [MTEditorOrder defaultIconNameForSelectionIdentifier:identifier]
            : [MTEditorOrder defaultIconNameForToolIdentifier:identifier]);
    NSString *customIcon = isAction
        ? [MTEditorOrder customIconNameForActionIdentifier:identifier]
        : (isSelection
            ? [MTEditorOrder customIconNameForSelectionIdentifier:identifier]
            : [MTEditorOrder customIconNameForToolIdentifier:identifier]);
    NSString *customName = isAction
        ? [MTEditorOrder customNameForActionIdentifier:identifier]
        : (isSelection
            ? [MTEditorOrder customNameForSelectionIdentifier:identifier]
            : [MTEditorOrder customNameForToolIdentifier:identifier]);

    __weak typeof(self) weakSelf = self;
    MTEditorButtonEditController *editor =
        [[MTEditorButtonEditController alloc] initWithIdentifier:identifier
                                                       isAction:isAction
                                                    displayName:[self displayNameForIdentifier:identifier section:indexPath.section]
                                                defaultIconName:defaultIcon
                                                     customName:customName
                                                 customIconName:customIcon
                                                         onSave:^(NSString *name, NSString *iconName) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !self.presentedViewController.view.window) return;
            if (isAction) {
                [MTEditorOrder saveActionName:name forIdentifier:identifier];
                [MTEditorOrder saveActionIconName:iconName forIdentifier:identifier];
            } else if (isSelection) {
                [MTEditorOrder saveSelectionName:name forIdentifier:identifier];
                [MTEditorOrder saveSelectionIconName:iconName forIdentifier:identifier];
            } else {
                [MTEditorOrder saveToolName:name forIdentifier:identifier];
                [MTEditorOrder saveToolIconName:iconName forIdentifier:identifier];
            }
            MTCaptureLogInfo(@"prefs editor button override saved: %@", identifier);
            [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                                  withRowAnimation:UITableViewRowAnimationNone];
            [self mtRefreshPreview];
            [self dismissViewControllerAnimated:YES completion:nil];
        }];
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:editor]
                       animated:YES completion:nil];
}

#pragma mark - 显隐开关

- (void)mtVisibilityChanged:(UISwitch *)sender {
    CGPoint point = [sender convertPoint:CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds))
                                  toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath || [self mtKindForSection:indexPath.section] >= 3) return;
    NSString *identifier = [self identifierAtIndexPath:indexPath];
    NSMutableSet<NSString *> *hidden = [self hiddenSetForSection:indexPath.section];
    if (sender.on) {
        [hidden removeObject:identifier];
    } else {
        [hidden addObject:identifier];
    }
    [self mtPersistAll];
    [self mtRefreshPreview];
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - 图标大小

- (void)mtIconSizeChanged:(UISlider *)sender {
    CGFloat size = MAX(10.0, MIN(20.0, sender.value));
    [MTEditorOrder saveButtonIconPointSize:size];
    self.sizeValueLabel.text = [NSString stringWithFormat:@"%.0fpt", size];
    [self mtRefreshPreview];
}

#pragma mark - 拖动排序

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self mtKindForSection:indexPath.section] < 3;
}

// 只允许同分组内移动，跨组拖动落点无效。
- (NSIndexPath *)tableView:(UITableView *)tableView
   targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
                          toProposedIndexPath:(NSIndexPath *)proposedIndexPath {
    if (sourceIndexPath.section != proposedIndexPath.section) return sourceIndexPath;
    return proposedIndexPath;
}

- (void)tableView:(UITableView *)tableView
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSInteger kind = [self mtKindForSection:sourceIndexPath.section];
    if (kind >= 3 || sourceIndexPath.section != destinationIndexPath.section) return;
    if (kind == 2) {
        // 列表按 SHELLX 在场与否过滤过，下标与 selectionOrder 不一定对齐，统一按锚点换算。
        [self mtMoveSelectionRowInDisplayOrder:[self mtSelectionDisplayOrder]
                                        source:sourceIndexPath.row
                                   destination:destinationIndexPath.row];
        [self mtPersistAll];
        [self mtRefreshPreview];
        return;
    }
    NSMutableArray<NSString *> *order = nil;
    if (kind == 0) order = self.actionOrder;
    else if (kind == 1) order = self.toolOrder;
    else order = self.selectionOrder;
    if (sourceIndexPath.row >= order.count || destinationIndexPath.row >= order.count) return;
    NSString *identifier = order[sourceIndexPath.row];
    [order removeObjectAtIndex:sourceIndexPath.row];
    [order insertObject:identifier atIndex:destinationIndexPath.row];
    [self mtPersistAll];
    [self mtRefreshPreview];
}

// 显示顺序与实际保存顺序的换算：落点取"目标行现有条目之前"，落到列表末尾时插到最后
// 一个可见条目之后。被过滤掉的 SHELLX 条目保留在原位，重新装上插件后次序不变。
- (void)mtMoveSelectionRowInDisplayOrder:(NSArray<NSString *> *)display
                                  source:(NSInteger)sourceRow
                             destination:(NSInteger)destinationRow {
    if (sourceRow < 0 || sourceRow >= (NSInteger)display.count) return;
    NSMutableArray<NSString *> *remaining = [display mutableCopy];
    NSString *identifier = remaining[sourceRow];
    [remaining removeObjectAtIndex:sourceRow];

    NSMutableArray<NSString *> *order = self.selectionOrder;
    [order removeObject:identifier];
    NSUInteger insertIndex = order.count;
    if (destinationRow >= 0 && destinationRow < (NSInteger)remaining.count) {
        NSUInteger anchor = [order indexOfObject:remaining[destinationRow]];
        if (anchor != NSNotFound) insertIndex = anchor;
    } else {
        NSString *last = remaining.lastObject;
        NSUInteger tail = last ? [order indexOfObject:last] : NSNotFound;
        if (tail != NSNotFound) insertIndex = tail + 1;
    }
    [order insertObject:identifier atIndex:MIN(insertIndex, order.count)];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

#pragma mark - 持久化

- (void)mtPersistAll {
    if ([self mtRegion]) {
        [MTEditorOrder saveSelectionOrderString:[MTEditorOrder stringForOrder:self.selectionOrder]];
        [MTEditorOrder saveSelectionHiddenString:[MTEditorOrder stringForOrder:self.selectionHidden.allObjects]];
    } else {
        [MTEditorOrder saveActionOrderString:[MTEditorOrder stringForOrder:self.actionOrder] fullscreenMarkup:[self mtFullscreen]];
        [MTEditorOrder saveToolOrderString:[MTEditorOrder stringForOrder:self.toolOrder] fullscreenMarkup:[self mtFullscreen]];
        [MTEditorOrder saveActionHiddenString:[MTEditorOrder stringForOrder:self.actionHidden.allObjects] fullscreenMarkup:[self mtFullscreen]];
        [MTEditorOrder saveToolHiddenString:[MTEditorOrder stringForOrder:self.toolHidden.allObjects] fullscreenMarkup:[self mtFullscreen]];
    }
    MTCaptureLogInfo(@"prefs button settings saved: %@", self.title);
}

- (void)mtResetTapped:(UIBarButtonItem *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认"
                                                                   message:([self mtRegion]
        ? @"恢复截图按钮顺序与开关，清除自定义名称与图标，显示样式复位为图标，按钮排布复位为多排；不影响其他模式。"
        : ([self mtFullscreen] ? @"仅恢复当前页面的按钮顺序与开关，不影响其他模式。" : @"恢复图片编辑按钮顺序与开关，以及共用的名称、图标和大小；全屏标记和区域选区的顺序与开关不变。"))
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        if ([self mtRegion]) {
            [MTEditorOrder saveSelectionOrderString:nil];
            [MTEditorOrder saveSelectionHiddenString:nil];
            for (NSString *identifier in [MTEditorOrder defaultSelectionIdentifiers]) {
                [MTEditorOrder saveSelectionName:nil forIdentifier:identifier];
                [MTEditorOrder saveSelectionIconName:nil forIdentifier:identifier];
            }
            [MTEditorOrder saveSelectionButtonStyle:MTSelectionButtonStyleIcon];
            [MTEditorOrder saveSelectionToolbarArrangement:MTSelectionToolbarArrangementRows];
        } else {
            [MTEditorOrder saveActionOrderString:nil fullscreenMarkup:[self mtFullscreen]];
            [MTEditorOrder saveToolOrderString:nil fullscreenMarkup:[self mtFullscreen]];
            [MTEditorOrder saveActionHiddenString:nil fullscreenMarkup:[self mtFullscreen]];
            [MTEditorOrder saveToolHiddenString:nil fullscreenMarkup:[self mtFullscreen]];
        }
        if (![self mtRegion] && ![self mtFullscreen]) {
            for (NSString *identifier in [MTEditorOrder defaultActionIdentifiers]) {
                [MTEditorOrder saveActionName:nil forIdentifier:identifier];
                [MTEditorOrder saveActionIconName:nil forIdentifier:identifier];
            }
            for (NSString *identifier in [MTEditorOrder defaultToolIdentifiers]) {
                [MTEditorOrder saveToolName:nil forIdentifier:identifier];
                [MTEditorOrder saveToolIconName:nil forIdentifier:identifier];
            }
            [MTEditorOrder saveButtonIconPointSize:17.0];
        }
        [self mtReloadFromPreferences];
        [self.tableView reloadData];
        [self mtRefreshPreview];
        MTCaptureLogInfo(@"prefs editor buttons reset to defaults");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@implementation MTFullscreenButtonController
- (BOOL)mtFullscreen { return YES; }
@end

@implementation MTRegionButtonController
- (BOOL)mtRegion { return YES; }
@end
