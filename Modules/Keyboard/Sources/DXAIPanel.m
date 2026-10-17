#import "DXAIPanel.h"
#import "DXAIEngine.h"
#import "DXAIMarkdown.h"
#import "common.h"
#import "DXShared.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@class DXAIHostWindow;
@class DXAIChatPanelController;

// 全局强引用只养活"当前正被使用"的窗口。关闭路径（X / 场景销毁）立即清空引用
// 并 hidden——ShellX 集成时验证过的教训：残留的全屏僵尸窗口会继续参与
// hitTest 吞掉宿主触摸，必须同步收尾、异步释放。
static DXAIHostWindow *g_aiPanelWindow;

// 最近一次键盘 endFrame（屏幕坐标）。进程级通知流维护（进程启动即注册，
// 面板首开前键盘必然已 show 过，首帧就有值）；打开首帧用活体探测兜底。
static CGRect g_dxKeyboardFrame;

@interface DXAIPanel ()
+ (DXAIChatPanelController *)ensurePanelController;
+ (void)openFromKeyboardWithSeedText:(NSString *)seedText;
+ (void)presentInSpringBoardWithSeedText:(NSString *)seedText clipboardImage:(BOOL)clipboardImage;
+ (void)closeAndDestroyPanel;
@end

#pragma mark - 工具

static inline UIColor *DXAIAccent(void) {
    return [UIColor systemBlueColor];
}

static inline UIColor *DXAICircleChrome(void) {
    return [DXAIAccent() colorWithAlphaComponent:0.12];
}

static NSString *DXAILocalized(NSString *key) {
    return [tweakBundle localizedStringForKey:key value:key table:nil];
}

static UIImage *DXAISymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    UIFont *font = [UIFont systemFontOfSize:pointSize weight:weight];
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithFont:font];
    return [UIImage systemImageNamed:name withConfiguration:configuration];
}

// 视觉请求上限 1280px / JPEG 0.55：兼顾视觉模型识别率与 base64 体积。
static UIImage *DXAIDownscaleForUpload(UIImage *image) {
    const CGFloat maxDimension = 1280.0;
    CGFloat larger = MAX(image.size.width, image.size.height);
    if (larger <= maxDimension || larger <= 0.0) return image;
    CGFloat scale = maxDimension / larger;
    CGSize target = CGSizeMake(floor(image.size.width * scale), floor(image.size.height * scale));
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    }];
}

static NSString *DXAIDataURLForImage(UIImage *image) {
    NSData *jpeg = UIImageJPEGRepresentation(DXAIDownscaleForUpload(image), 0.55);
    if (!jpeg) return nil;
    return [NSString stringWithFormat:@"data:image/jpeg;base64,%@", [jpeg base64EncodedStringWithOptions:0]];
}

// 打开首帧的通知尚未到达时，从活跃键盘实例探测当前键盘 frame（屏幕坐标）。
// UIKeyboardImpl 是全屏容器（部分 iOS 版本上 frame 覆盖整个输入窗口且 hidden
// 不可信），必须经视图链换算出窗口坐标，再对结果做"落在屏幕下半部"的几何
// 校验——首弹落屏幕底部的根因就是把全屏容器 frame 当成了键盘 frame。
static CGRect DXAIProbeKeyboardFrame(void) {
    UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
    if (!keyboard || !keyboard.window) return CGRectZero;
    CGRect windowFrame = [keyboard convertRect:keyboard.bounds toView:nil];
    CGRect screenFrame = [keyboard.window convertRect:windowFrame toWindow:nil];
    CGFloat screenHeight = CGRectGetHeight(keyboard.window.bounds);
    if (CGRectIsNull(screenFrame) || CGRectGetHeight(screenFrame) <= 10.0) return CGRectZero;
    if (CGRectGetMinY(screenFrame) <= 0.0) return CGRectZero;                 // 全屏容器，非键盘本体
    if (CGRectGetMinY(screenFrame) >= screenHeight - 10.0) return CGRectZero; // 已滑出屏幕
    return screenFrame;
}

#pragma mark - 宿主窗口

@interface DXAIHostWindow : UIWindow
@end

@implementation DXAIHostWindow

- (BOOL)canBecomeKeyWindow {
    return YES; // 面板输入框需要 key 才能聚焦
}

// 卡片之外的触摸一律穿透回宿主：面板打开但未聚焦时，宿主文字区域仍可直接
// 点击继续输入（键盘属于宿主第一响应者，不受影响）。
// tag 7717 = 自定义弹层（模型菜单/附件菜单）打开。卡片收窄后弹层可能悬出
// 卡片边界，挂在窗口层才能命中，此时整个窗口走默认命中，点弹层外由 catcher
// 统一关闭。
#define DXAI_POPOVER_TAG 7717

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIViewController *root = self.rootViewController;
    if (!root || self.hidden) return nil;
    if (root.presentedViewController != nil) {
        // 模态弹窗（alert/照片/文件选择器）的 transition view 挂在窗口上而不在
        // root.view 里，必须走默认命中，否则弹窗收不到触摸、永远关不掉。
        return [super hitTest:point withEvent:event];
    }
    if ([self viewWithTag:DXAI_POPOVER_TAG] != nil) {
        return [super hitTest:point withEvent:event];
    }
    CGPoint local = [root.view convertPoint:point fromView:self];
    if (![root.view pointInside:local withEvent:event]) return nil;
    return [root.view hitTest:local withEvent:event];
}

@end

#pragma mark - 菜单行（图标 + 文本；UIButton 的 inset 属性 iOS 15 已弃用，改用自绘行）

@interface DXAIMenuRow : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *label;
@end

@implementation DXAIMenuRow

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.iconView = [[UIImageView alloc] init];
        self.iconView.contentMode = UIViewContentModeCenter;
        self.iconView.tintColor = DXAIAccent();
        [self addSubview:self.iconView];

        self.label = [[UILabel alloc] init];
        self.label.font = [UIFont systemFontOfSize:16.0];
        self.label.textColor = [UIColor labelColor];
        [self addSubview:self.label];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? [UIColor tertiarySystemFillColor] : UIColor.clearColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = CGRectGetHeight(self.bounds);
    self.iconView.frame = CGRectMake(16, 0, 24, height);
    self.label.frame = CGRectMake(52, 0, CGRectGetWidth(self.bounds) - 64, height);
}

@end

#pragma mark - 消息模型

@interface DXAIMessage : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, copy) NSString *imageDataURL; // 首次发送时编码并缓存，多轮不重复编码
@property (nonatomic, assign) BOOL isUser;
@property (nonatomic, assign) BOOL isError;
@property (nonatomic, assign) BOOL streaming;
@end

@implementation DXAIMessage
@end

#pragma mark - 用户气泡

@interface DXAIUserBubbleCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) NSLayoutConstraint *photoHeight;
@property (nonatomic, strong) NSLayoutConstraint *textBelowPhoto;
@property (nonatomic, strong) NSLayoutConstraint *textTopInBubble;
@end

@implementation DXAIUserBubbleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;

        self.bubble = [[UIView alloc] init];
        self.bubble.backgroundColor = DXAIAccent();
        self.bubble.layer.cornerRadius = 18.0;
        self.bubble.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.bubble];

        self.photoView = [[UIImageView alloc] init];
        self.photoView.contentMode = UIViewContentModeScaleAspectFill;
        self.photoView.clipsToBounds = YES;
        self.photoView.layer.cornerRadius = 12.0;
        self.photoView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.bubble addSubview:self.photoView];

        self.messageLabel = [[UILabel alloc] init];
        self.messageLabel.font = [UIFont systemFontOfSize:16.0];
        self.messageLabel.textColor = UIColor.whiteColor;
        self.messageLabel.numberOfLines = 0;
        self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.bubble addSubview:self.messageLabel];

        self.photoHeight = [self.photoView.heightAnchor constraintEqualToConstant:150.0];
        self.textBelowPhoto = [self.messageLabel.topAnchor constraintEqualToAnchor:self.photoView.bottomAnchor constant:6.0];
        self.textTopInBubble = [self.messageLabel.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:12.0];

        [NSLayoutConstraint activateConstraints:@[
            [self.bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14.0],
            [self.bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [self.bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [self.bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.78 constant:0.0],
            [self.photoView.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:10.0],
            [self.photoView.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-10.0],
            [self.photoView.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:10.0],
            [self.messageLabel.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:14.0],
            [self.messageLabel.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-14.0],
            [self.messageLabel.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-12.0],
        ]];
    }
    return self;
}

- (void)configureWithMessage:(DXAIMessage *)message {
    self.messageLabel.text = message.text ?: @"";
    BOOL hasImage = message.image != nil;
    self.photoView.image = message.image;
    if (hasImage) {
        self.textTopInBubble.active = NO;
        self.photoHeight.active = YES;
        self.textBelowPhoto.active = YES;
    } else {
        self.photoHeight.active = NO;
        self.textBelowPhoto.active = NO;
        self.textTopInBubble.active = YES;
    }
}

@end

#pragma mark - 助手气泡

// 助手气泡：灰色圆角气泡（左对齐，宽度封顶 0.82），内容走 DXAIMarkdown 渲染
// ——回复与网页版一致：标题/列表/引用/代码块/粗斜体/链接，流式期间每次全量重绘。
// 长按气泡把回复直接写回宿主 app 输入框并关闭 AI 窗口；textView 不可选择
// ——系统"长按选择/双击选词"与写回手势抢同一位，关掉 selectable 长按才唯一
// 归写回（单击/双击不再触发任何动作）。
@interface DXAIAssistantBubbleCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, copy) void (^pressAction)(void);
@end

@implementation DXAIAssistantBubbleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;

        self.bubble = [[UIView alloc] init];
        self.bubble.backgroundColor = [UIColor secondarySystemFillColor];
        self.bubble.layer.cornerRadius = 18.0;
        self.bubble.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.bubble];

        self.textView = [[UITextView alloc] init];
        self.textView.editable = NO;
        self.textView.selectable = NO; // 长按归写回手势，系统选择/选词菜单不再出现
        self.textView.scrollEnabled = NO;
        self.textView.backgroundColor = UIColor.clearColor;
        self.textView.textContainerInset = UIEdgeInsetsZero;
        self.textView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.bubble addSubview:self.textView];

        [NSLayoutConstraint activateConstraints:@[
            [self.bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0],
            [self.bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [self.bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [self.bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.82 constant:0.0],
            [self.textView.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:14.0],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-14.0],
            [self.textView.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:10.0],
            [self.textView.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-10.0],
        ]];

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(bubbleLongPressed:)];
        longPress.minimumPressDuration = 0.4; // 略快于系统默认，写回手感跟手
        longPress.cancelsTouchesInView = NO;
        [self.bubble addGestureRecognizer:longPress];
    }
    return self;
}

- (void)bubbleLongPressed:(UILongPressGestureRecognizer *)gr {
    // Began 即触发：面板随即关闭，不必等手指抬起
    if (gr.state == UIGestureRecognizerStateBegan && self.pressAction) self.pressAction();
}

- (void)configureWithMessage:(DXAIMessage *)message {
    NSString *text = message.text;
    if (message.isError) {
        // 本地提示（未配置 Key/请求失败等）：纯文本，不进 markdown 解析。
        self.textView.attributedText = [[NSAttributedString alloc]
            initWithString:[@"⚠️ " stringByAppendingString:text ?: @""]
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16.0],
                             NSForegroundColorAttributeName: [UIColor secondaryLabelColor]}];
    } else {
        if (message.streaming && text.length == 0) text = @"…";
        self.textView.attributedText = [DXAIMarkdown attributedStringWithMarkdown:text ?: @""
                                                                             font:[UIFont systemFontOfSize:16.0]
                                                                        textColor:[UIColor labelColor]
                                                                      accentColor:DXAIAccent()
                                                                   codeBackground:[UIColor tertiarySystemFillColor]];
    }
}

@end

#pragma mark - 聊天面板控制器

@interface DXAIChatPanelController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *modelButton;
@property (nonatomic, strong) UIButton *personaButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIView *headerDivider;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UIView *chipContainer;
@property (nonatomic, strong) UIImageView *chipThumb;
@property (nonatomic, strong) UILabel *chipNameLabel;
@property (nonatomic, strong) UIButton *chipRemoveButton;
@property (nonatomic, strong) UIView *fieldContainer;
@property (nonatomic, strong) UITextView *inputField;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIControl *popoverCatcher;
@property (nonatomic, strong) UILabel *toastView;

@property (nonatomic, strong) NSMutableArray<DXAIMessage *> *messages;
@property (nonatomic, strong) UIImage *attachedImage;
@property (nonatomic, copy) NSString *pendingFileText;
@property (nonatomic, copy) NSString *pendingFileName;
@property (nonatomic, copy) NSString *seedText;
@property (nonatomic, assign) BOOL streaming;
@property (nonatomic, assign) BOOL flushScheduled;
@property (nonatomic, strong) DXAIChatRequest *currentRequest;
@property (nonatomic, weak) UIWindow *hostKeyWindow; // 进程内承载时的宿主 key 窗口（SB 承载恒 nil）
@property (nonatomic, weak) UIResponder *hostInputResponder; // 打开面板前宿主输入框，关闭时无缝归还焦点
@property (nonatomic, copy) NSString *activePersonaID;  // 会话内用户手动选择的人设
@property (nonatomic, assign) BOOL pinnedAfterKeyboardHide; // 键盘收起且有输出：卡片钉在原位不随键盘下坠
// 抢焦点过渡期标志：面板输入框拿到焦点前，旧键盘会话必须先 resign，系统随
// 之发出一次"键盘收起"通知——这是自导的过渡，不是用户收起；过渡期内既不
// 执行空判关闭，也不随 hide 方向的 frame 变化重定位（否则卡片先坠到悬空位、
// 键盘重弹后又跳回，肉眼可见地抖一下）。两个来源：SB 入口打开即聚焦；进程
// 内入口由用户点输入框接管 key 触发（textViewShouldBeginEditing 置位）。
// 焦点落进输入框（textViewDidBeginEditing）即解除；聚焦没落成时由 0.80s
// 兜底解除。
@property (nonatomic, assign) BOOL openingFocusTransition;
// 相册/文件选择器呈现中标志：presentModalController 为给选择器让路会主动
// resign 面板输入框，这次收键盘同样是自导的——空会话面板若照常执行"键盘
// 收起即关闭"，会在 presentViewController 之前把自己销毁，选择器落在已脱离
// 窗口层级的控制器上被 UIKit 静默拒绝，表现为"点相册/文件没反应"。呈现前
// 置位，选择器回调收尾（四个 delegate 全覆盖：PHPicker 取消走 didFinishPicking
// 空结果、UIDocumentPicker 取消走 wasCancelled）即解除；用户重新聚焦输入框
// 时全屏模态必然已不在，textViewDidBeginEditing 兜底清除防陈旧标志。
@property (nonatomic, assign) BOOL presentingAttachmentPicker;

- (void)applySeedText;
- (void)refreshModelButton;
- (void)refreshChip;
- (void)updateAttachedImage:(UIImage *)image;
- (void)inputFieldTextChanged;
- (void)repositionAnimated:(BOOL)animated;
- (void)cancelRunningRequest;
- (void)focusInputField;              // 光标落进面板输入框（SB 承载打开即聚焦）
- (void)hideIfEmptyOnKeyboardHide;    // 键盘收起且会话无输出时随键盘一起关闭
- (void)assistantBubbleTappedForMessage:(DXAIMessage *)message;
+ (DXAIChatPanelController *)liveController; // 当前正显示的面板（进程级键盘通知用）
@end

// 面板输入框：系统"粘贴"菜单扩展出图片路径——剪贴板只有图片时不走超类插入
// 文本，改为挂到附件 chip（与相册/文件同一管线）；图文并存仍以文本粘贴为优先，
// 保持常规粘贴行为不变。
@interface DXAIInputTextView : UITextView
@property (nonatomic, weak) DXAIChatPanelController *panelController;
@end

@implementation DXAIInputTextView

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(paste:)) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        return pasteboard.hasStrings || pasteboard.hasImages;
    }
    return [super canPerformAction:action withSender:sender];
}

- (void)paste:(id)sender {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    if (pasteboard.hasImages && !pasteboard.hasStrings) {
        UIImage *image = pasteboard.image;
        if (image) {
            [self.panelController updateAttachedImage:image];
            return;
        }
    }
    [super paste:sender];
}

@end

@implementation DXAIChatPanelController

- (instancetype)init {
    if ((self = [super init])) {
        self.messages = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.view.layer.cornerRadius = 24.0;
    self.view.layer.shadowColor = [UIColor blackColor].CGColor;
    self.view.layer.shadowOpacity = 0.18;
    self.view.layer.shadowRadius = 18.0;
    self.view.layer.shadowOffset = CGSizeMake(0, 5);

    // ── header ──
    self.headerView = [[UIView alloc] init];
    [self.view addSubview:self.headerView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = DXAILocalized(@"AI_CARD_TITLE");
    self.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [UIColor labelColor];
    [self.headerView addSubview:self.titleLabel];

    self.modelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.modelButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.modelButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    [self.modelButton setTitleColor:DXAIAccent() forState:UIControlStateNormal];
    [self.modelButton addTarget:self action:@selector(modelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.modelButton];

    self.personaButton = [DXAIChatPanelController circleButtonWithSymbol:@"person.circle" action:@selector(personaTapped) target:self];
    self.closeButton = [DXAIChatPanelController circleButtonWithSymbol:@"xmark" action:@selector(closeTapped) target:self];
    [self.headerView addSubview:self.personaButton];
    [self.headerView addSubview:self.closeButton];

    self.headerDivider = [[UIView alloc] init];
    self.headerDivider.backgroundColor = [UIColor separatorColor];
    [self.view addSubview:self.headerDivider];

    // ── 会话流 ──
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.hidden = YES;
    self.table.estimatedRowHeight = 80.0;
    self.table.rowHeight = UITableViewAutomaticDimension;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone;
    [self.table registerClass:[DXAIUserBubbleCell class] forCellReuseIdentifier:@"user"];
    [self.table registerClass:[DXAIAssistantBubbleCell class] forCellReuseIdentifier:@"assistant"];
    [self.view addSubview:self.table];

    // ── 输入栏 ──
    self.inputBar = [[UIView alloc] init];
    [self.view addSubview:self.inputBar];

    self.chipContainer = [[UIView alloc] init];
    self.chipContainer.backgroundColor = [UIColor tertiarySystemFillColor];
    self.chipContainer.layer.cornerRadius = 12.0;
    self.chipContainer.hidden = YES;
    [self.inputBar addSubview:self.chipContainer];

    self.chipThumb = [[UIImageView alloc] init];
    self.chipThumb.contentMode = UIViewContentModeScaleAspectFill;
    self.chipThumb.clipsToBounds = YES;
    self.chipThumb.layer.cornerRadius = 8.0;
    self.chipThumb.tintColor = DXAIAccent();
    [self.chipContainer addSubview:self.chipThumb];

    self.chipNameLabel = [[UILabel alloc] init];
    self.chipNameLabel.font = [UIFont systemFontOfSize:14.0];
    self.chipNameLabel.textColor = [UIColor labelColor];
    [self.chipContainer addSubview:self.chipNameLabel];

    self.chipRemoveButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.chipRemoveButton setImage:DXAISymbol(@"xmark.circle.fill", 20, UIImageSymbolWeightRegular) forState:UIControlStateNormal];
    self.chipRemoveButton.tintColor = [UIColor secondaryLabelColor];
    [self.chipRemoveButton addTarget:self action:@selector(chipRemoveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.chipContainer addSubview:self.chipRemoveButton];

    self.fieldContainer = [[UIView alloc] init];
    self.fieldContainer.backgroundColor = [UIColor tertiarySystemFillColor];
    self.fieldContainer.layer.cornerRadius = 20.0;
    [self.inputBar addSubview:self.fieldContainer];

    self.inputField = [[DXAIInputTextView alloc] init];
    ((DXAIInputTextView *)self.inputField).panelController = self;
    self.inputField.backgroundColor = UIColor.clearColor;
    self.inputField.font = [UIFont systemFontOfSize:16.0];
    self.inputField.textColor = [UIColor labelColor];
    self.inputField.tintColor = DXAIAccent();
    self.inputField.textContainerInset = UIEdgeInsetsZero;
    self.inputField.scrollIndicatorInsets = UIEdgeInsetsZero;
    self.inputField.delegate = self;
    [self.fieldContainer addSubview:self.inputField];

    self.placeholderLabel = [[UILabel alloc] init];
    self.placeholderLabel.text = DXAILocalized(@"AI_CARD_PLACEHOLDER");
    self.placeholderLabel.font = [UIFont systemFontOfSize:16.0];
    self.placeholderLabel.textColor = [UIColor placeholderTextColor];
    self.placeholderLabel.userInteractionEnabled = NO;
    [self.fieldContainer addSubview:self.placeholderLabel];

    self.plusButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.plusButton.backgroundColor = DXAIAccent();
    self.plusButton.layer.cornerRadius = 23.0;
    self.plusButton.tintColor = UIColor.whiteColor;
    [self.plusButton setImage:DXAISymbol(@"plus", 20, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    [self.plusButton addTarget:self action:@selector(plusTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.plusButton];

    self.sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.sendButton.backgroundColor = DXAIAccent();
    self.sendButton.layer.cornerRadius = 23.0;
    self.sendButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    [self.sendButton setTitle:DXAILocalized(@"AI_CARD_SEND") forState:UIControlStateNormal];
    [self.sendButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.sendButton];

    // 键盘 frame 的跟踪与卡片跟随由进程级观察者负责（DXAIInstallKeyboardFrameTracking，
    // +load 时注册一次），面板会话反复开关不再叠加观察者。

    [self applySeedText];
    [self refreshModelButton];
    [self refreshChip];
    [self updatePlaceholder];
    [self updateSendState];
}

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width <= 0.0 || height <= 0.0) return;

    [self layoutHeaderWithWidth:width];
    self.headerView.frame = CGRectMake(0, 0, width, 56.0);
    self.headerDivider.frame = CGRectMake(0, 55.5, width, 0.5);

    CGFloat inputBarHeight = [self inputBarHeightForWidth:width];
    BOOL imageVisible = self.attachedImage != nil;
    BOOL fileVisible = self.pendingFileText.length > 0;
    BOOL chipVisible = imageVisible || fileVisible;
    CGFloat sidePad = 14.0, gap = 8.0, plusSize = 46.0, sendWidth = 74.0;
    CGFloat fieldWidth = width - sidePad * 2 - plusSize - gap * 2 - sendWidth;
    // 图片采用大圆角预览区；文本文件仍使用紧凑横条并显示文件名。
    CGFloat chipBlockHeight = imageVisible ? 124.0 : (fileVisible ? 66.0 : 0.0);
    CGFloat fieldRowHeight = inputBarHeight - chipBlockHeight - 8.0;

    self.inputBar.frame = CGRectMake(0, height - inputBarHeight, width, inputBarHeight);
    self.table.frame = CGRectMake(0, 56.0, width, MAX(0.0, height - 56.0 - inputBarHeight));
    self.table.contentInset = UIEdgeInsetsMake(0, 0, 6, 0);

    CGFloat centerY = chipBlockHeight + fieldRowHeight / 2.0;
    if (chipVisible) {
        CGFloat chipWidth = width - sidePad * 2;
        if (imageVisible) {
            // 图二样式：预览缩略图靠左上，关闭按钮叠在缩略图右上角。
            self.chipContainer.frame = CGRectMake(sidePad, 4.0, chipWidth, 112.0);
            self.chipThumb.frame = CGRectMake(12.0, 12.0, 76.0, 76.0);
            self.chipNameLabel.frame = CGRectZero;
            self.chipRemoveButton.frame = CGRectMake(56.0, 12.0, 32.0, 32.0);
        } else {
            self.chipContainer.frame = CGRectMake(sidePad, 4.0, chipWidth, 56.0);
            self.chipThumb.frame = CGRectMake(4.0, 4.0, 48.0, 48.0);
            self.chipNameLabel.frame = CGRectMake(60.0, 0.0, chipWidth - 94.0, 56.0);
            self.chipRemoveButton.frame = CGRectMake(chipWidth - 30.0, 17.0, 22.0, 22.0);
        }
    }
    self.fieldContainer.frame = CGRectMake(sidePad, chipBlockHeight, fieldWidth, fieldRowHeight);
    self.inputField.frame = CGRectMake(12, 8, fieldWidth - 24, fieldRowHeight - 16);
    self.placeholderLabel.frame = CGRectMake(20, 8, fieldWidth - 40, fieldRowHeight - 16);
    self.plusButton.frame = CGRectMake(sidePad + fieldWidth + gap, centerY - plusSize / 2.0, plusSize, plusSize);
    self.sendButton.frame = CGRectMake(sidePad + fieldWidth + gap + plusSize + gap, centerY - 23.0, sendWidth, 46.0);
}

// 输入栏总高度（图片预览/文件横条 + 自适应输入框 + 底边距），布局与卡片高度计算共用。
- (CGFloat)inputBarHeightForWidth:(CGFloat)width {
    BOOL hasImage = self.attachedImage != nil;
    BOOL hasFile = self.pendingFileText.length > 0;
    CGFloat sidePad = 14.0, gap = 8.0, plusSize = 46.0, sendWidth = 74.0;
    CGFloat fieldWidth = width - sidePad * 2 - plusSize - gap * 2 - sendWidth;
    CGFloat textHeight = [self.inputField sizeThatFits:CGSizeMake(fieldWidth - 24.0, CGFLOAT_MAX)].height;
    textHeight = MIN(MAX(textHeight, 30.0), 110.0);
    CGFloat attachmentHeight = hasImage ? 124.0 : (hasFile ? 66.0 : 0.0);
    return attachmentHeight + textHeight + 16.0 + 8.0;
}

- (void)layoutHeaderWithWidth:(CGFloat)width {
    CGFloat buttonSize = 34.0, gap = 10.0, rightEdge = width - 14.0;
    for (UIButton *button in @[self.closeButton, self.personaButton]) {
        button.frame = CGRectMake(rightEdge - buttonSize, 11.0, buttonSize, buttonSize);
        rightEdge -= (buttonSize + gap);
    }

    CGFloat titleWidth = [self.titleLabel.text sizeWithAttributes:@{NSFontAttributeName: self.titleLabel.font}].width;
    self.titleLabel.frame = CGRectMake(20.0, 0.0, ceil(titleWidth), 56.0);

    NSString *modelTitle = self.modelButton.currentTitle ?: @"";
    CGFloat modelWidth = ceil([modelTitle sizeWithAttributes:@{NSFontAttributeName: self.modelButton.titleLabel.font}].width) + 8.0;
    self.modelButton.frame = CGRectMake(20.0 + titleWidth + 10.0, 0.0, modelWidth, 56.0);
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        self.pinnedAfterKeyboardHide = NO; // 转屏几何全变，钉扎解除按新尺寸落位
        [self repositionAnimated:NO];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // 新宽度下表格 contentSize 需要重排一次才准，转场结束后再校一遍高度。
        [self repositionAnimated:NO];
    }];
}

// 面板锚定：紧凑悬浮卡片（四周留边、四角圆角），ShellX 式的常驻会话窗——
// 不再完全贴内容：有最低高度（0.45 屏），会话区始终是一整块可滚动视口；
// 内容变高时跟着长，上限为键盘上方全部空间（无键盘时 0.8 屏）。键盘可见时
// 贴在键盘上方；键盘收起时分两种：会话无输出→随键盘一起关闭（hideIfEmpty），
// 有输出（执行中或已有消息）→钉在键盘上方原位不动，不跟着键盘下坠。
// 转屏时解除钉扎按新几何重新落位。
- (void)repositionAnimated:(BOOL)animated {
    [self dismissPopover]; // 弹层挂在窗口层、锚定旧卡片位置，卡片一动就收起
    UIWindow *window = self.view.window;
    if (!window) return;
    CGRect screen = window.bounds;
    CGRect keyboardFrame = (!CGRectIsEmpty(g_dxKeyboardFrame) || g_dxKeyboardFrame.origin.y > 0)
        ? g_dxKeyboardFrame : DXAIProbeKeyboardFrame();
    if (CGRectIsNull(keyboardFrame)) keyboardFrame = CGRectZero;

    BOOL keyboardVisible = keyboardFrame.origin.y > 0 && keyboardFrame.origin.y < CGRectGetHeight(screen) - 10.0;
    BOOL hasOutput = self.messages.count > 0 || self.streaming;
    if (keyboardVisible) {
        self.pinnedAfterKeyboardHide = NO; // 键盘回来了：恢复贴键盘上方
    } else if (self.pinnedAfterKeyboardHide && hasOutput && !CGRectIsEmpty(self.view.frame)) {
        [self.view setNeedsLayout]; // 卡片框不动，内部输入栏仍随内容重排
        return; // 键盘收起且有输出：保持当前位置（流式内容在卡片内滚动）
    }
    CGFloat keyboardTop = keyboardVisible ? keyboardFrame.origin.y : CGRectGetHeight(screen);
    CGFloat topInset = window.safeAreaInsets.top + 6.0;

    CGFloat leftPad = MAX(16.0, window.safeAreaInsets.left + 8.0);
    CGFloat rightPad = MAX(16.0, window.safeAreaInsets.right + 8.0);
    CGFloat cardWidth = CGRectGetWidth(screen) - leftPad - rightPad;

    CGFloat inputBarHeight = [self inputBarHeightForWidth:cardWidth];
    CGFloat contentHeight = 56.0 + inputBarHeight;
    if (self.messages.count > 0) {
        [self.table layoutIfNeeded]; // 先让表格按当前宽度算出新 contentSize
        contentHeight += self.table.contentSize.height + 6.0;
    }
    CGFloat maxHeight = keyboardVisible ? (keyboardTop - topInset)
                                        : CGRectGetHeight(screen) * 0.80;
    // 初始（无输出）高度取原 0.45 屏的一半：空窗口只露 header+输入栏即可，
    // 不必占半屏；有对话输出后卡片随 contentHeight 动态拉伸（上限仍是键盘
    // 上方全部空间 / 无键盘 0.8 屏）。
    CGFloat minHeight = MIN(CGRectGetHeight(screen) * 0.225, maxHeight);
    CGFloat cardHeight = MIN(MAX(contentHeight, minHeight), maxHeight);
    cardHeight = MAX(cardHeight, 110.0);

    CGRect cardFrame;
    if (keyboardVisible) {
        cardFrame = CGRectMake(leftPad, keyboardTop - 10.0 - cardHeight, cardWidth, cardHeight);
    } else {
        CGFloat centerY = CGRectGetHeight(screen) * 0.75;
        CGFloat bottomInset = window.safeAreaInsets.bottom + 8.0;
        CGFloat minCenter = topInset + cardHeight / 2.0;
        CGFloat maxCenter = MAX(CGRectGetHeight(screen) - bottomInset - cardHeight / 2.0, minCenter);
        centerY = MIN(MAX(centerY, minCenter), maxCenter);
        cardFrame = CGRectMake(leftPad, centerY - cardHeight / 2.0, cardWidth, cardHeight);
    }

    if (animated) {
        [UIView animateWithDuration:0.22 animations:^{
            self.view.frame = cardFrame;
        }];
    } else {
        self.view.frame = cardFrame;
    }
    [self.view setNeedsLayout];
}

#pragma mark - 种子 / 状态刷新

- (void)applySeedText {
    // ensurePanelController 只把控制器挂到 window，入口第一次调用本方法时
    // viewDidLoad 还没发生、inputField 尚未创建。此时必须保留 seedText，等
    // viewDidLoad 创建完输入框后再次调用并消费；否则首次打开 AI 面板会丢掉
    // 宿主输入框全文。已加载的面板仍在入口处立即更新。
    if (!self.isViewLoaded || !self.inputField) return;

    NSString *seed = self.seedText;
    self.seedText = nil;
    if (seed.length == 0) return;
    // 不限全新会话：用户随时可能回宿主改完文字再点 AI 按钮，非空即带入；
    // 输入框已是同值则不动（重复点击 AI 按钮不白白触发刷新）。
    if ([self.inputField.text isEqualToString:seed]) return;
    self.inputField.text = seed;
}

- (void)refreshModelButton {
    DXAIEngineInfo *engine = [self currentEngine];
    NSString *model = [DXAIEngine selectedModelForEngine:engine];
    [self.modelButton setTitle:[NSString stringWithFormat:@"%@  ▾", model ?: @""] forState:UIControlStateNormal];
    [self.view setNeedsLayout];
}

- (void)updatePlaceholder {
    self.placeholderLabel.hidden = self.inputField.text.length > 0;
}

- (void)updateSendState {
    NSString *question = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL hasContent = question.length > 0 || self.attachedImage != nil || self.pendingFileText.length > 0;
    BOOL enabled = hasContent || self.streaming;
    self.sendButton.enabled = enabled;
    self.sendButton.alpha = enabled ? 1.0 : 0.45;
    [self.sendButton setTitle:DXAILocalized(self.streaming ? @"AI_CARD_STOP" : @"AI_CARD_SEND")
                     forState:UIControlStateNormal];
}

- (void)refreshSendButton {
    [self updateSendState];
}

- (void)refreshChip {
    BOOL hasImage = self.attachedImage != nil;
    BOOL hasFile = self.pendingFileText.length > 0;
    self.chipContainer.hidden = !(hasImage || hasFile);
    if (hasImage) {
        self.chipContainer.layer.cornerRadius = 22.0;
        self.chipThumb.image = self.attachedImage;
        self.chipThumb.contentMode = UIViewContentModeScaleAspectFill;
        self.chipThumb.layer.cornerRadius = 14.0;
        self.chipNameLabel.hidden = YES;
        self.chipNameLabel.text = nil;
        self.chipRemoveButton.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.78];
        self.chipRemoveButton.layer.cornerRadius = 16.0;
        self.chipRemoveButton.tintColor = UIColor.whiteColor;
        [self.chipRemoveButton setImage:DXAISymbol(@"xmark", 15.0, UIImageSymbolWeightBold)
                               forState:UIControlStateNormal];
    } else if (hasFile) {
        self.chipContainer.layer.cornerRadius = 12.0;
        self.chipThumb.image = DXAISymbol(@"doc.text", 22, UIImageSymbolWeightMedium);
        self.chipThumb.contentMode = UIViewContentModeCenter;
        self.chipThumb.layer.cornerRadius = 8.0;
        self.chipNameLabel.hidden = NO;
        self.chipNameLabel.text = self.pendingFileName ?: DXAILocalized(@"AI_CARD_FILES");
        self.chipRemoveButton.backgroundColor = UIColor.clearColor;
        self.chipRemoveButton.layer.cornerRadius = 0.0;
        self.chipRemoveButton.tintColor = [UIColor secondaryLabelColor];
        [self.chipRemoveButton setImage:DXAISymbol(@"xmark.circle.fill", 20.0, UIImageSymbolWeightRegular)
                               forState:UIControlStateNormal];
    }
    [self.view setNeedsLayout];
    [self repositionAnimated:NO]; // chip 显隐改变输入栏高度，卡片跟随
    [self updateSendState];
}

- (void)updateAttachedImage:(UIImage *)image {
    self.attachedImage = image;
    if (image) { // 单附件槽：图片与文件互斥，后选替换先选
        self.pendingFileText = nil;
        self.pendingFileName = nil;
    }
    [self refreshChip];
}

- (void)chipRemoveTapped {
    self.attachedImage = nil;
    self.pendingFileText = nil;
    self.pendingFileName = nil;
    [self refreshChip];
}

- (DXAIEngineInfo *)currentEngine {
    return [DXAIEngine currentEngine];
}

#pragma mark - 输入

- (void)textViewDidChange:(UITextView *)textView {
    [self inputFieldTextChanged];
}

// 用户点输入框＝面板窗口接管 key（UIKit 随 becomeFirstResponder 自动提 key），
// 宿主输入会话同样要先 resign 一次、触发"自导的"键盘 hide——与 SB 入口的
// 打开聚焦同款。shouldBeginEditing 在焦点机制动手前被调用，正好在这里置
// 过渡标志防空面板被误关；聚焦落定由 textViewDidBeginEditing 解除，0.8s
// 兜底防极端落空后永久抑制（时限同 DXAIScheduleInputFocus）。
- (BOOL)textViewShouldBeginEditing:(UITextView *)textView {
    if (textView != self.inputField) return YES;
    self.openingFocusTransition = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.inputField.isFirstResponder) return;
        strongSelf.openingFocusTransition = NO;
    });
    return YES;
}

// 焦点落进面板输入框＝抢焦点过渡结束：此后发生的键盘收起都是真实的
// 用户收起，空判关闭与重定位恢复常态。
- (void)textViewDidBeginEditing:(UITextView *)textView {
    if (textView != self.inputField) return;
    self.openingFocusTransition = NO;
    self.presentingAttachmentPicker = NO; // 能重新聚焦输入框，全屏选择器必然已不在
}

- (void)inputFieldTextChanged {
    [self updatePlaceholder];
    [self updateSendState];
    [self repositionAnimated:NO]; // 多行输入撑高输入栏时卡片跟随
}

// 恢复宿主输入：直接让打开面板前保存的宿主输入框接替第一响应者。不要先让
// AI 输入框 resign——那会明确启动一次键盘收起动画，随后宿主重新激活又弹起，
// 微信里就表现为关闭面板时键盘下坠再回弹。两次切换放在同一事件周期，UIKit
// 只更新输入目标而保持键盘在屏幕上。保存的响应者失效时再走旧的键盘兜底。
- (void)restoreHostFocus {
    if (!self.inputField.isFirstResponder) return;
    self.openingFocusTransition = YES; // 抑制跨窗口切换期间的 keyboard-hide 联动

    UIWindow *hostWindow = self.hostKeyWindow;
    if (hostWindow && hostWindow != self.view.window) [hostWindow makeKeyWindow];

    UIResponder *hostResponder = self.hostInputResponder;
    if (hostResponder && hostResponder != self.inputField && [hostResponder becomeFirstResponder]) {
        return;
    }

    // 宿主重建了输入视图等极端场景：退回现有 UIKeyboardImpl 恢复路径。
    [self.inputField resignFirstResponder];
    UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
    [keyboard becomeFirstResponder];
}

// 收尾必须同步完成（ShellX 集成时的教训：关闭链路任何一环异步断裂都会残留
// 全屏窗口，继续参与 hitTest 吞掉宿主触摸）。
- (void)closeTapped {
    [self dismissPopover];
    [self cancelRunningRequest];
    if (self.hostKeyWindow) {
        [self restoreHostFocus]; // 进程内承载：焦点还给宿主输入会话
    } else {
        [self.view.window endEditing:YES]; // SB 承载：确定性收起 SB 键盘
    }
    // 当前 target-action 返回后再拆 rootViewController，避免在按钮事件栈内
    // 释放控制器；焦点切换已在本轮同步完成，不会重新引入键盘收起动画。
    dispatch_async(dispatch_get_main_queue(), ^{
        [DXAIPanel closeAndDestroyPanel];
    });
}

#pragma mark - 聚焦 / 键盘联动

// 打开即聚焦：面板窗口接管 key，光标落进输入框（键盘随之弹出/继续留在面板）。
// 打开瞬间窗口可能刚挂屏（SB plain-init 路径），becomeFirstResponder 偶发落空，
// 由入口处的延迟重试兜底。
- (void)focusInputField {
    UIWindow *window = self.view.window;
    if (!window || window.hidden) return;
    if (!window.isKeyWindow) [window makeKeyWindow];
    if (!self.inputField.isFirstResponder) [self.inputField becomeFirstResponder];
    DXPlaceCaretAtEnd(self.inputField);
}

// 键盘收起联动：会话还没有任何输出（一条消息都没有、也非流式中）时，面板
// 跟着键盘一起消失——空窗口孤零零悬在屏上是纯噪音。有输出（执行中或已有
// 消息）时置钉扎，卡片保持在键盘上方原位，不随键盘下坠重定位。
- (void)hideIfEmptyOnKeyboardHide {
    if (self.openingFocusTransition) return; // 抢焦点自导的键盘 hide，非用户收起
    if (self.presentingAttachmentPicker) return; // 选择器呈现中收键盘是呈现准备，非用户收起
    if (self.messages.count > 0 || self.streaming) {
        self.pinnedAfterKeyboardHide = YES;
        return;
    }
    [DXAIPanel closeAndDestroyPanel];
}

// 长按助手气泡：把回复直接写回宿主 app 的输入框并关闭 AI 窗口——生成结果
// 落位即任务完成，用户不需要再搬运文本。进程内承载（宿主 app/SB 系统键盘）
// 走"复活原输入会话 + UIKeyInput insertText 阶梯"；SB 承载（第三方键盘扩展
// 来源，宿主 app 已退后台）无法直写，退化为复制到剪贴板并延迟关闭。
// 错误提示与正在流式的消息不响应。
- (void)assistantBubbleTappedForMessage:(DXAIMessage *)message {
    if (message.isUser || message.isError || message.streaming) return;
    NSString *text = message.text ?: @"";
    if (text.length == 0) return;
    [self dismissPopover];

    if (self.hostKeyWindow) {
        [self deliverReplyToHostInput:text];
    } else {
        [self deliverReplyViaClipboard:text];
    }
}

// 写回宿主输入：面板让出焦点 → 宿主 key 窗口复位 → UIKeyboardImpl 复活原
// 输入会话（restoreHostFocus 同款链路），稍等会话重建后把回复插到光标处，
// 再销毁面板。插入走 DXCollectionView 验证过的阶梯——delegate 优先
// （UIKeyboardImpl 直插在 iOS 17 上会崩宿主 app），clearTransientState 收尾。
- (void)deliverReplyToHostInput:(NSString *)text {
    if (self.inputField.isFirstResponder) [self.inputField resignFirstResponder];
    UIWindow *hostWindow = self.hostKeyWindow;
    if (hostWindow && hostWindow != self.view.window) [hostWindow makeKeyWindow];
    UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
    if (!keyboard) {
        [self deliverReplyViaClipboard:text];
        return;
    }
    [keyboard becomeFirstResponder];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // 间隔期键盘实例可能被宿主重建，插入前重取 activeInstance
        UIKeyboardImpl *liveKeyboard = [objc_getClass("UIKeyboardImpl") activeInstance] ?: keyboard;
        UIResponder <UITextInput> *input = (UIResponder <UITextInput> *)DXKeyboardInputDelegate(liveKeyboard);
        BOOL delivered = NO;
        if (input && [input respondsToSelector:@selector(insertText:)]) {
            @try {
                [input insertText:text];
                delivered = YES;
            } @catch (__unused NSException *exception) {
                // 落到 keyboard-impl 兜底
            }
        }
        if (!delivered) {
            @try {
                [liveKeyboard insertText:text];
                [liveKeyboard clearTransientState];
                [liveKeyboard clearAnimations];
                [liveKeyboard setCaretBlinks:YES];
            } @catch (__unused NSException *exception) {
                [[UIPasteboard generalPasteboard] setString:text]; // 末级兜底：至少进剪贴板
            }
        }
        [DXAIPanel closeAndDestroyPanel];
    });
}

// SB 承载退化路径：宿主 app 在后台、输入框不可达。复制回复进剪贴板，toast
// 提示后稍作停留再关闭（toast 挂在面板上，立即关用户看不到提示）。
- (void)deliverReplyViaClipboard:(NSString *)text {
    [[UIPasteboard generalPasteboard] setString:text];
    [self showToast:DXAILocalized(@"AI_CARD_REPLY_COPIED")];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.viewIfLoaded.window) {
            [strongSelf.view.window endEditing:YES];
        }
        [DXAIPanel closeAndDestroyPanel];
    });
}

#pragma mark - 会话流

- (void)reloadAll {
    self.table.hidden = self.messages.count == 0;
    [self.table reloadData];
    // 卡片高度随会话内容自适应：先算出新 contentSize 重排卡片，再用新视口定位滚动。
    [self.table layoutIfNeeded];
    [self repositionAnimated:NO];
    [self.view layoutIfNeeded];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (self.messages.count == 0) return;
    NSIndexPath *last = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
    [self.table scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

- (void)sendTapped {
    [self dismissPopover];
    if (self.streaming) {
        [self cancelRunningRequest];
        return;
    }

    NSString *question = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (question.length == 0 && self.attachedImage == nil && self.pendingFileText.length == 0) return;

    DXAIEngineInfo *engine = [self currentEngine];
    if ([DXAIEngine apiKeyForEngine:engine].length == 0) {
        [self appendHintMessage:DXAILocalized(@"AI_CARD_NO_KEY_ALERT")];
        return;
    }
    if ([DXAIEngine selectedModelForEngine:engine].length == 0) {
        [self appendHintMessage:DXAILocalized(@"AI_CARD_NO_MODEL_ALERT")];
        return;
    }

    DXAIMessage *user = [[DXAIMessage alloc] init];
    user.isUser = YES;
    if (self.attachedImage) {
        user.image = self.attachedImage;
        user.imageDataURL = DXAIDataURLForImage(self.attachedImage);
    }
    NSMutableString *content = [NSMutableString string];
    if (self.pendingFileText.length > 0) {
        [content appendFormat:@"【%@】\n%@\n\n", self.pendingFileName ?: DXAILocalized(@"AI_CARD_FILES"), self.pendingFileText];
    }
    if (question.length > 0) [content appendString:question];
    user.text = content;

    DXAIMessage *assistant = [[DXAIMessage alloc] init];
    assistant.isUser = NO;
    assistant.streaming = YES;

    [self.messages addObject:user];
    [self.messages addObject:assistant];

    self.inputField.text = @"";
    self.attachedImage = nil;
    self.pendingFileText = nil;
    self.pendingFileName = nil;

    [self updatePlaceholder];
    [self refreshChip];
    [self updateSendState];
    [self reloadAll];
    [self scrollToBottomAnimated:YES];
    [self startRequestForAssistantMessage:assistant];
}

- (void)startRequestForAssistantMessage:(DXAIMessage *)assistant {
    NSMutableArray *payload = [NSMutableArray array];
    // 人设两级解析：会话内手动选择 → 列表第一项（设置页拖动排序的第一位
    // 即默认人设）。
    NSDictionary *persona = [DXAIEngine personaForID:self.activePersonaID];
    if (!persona) persona = [DXAIEngine defaultPersona];
    NSString *personaText = [persona isKindOfClass:[NSDictionary class]] ? persona[@"content"] : nil;
    if (![personaText isKindOfClass:[NSString class]] || personaText.length == 0) {
        personaText = @"你是AI问答助手：先给结论，再给细节；简洁、准确、不编造。";
    }
    [payload addObject:@{@"role": @"system", @"content": personaText}];

    // 末尾的 assistant 消息是正在生成的这条，不进入请求历史。
    NSArray *history = [self.messages subarrayWithRange:NSMakeRange(0, self.messages.count - 1)];
    if (history.count > 40) history = [history subarrayWithRange:NSMakeRange(history.count - 40, 40)];
    for (DXAIMessage *message in history) {
        if (message.isError) continue; // 本地提示（未配置 Key 等），不是模型说过的话
        if (message.imageDataURL.length > 0) {
            [payload addObject:@{@"role": @"user", @"content": @[
                @{@"type": @"text", @"text": message.text ?: @""},
                @{@"type": @"image_url", @"image_url": @{@"url": message.imageDataURL}}]}];
        } else if (message.text.length > 0) {
            [payload addObject:@{@"role": message.isUser ? @"user" : @"assistant", @"content": message.text}];
        }
    }

    self.streaming = YES;
    [self updateSendState];

    __weak typeof(self) weakSelf = self;
    self.currentRequest = [DXAIEngine sendChatWithMessages:payload
                                                    engine:[self currentEngine]
                                                  onDelta:^(NSString *piece) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            assistant.text = [(assistant.text ?: @"") stringByAppendingString:piece];
            [strongSelf scheduleStreamFlush];
        });
    }
                                                 onDone:^(NSString *fullText, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf finishStreamingForMessage:assistant fullText:fullText error:error];
        });
    }];
}

- (void)scheduleStreamFlush {
    if (self.flushScheduled) return;
    self.flushScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.messages.count == 0) return;
        strongSelf.flushScheduled = NO;
        NSIndexPath *last = [NSIndexPath indexPathForRow:strongSelf.messages.count - 1 inSection:0];
        BOOL lastVisible = [strongSelf.table.indexPathsForVisibleRows containsObject:last];
        [strongSelf.table beginUpdates];
        [strongSelf.table reloadRowsAtIndexPaths:@[last] withRowAnimation:UITableViewRowAnimationNone];
        [strongSelf.table endUpdates];
        [strongSelf.table layoutIfNeeded];
        [strongSelf repositionAnimated:NO]; // 流式变长时卡片高度跟随（到封顶为止）
        if (lastVisible) [strongSelf scrollToBottomAnimated:NO];
    });
}

- (void)finishStreamingForMessage:(DXAIMessage *)assistant fullText:(NSString *)fullText error:(NSError *)error {
    assistant.streaming = NO;
    self.streaming = NO;
    self.currentRequest = nil;
    if (error && error.code != NSURLErrorCancelled) {
        assistant.isError = YES;
        assistant.text = error.localizedDescription.length > 0 ? error.localizedDescription
                                                              : DXAILocalized(@"AI_CARD_REQUEST_FAILED");
    } else {
        // 成功与手动停止都保留已收到的内容。
        assistant.text = fullText ?: @"";
    }
    [self updateSendState];
    [self reloadAll];
    [self scrollToBottomAnimated:YES];
}

- (void)cancelRunningRequest {
    if (self.currentRequest) {
        [self.currentRequest cancel];
        self.currentRequest = nil;
    }
    self.streaming = NO;
    DXAIMessage *last = self.messages.lastObject;
    if (last && !last.isUser) last.streaming = NO;
    [self updateSendState];
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DXAIMessage *message = self.messages[indexPath.row];
    if (message.isUser) {
        DXAIUserBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"user" forIndexPath:indexPath];
        [cell configureWithMessage:message];
        return cell;
    }
    DXAIAssistantBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"assistant" forIndexPath:indexPath];
    [cell configureWithMessage:message];
    __weak typeof(self) weakSelf = self;
    void (^deliver)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf assistantBubbleTappedForMessage:message];
    };
    // 长按气泡写回宿主输入框（SB 承载退化为复制+toast）并关闭面板；流式/错误
    // 消息由 assistantBubbleTappedForMessage 内部把关
    cell.pressAction = deliver;
    return cell;
}

#pragma mark - 弹层（模型切换 / 附件菜单）

- (void)presentPopover:(UIView *)content {
    [self dismissPopover];
    UIControl *catcher = [[UIControl alloc] init];
    catcher.tag = DXAI_POPOVER_TAG;
    catcher.backgroundColor = UIColor.clearColor;
    [catcher addTarget:self action:@selector(dismissPopover) forControlEvents:UIControlEventTouchUpInside];
    UIWindow *window = self.view.window;
    if (window) {
        // 菜单可能悬出卡片边界（+ 菜单锚在输入栏上缘之上），挂到窗口层并在
        // 窗口坐标系里摆放，DXAIHostWindow 对弹层放行默认命中。
        catcher.frame = window.bounds;
        content.frame = [self.view convertRect:content.frame toView:window];
        [window addSubview:catcher];
    } else {
        catcher.frame = self.view.bounds;
        [self.view addSubview:catcher];
    }
    [catcher addSubview:content];
    self.popoverCatcher = catcher;
}

- (void)dismissPopover {
    [self.popoverCatcher removeFromSuperview];
    self.popoverCatcher = nil;
}

- (void)modelTapped {
    if (self.popoverCatcher) {
        [self dismissPopover];
        return;
    }
    DXAIEngineInfo *engine = [self currentEngine];
    NSArray<NSString *> *models = [DXAIEngine modelsForEngine:engine];
    if (models.count == 0) {
        [self showToast:DXAILocalized(@"AI_CARD_NO_MODEL_ALERT")];
        return;
    }
    NSString *selected = [DXAIEngine selectedModelForEngine:engine];

    CGFloat rowHeight = 36.0;
    CGFloat menuWidth = MIN(280.0, CGRectGetWidth(self.view.bounds) - 40.0);
    // 长模型列表（GPT/claude 全家桶动辄十几行）：上限 460、屏高 2/3 封顶，
    // 并夹在卡片内部（面板初始是紧凑小条，菜单超出卡片下缘会悬到键盘上）；
    // 极矮卡片下保证至少露出 3 行，其余靠 scroll 滚动。
    CGFloat screenCap = CGRectGetHeight(self.view.window.bounds) * 2.0 / 3.0;
    if (screenCap < 280.0) screenCap = 280.0;
    CGFloat available = CGRectGetHeight(self.view.bounds) - 62.0 - 10.0;
    CGFloat menuHeight = MIN(MIN(models.count * rowHeight + 6.0, MIN(460.0, screenCap)), MAX(available, rowHeight * 3.0));
    UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(16.0, 62.0, menuWidth, menuHeight)];
    menu.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    menu.layer.cornerRadius = 14.0;
    menu.layer.shadowColor = [UIColor blackColor].CGColor;
    menu.layer.shadowOpacity = 0.18;
    menu.layer.shadowRadius = 14.0;
    menu.layer.shadowOffset = CGSizeMake(0, 4);

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:menu.bounds];
    scroll.contentSize = CGSizeMake(menuWidth, models.count * rowHeight + 6.0);
    [menu addSubview:scroll];

    for (NSUInteger index = 0; index < models.count; index++) {
        NSString *model = models[index];
        DXAIMenuRow *row = [[DXAIMenuRow alloc] initWithFrame:CGRectMake(0, 3.0 + index * rowHeight, menuWidth, rowHeight)];
        BOOL isSelected = [model isEqualToString:selected];
        row.label.text = model;
        row.label.font = [UIFont systemFontOfSize:15.0 weight:isSelected ? UIFontWeightSemibold : UIFontWeightRegular];
        row.label.textColor = isSelected ? DXAIAccent() : [UIColor labelColor];
        row.tag = index;
        [row addTarget:self action:@selector(modelRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:row];
    }
    [self presentPopover:menu];
}

- (void)modelRowTapped:(UIButton *)sender {
    DXAIEngineInfo *engine = [self currentEngine];
    NSArray<NSString *> *models = [DXAIEngine modelsForEngine:engine];
    if (sender.tag < models.count) {
        [DXAIEngine setSelectedModelForEngine:engine model:models[sender.tag]];
        [self refreshModelButton];
    }
    [self dismissPopover];
}

#pragma mark 人设菜单（框选菜单）

// 人设菜单里可见的人设：enabled 缺省为开（设置页新增人设默认出现在菜单）。
- (NSArray<NSDictionary *> *)menuPersonas {
    NSMutableArray<NSDictionary *> *enabled = [NSMutableArray array];
    for (NSDictionary *persona in [DXAIEngine personas]) {
        if (![persona isKindOfClass:[NSDictionary class]]) continue;
        BOOL isEnabled = YES;
        id enabledValue = persona[@"enabled"];
        if ([enabledValue isKindOfClass:[NSNumber class]]) isEnabled = [enabledValue boolValue];
        if (!isEnabled) continue;
        [enabled addObject:persona];
    }
    return enabled;
}

- (void)personaTapped {
    if (self.popoverCatcher) {
        [self dismissPopover];
        return;
    }
    NSArray<NSDictionary *> *personas = [self menuPersonas];
    if (personas.count == 0) return;
    NSString *activeID = self.activePersonaID ?: [DXAIEngine defaultPersona][@"id"];
    if (![activeID isKindOfClass:[NSString class]]) activeID = @"";

    CGFloat rowHeight = 36.0;
    CGFloat menuWidth = 180.0;
    // 框体收紧并夹在卡片内部：面板初始是紧凑小条，菜单一旦超出卡片下缘
    // 就会悬到键盘/工具栏上。行高缩小，放不下的行靠 menu 里的 scroll 滚动；
    // 极矮卡片下也保证至少露出 3 行。
    CGFloat available = CGRectGetHeight(self.view.bounds) - 62.0 - 10.0;
    CGFloat menuHeight = MIN(MIN(personas.count * rowHeight + 6.0, 260.0), MAX(available, rowHeight * 3.0));
    // 右对齐挂在人设按钮下方（菜单右缘 = 按钮右缘），不遮左上角标题/模型区；
    // 越界时收进卡片 16pt 边距内。
    CGRect anchor = [self.view convertRect:self.personaButton.frame fromView:self.headerView];
    CGFloat menuX = CGRectGetMaxX(anchor) - menuWidth;
    menuX = MIN(MAX(menuX, 16.0), CGRectGetWidth(self.view.bounds) - 16.0 - menuWidth);
    UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(menuX, 62.0, menuWidth, menuHeight)];
    menu.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    menu.layer.cornerRadius = 14.0;
    menu.layer.shadowColor = [UIColor blackColor].CGColor;
    menu.layer.shadowOpacity = 0.18;
    menu.layer.shadowRadius = 14.0;
    menu.layer.shadowOffset = CGSizeMake(0, 4);

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:menu.bounds];
    scroll.contentSize = CGSizeMake(menuWidth, personas.count * rowHeight + 6.0);
    [menu addSubview:scroll];

    for (NSUInteger index = 0; index < personas.count; index++) {
        NSDictionary *persona = personas[index];
        DXAIMenuRow *row = [[DXAIMenuRow alloc] initWithFrame:CGRectMake(0, 3.0 + index * rowHeight, menuWidth, rowHeight)];
        NSString *name = [persona[@"name"] isKindOfClass:[NSString class]] ? persona[@"name"] : @"";
        BOOL isActive = [persona[@"id"] isKindOfClass:[NSString class]] && [persona[@"id"] isEqualToString:activeID];
        row.label.text = name;
        row.label.font = [UIFont systemFontOfSize:15.0 weight:isActive ? UIFontWeightSemibold : UIFontWeightRegular];
        row.label.textColor = isActive ? DXAIAccent() : [UIColor labelColor];
        row.tag = index;
        [row addTarget:self action:@selector(personaRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:row];
    }
    [self presentPopover:menu];
}

- (void)personaRowTapped:(UIControl *)sender {
    [self dismissPopover];
    NSArray<NSDictionary *> *personas = [self menuPersonas];
    if (sender.tag >= personas.count) return;
    NSDictionary *persona = personas[sender.tag];
    NSString *personaID = [persona[@"id"] isKindOfClass:[NSString class]] ? persona[@"id"] : nil;
    self.activePersonaID = personaID;
}

- (void)plusTapped {
    if (self.popoverCatcher) {
        [self dismissPopover];
        return;
    }

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    // 剪贴板入口：有图挂附件 chip、纯文本插到光标处——比输入框长按菜单更
    // 直接的一条粘贴路径（检测 API 不触发 iOS16+ 授权弹窗）。
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    if (pasteboard.hasImages || pasteboard.hasStrings) {
        [items addObject:@{@"title": DXAILocalized(@"PASTE_CHIP_ACTION"),
                           @"symbol": @"doc.on.clipboard",
                           @"action": [NSValue valueWithPointer:@selector(pasteClipboardRowTapped)]}];
    }
    [items addObject:@{@"title": DXAILocalized(@"AI_CARD_PHOTOS"),
                       @"symbol": @"photo.on.rectangle",
                       @"action": [NSValue valueWithPointer:@selector(photosRowTapped)]}];
    // 相机不提供：面板在 SpringBoard 进程承载，SB 的 Info.plist 没有相机用途
    // 描述，UIImagePickerController 相机源一呈现就会杀死 SpringBoard。
    [items addObject:@{@"title": DXAILocalized(@"AI_CARD_FILES"),
                       @"symbol": @"doc",
                       @"action": [NSValue valueWithPointer:@selector(filesRowTapped)]}];

    CGFloat rowHeight = 50.0;
    CGFloat menuWidth = 168.0;
    CGFloat menuHeight = items.count * rowHeight + 8.0;
    // 菜单悬在 + 号正上方（卡片坐标系，presentPopover 里统一换算到窗口）。
    CGRect plusFrame = [self.view convertRect:self.plusButton.frame fromView:self.inputBar];
    CGFloat menuTop = CGRectGetMinY(plusFrame) - menuHeight - 10.0;
    CGFloat menuX = CGRectGetMidX(plusFrame) - menuWidth / 2.0;
    menuX = MAX(10.0, MIN(menuX, CGRectGetWidth(self.view.bounds) - menuWidth - 10.0));
    UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(menuX, menuTop, menuWidth, menuHeight)];
    menu.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    menu.layer.cornerRadius = 14.0;
    menu.layer.shadowColor = [UIColor blackColor].CGColor;
    menu.layer.shadowOpacity = 0.18;
    menu.layer.shadowRadius = 14.0;
    menu.layer.shadowOffset = CGSizeMake(0, 4);

    for (NSUInteger index = 0; index < items.count; index++) {
        NSDictionary *item = items[index];
        DXAIMenuRow *row = [[DXAIMenuRow alloc] initWithFrame:CGRectMake(0, 4.0 + index * rowHeight, menuWidth, rowHeight)];
        row.iconView.image = DXAISymbol(item[@"symbol"], 19, UIImageSymbolWeightMedium);
        row.label.text = item[@"title"];
        SEL action = (SEL)[item[@"action"] pointerValue];
        [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        [menu addSubview:row];
    }
    [self presentPopover:menu];
}

- (void)photosRowTapped {
    [self dismissPopover];
    [self pickPhotos];
}

- (void)filesRowTapped {
    [self dismissPopover];
    [self pickFiles];
}

// 「+」菜单的粘贴行：剪贴板有图直接挂附件 chip（与相册/文件同一管线，读板
// 可能触发 iOS16+ 授权弹窗，自动放行闸门覆盖面板），无图纯文本插到光标处。
- (void)pasteClipboardRowTapped {
    [self dismissPopover];
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    if (pasteboard.hasImages) {
        UIImage *image = pasteboard.image;
        if (image) {
            [self updateAttachedImage:image];
            return;
        }
    }
    NSString *string = pasteboard.string;
    if (string.length == 0) return;
    if (string.length > 20000) string = [string substringToIndex:20000];
    UITextRange *selected = self.inputField.selectedTextRange;
    if (selected) {
        [self.inputField replaceRange:selected withText:string];
    } else {
        self.inputField.text = [(self.inputField.text ?: @"") stringByAppendingString:string];
    }
    [self inputFieldTextChanged];
}

#pragma mark - 附件选择

- (void)presentModalController:(UIViewController *)controller {
    if (!self.view.window) return;
    [self dismissPopover];
    // 先置自导过渡标志再收键盘：WillHide 在 resign 内同步到达，空会话面板
    // 若不豁免会抢在呈现前销毁窗口，选择器永远弹不出来。
    self.presentingAttachmentPicker = YES;
    [self.view.window makeKeyWindow];
    if (self.inputField.isFirstResponder) [self.inputField resignFirstResponder];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)pickPhotos {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentModalController:picker];
}

- (void)takePhoto {
    // 保留给未来 app 内承载场景；SB 进程缺相机用途描述，菜单层已直接隐藏入口。
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) return;
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentModalController:picker];
}

- (void)pickFiles {
    NSArray<UTType *> *types = @[UTTypeImage, UTTypePlainText, UTTypeUTF8PlainText];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    [self presentModalController:picker];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    self.presentingAttachmentPicker = NO; // 取消（下滑）也走这里：空 results 视为结束
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result.itemProvider) return;
    __weak typeof(self) weakSelf = self;
    [result.itemProvider loadObjectOfClass:[UIImage class]
                         completionHandler:^(__kindof NSObject *object, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && [object isKindOfClass:[UIImage class]]) {
                [strongSelf updateAttachedImage:(UIImage *)object];
            }
        });
    }];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    self.presentingAttachmentPicker = NO;
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (image) [self updateAttachedImage:image];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    self.presentingAttachmentPicker = NO;
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    self.presentingAttachmentPicker = NO;
    [controller dismissViewControllerAnimated:YES completion:nil];
    NSURL *url = urls.firstObject;
    if (!url) return;
    [url startAccessingSecurityScopedResource];
    UTType *type = nil;
    [url getResourceValue:&type forKey:NSURLContentTypeKey error:nil];
    if ([type conformsToType:UTTypeImage]) {
        UIImage *image = [UIImage imageWithContentsOfFile:url.path];
        if (image) [self updateAttachedImage:image];
    } else {
        NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
        if (text.length == 0) {
            [self showToast:DXAILocalized(@"AI_CARD_FILE_UNREADABLE")];
        } else {
            if (text.length > 20000) text = [[text substringToIndex:20000] stringByAppendingString:@"\n…"];
            self.pendingFileText = text;
            self.pendingFileName = url.lastPathComponent;
            self.attachedImage = nil;
            [self refreshChip];
        }
    }
    [url stopAccessingSecurityScopedResource];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.presentingAttachmentPicker = NO;
    [controller dismissViewControllerAnimated:YES completion:nil];
}

// 未配置 Key/模型等本地提示：作为一条错误样式的助手消息写进对话流，
// 不打断输入（问题保留在输入框），也不进入后续请求上下文。
- (void)appendHintMessage:(NSString *)text {
    DXAIMessage *hint = [[DXAIMessage alloc] init];
    hint.isUser = NO;
    hint.isError = YES;
    hint.text = text;
    [self.messages addObject:hint];
    [self updateSendState];
    [self reloadAll];
    [self scrollToBottomAnimated:YES];
}

// 非阻塞 toast：挂在卡片顶部居中，2 秒后淡出。
- (void)showToast:(NSString *)text {
    [self.toastView removeFromSuperview];
    UILabel *toast = [[UILabel alloc] init];
    toast.text = text;
    toast.font = [UIFont systemFontOfSize:13.0];
    toast.textColor = UIColor.whiteColor;
    toast.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.numberOfLines = 0;
    toast.layer.cornerRadius = 10.0;
    toast.layer.masksToBounds = YES;
    CGFloat maxWidth = CGRectGetWidth(self.view.bounds) - 60.0;
    if (maxWidth < 120.0) maxWidth = 120.0;
    CGSize fit = [toast sizeThatFits:CGSizeMake(maxWidth - 24.0, CGFLOAT_MAX)];
    toast.frame = CGRectMake(0, 0, MIN(maxWidth, fit.width + 24.0), fit.height + 14.0);
    CGFloat toastY = MIN(92.0, CGRectGetHeight(self.view.bounds) - 44.0);
    toast.center = CGPointMake(CGRectGetMidX(self.view.bounds), MAX(toastY, 40.0));
    toast.alpha = 0.0;
    [self.view addSubview:toast];
    self.toastView = toast;
    [UIView animateWithDuration:0.18 animations:^{ toast.alpha = 1.0; }];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.toastView != toast) return;
        [UIView animateWithDuration:0.25 animations:^{ toast.alpha = 0.0; }
            completion:^(BOOL finished) {
                [toast removeFromSuperview];
                if (strongSelf.toastView == toast) strongSelf.toastView = nil;
            }];
    });
}

+ (UIButton *)circleButtonWithSymbol:(NSString *)symbol action:(SEL)action target:(id)target {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = DXAICircleChrome();
    button.layer.cornerRadius = 17.0;
    button.tintColor = DXAIAccent();
    [button setImage:DXAISymbol(symbol, 15.0, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

+ (DXAIChatPanelController *)liveController {
    if (!g_aiPanelWindow || g_aiPanelWindow.hidden) return nil;
    return (DXAIChatPanelController *)g_aiPanelWindow.rootViewController;
}

@end

#pragma mark - 键盘 frame 跟踪（进程级）

// 进程启动即注册（+load）：键盘 show/frame 变化的通知先于面板首开到达，
// g_dxKeyboardFrame 首帧就有值——这是"第一次弹在屏幕底部、第二次才正确"
// 的根因修复（原来观察者挂在面板 viewDidLoad，首开时键盘早已 show 完）。
// 同一观察者兼管面板随键盘动画重定位，替代原先每会话注册的观察者。
static void DXAIInstallKeyboardFrameTracking(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSOperationQueue *main = [NSOperationQueue mainQueue];
        void (^handler)(NSNotification *) = ^(NSNotification *note) {
            NSValue *value = note.userInfo[UIKeyboardFrameEndUserInfoKey];
            if ([value isKindOfClass:[NSValue class]]) g_dxKeyboardFrame = value.CGRectValue;

            DXAIChatPanelController *controller = [DXAIChatPanelController liveController];
            if (!controller || !controller.viewIfLoaded.window) return;

            // 抢焦点过渡期（SB 开面板即聚焦 / 进程内点输入框接管）：旧会话
            // resign 后键盘为面板重绑，期间的 frame 变化不驱动重定位——卡片
            // 保持在既有位置，焦点落定后的重弹/兜底重定位自然收口。
            if (controller.openingFocusTransition) return;

            // 选择器呈现中同理：resign 引发的 hide 方向 frame 变化不驱动
            // 重定位，避免卡片在转场画面后面坠向悬空位再被选择器盖住。
            if (controller.presentingAttachmentPicker) return;

            // 本次 frame 变化是"键盘收起"且会话有输出：钉在键盘上方原位，
            // 不做随键盘下坠的动画重定位（有输出空判关闭走 WillHide 观察者）。
            CGRect endFrame = CGRectIsNull(g_dxKeyboardFrame) ? CGRectZero : g_dxKeyboardFrame;
            CGFloat screenHeight = CGRectGetHeight(controller.view.window.bounds);
            BOOL keyboardHiding = screenHeight > 0.0 && CGRectGetMinY(endFrame) >= screenHeight - 10.0;
            if (keyboardHiding && (controller.messages.count > 0 || controller.streaming)) {
                controller.pinnedAfterKeyboardHide = YES;
                return;
            }

            NSTimeInterval duration = 0.25;
            NSNumber *durationNumber = note.userInfo[UIKeyboardAnimationDurationUserInfoKey];
            if ([durationNumber isKindOfClass:[NSNumber class]]) duration = durationNumber.doubleValue;
            NSInteger curve = 7; // UIViewAnimationCurveKeyValue 非公开常量的等价值
            NSNumber *curveNumber = note.userInfo[UIKeyboardAnimationCurveUserInfoKey];
            if ([curveNumber isKindOfClass:[NSNumber class]]) curve = curveNumber.integerValue;

            __weak DXAIChatPanelController *weakSelf = controller;
            [UIView animateWithDuration:duration delay:0.0 options:(curve << 16) animations:^{
                [weakSelf repositionAnimated:NO];
            } completion:nil];
        };
        [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillChangeFrameNotification
                                                          object:nil
                                                           queue:main
                                                      usingBlock:handler];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardDidShowNotification
                                                          object:nil
                                                           queue:main
                                                      usingBlock:handler];
        // 键盘收起联动：空会话的面板随键盘一起关闭（有输出则只重定位保留）。
        [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillHideNotification
                                                          object:nil
                                                           queue:main
                                                      usingBlock:^(NSNotification *note) {
            DXAIChatPanelController *controller = [DXAIChatPanelController liveController];
            if (!controller || !controller.viewIfLoaded.window) return;
            [controller hideIfEmptyOnKeyboardHide];
        }];
    });
}

// 打开瞬间的兜底：窗口刚挂屏时个别场景键盘通知还没补发完，延迟再校两次
// 位置；frame 已正确时重定位是幂等的，肉眼无感。
static void DXAISchedulePanelReposition(DXAIChatPanelController *controller) {
    __weak typeof(controller) weakSelf = controller;
    for (NSNumber *delay in @[@0.05, @0.30]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.viewIfLoaded.window) return;
            [strongSelf repositionAnimated:NO];
        });
    }
}

// 聚焦兜底：打开瞬间窗口可能尚未完成挂屏/key 切换，becomeFirstResponder 偶发
// 落空；0.15/0.40s 各重试一次，输入框已持有焦点则静默跳过（不与用户抢焦点）。
static void DXAIScheduleInputFocus(DXAIChatPanelController *controller) {
    __weak typeof(controller) weakSelf = controller;
    [controller focusInputField];
    for (NSNumber *delay in @[@0.15, @0.40]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.viewIfLoaded.window) return;
            if (!strongSelf.inputField.isFirstResponder) [strongSelf focusInputField];
        });
    }
    // 聚焦始终没成功（beginEditing 没机会解除过渡标志）的兜底：0.80s 晚于最后
    // 一次重试，此后真实的键盘收起要恢复"空面板随之关闭"的常态。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.80 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.openingFocusTransition = NO;
    });
}

#pragma mark - 入口

@implementation DXAIPanel

+ (void)load {
    DXAIInstallKeyboardFrameTracking();
}

// 进程内承载（第一版同款）：从活跃键盘/宿主 key 窗口取 windowScene；SB 的窗口
// 是 scene-less 的（ShellX 同款承载方式），找不到 scene 时 plain init 也能正常
// 显示——两种创建路径都落在同一个 g_aiPanelWindow 全局上，会话共用。
+ (DXAIChatPanelController *)ensurePanelController {
    if (g_aiPanelWindow && g_aiPanelWindow.rootViewController) {
        return (DXAIChatPanelController *)g_aiPanelWindow.rootViewController;
    }

    if (g_aiPanelWindow) { // 残窗：连同旧会话一起丢弃
        g_aiPanelWindow.hidden = YES;
        g_aiPanelWindow.rootViewController = nil;
        g_aiPanelWindow = nil;
    }

    DXAIHostWindow *window = nil;
    UIWindowScene *scene = nil;
    UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
    scene = keyboard.window.windowScene;
    if (!scene) scene = DXKeyWindow().windowScene;
    for (UIScene *connected in [UIApplication sharedApplication].connectedScenes) {
        if (!scene && [connected isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)connected;
            break;
        }
    }

    if (scene) {
        window = [[DXAIHostWindow alloc] initWithWindowScene:scene];
        window.frame = scene.coordinateSpace.bounds;
    } else {
        window = [[DXAIHostWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    window.windowLevel = 1000000.0;
    window.backgroundColor = UIColor.clearColor;
    window.hidden = YES;

    DXAIChatPanelController *controller = [[DXAIChatPanelController alloc] init];
    window.rootViewController = controller;
    g_aiPanelWindow = window;
    return controller;
}

// 进程内承载入口（第一版）：点 AI 按钮立即弹出，锚定当前键盘上方。
// 不抢焦点：面板窗口只显示、不接管 key，宿主输入会话原样保留，键盘全程
// 不收不弹。旧方案"打开即聚焦"必须先 makeKeyWindow resign 宿主会话（一次
// 完整的键盘收起动画），再为面板输入框弹回，聚焦落空时还要走 0.15/0.40s
// 重试——观感即"键盘先收起、再弹出、面板最后才落位"。现在光标由用户点
// 输入框时接管（textViewShouldBeginEditing 置过渡标志），键盘只在那一刻
// 换绑输入会话。
+ (void)openFromKeyboardWithSeedText:(NSString *)seedText {
    DXAIChatPanelController *controller = [self ensurePanelController];
    if (!controller) return;

    UIWindow *keyWindow = DXKeyWindow();
    if (keyWindow && keyWindow != g_aiPanelWindow) {
        controller.hostKeyWindow = keyWindow; // 面板已持 key（重开）时不覆盖宿主记录
        // 此时宿主输入框仍是键盘 delegate；必须在用户点进 AI 输入框前保存，
        // 之后 activeInstance 的 delegate 会切成面板自己的 UITextView。
        UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
        UIResponder *hostResponder = DXKeyboardInputDelegate(keyboard);
        if (hostResponder && hostResponder != controller.inputField) {
            controller.hostInputResponder = hostResponder;
        }
    }
    controller.seedText = seedText;
    [controller applySeedText];
    [controller inputFieldTextChanged]; // 种子程序性写入不触发 textViewDidChange，状态手动刷新

    [controller refreshModelButton];

    g_aiPanelWindow.hidden = NO;
    [controller repositionAnimated:NO];
    DXAISchedulePanelReposition(controller);
}

// SB 承载入口：第三方键盘扩展经通道触发。plain-init 窗口必须走
// makeKeyAndVisible 才可靠挂屏（ShellX 同款）。
+ (void)presentInSpringBoardWithSeedText:(NSString *)seedText clipboardImage:(BOOL)clipboardImage {
    DXAIChatPanelController *controller = [self ensurePanelController];
    if (!controller) return;

    // 宿主输入全文非空即带入面板输入框（不限全新会话）；剪贴板图片仅在用户
    // 还没选附件时注入（不覆盖已选附件）。
    controller.hostKeyWindow = nil;
    controller.seedText = seedText;
    [controller applySeedText];
    [controller inputFieldTextChanged]; // 种子程序性写入不触发 textViewDidChange，状态手动刷新
    if (clipboardImage) {
        UIImage *image = [UIPasteboard generalPasteboard].image;
        if (image && !controller.attachedImage) [controller updateAttachedImage:image];
    }
    [controller refreshModelButton];

    g_aiPanelWindow.hidden = NO;
    // 与进程内入口同款：聚焦过渡抑制（SB 路径打开时通常无键盘在弹，置位是
    // 防个别场景键盘先于面板出现的抖动）。
    controller.openingFocusTransition = YES;
    [g_aiPanelWindow makeKeyAndVisible];
    [controller repositionAnimated:NO];
    DXAISchedulePanelReposition(controller);
    DXAIScheduleInputFocus(controller);
}

+ (void)closeAndDestroyPanel {
    if (g_aiPanelWindow) {
        g_aiPanelWindow.hidden = YES;
        g_aiPanelWindow.rootViewController = nil; // 会话销毁，控制器随之释放
        g_aiPanelWindow = nil;
    }
}

+ (BOOL)isPanelInputActive {
    DXAIChatPanelController *controller = [DXAIChatPanelController liveController];
    if (!controller) return NO;
    if (controller.inputField.isFirstResponder) return YES;
    // 面板窗口仍持有 key 也算活跃：粘贴授权弹窗呈现瞬间 first responder 可能
    // 被 alert 抢走，而这次读板正是面板（输入框/+ 菜单）发起的。
    return controller.view.window.isKeyWindow;
}

@end
