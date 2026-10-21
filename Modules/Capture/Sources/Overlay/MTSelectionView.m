#import "MTSelectionView.h"
#import "../Common/MTEditorOrder.h"
#import "../Common/MTCapturePreferences.h"
#import "../Common/MTSelectionToolbar.h"
#import "../Common/MTCaptureLog.h"

static const CGFloat MTSelectionMinimumSize = 44.0;   // 点；过小选区会产出无意义的细条裁剪
static const CGFloat MTHandleHitRadius = 36.0;
// 工具栏与屏幕边缘的常规留白（左右、非区域模式的底部）。
static const CGFloat MTSelectionEdgeMargin = 12.0;
// 区域模式底部留白：实时取景下面板默认贴屏幕底部，12pt 在无 Home 指示条/横屏时
// 视觉上咬住底缘；抬到 24pt 让它明确落在底部区域内，同时不过度侵占选区。
static const CGFloat MTSelectionAreaBottomMargin = 24.0;
// 选区内部起点的把手命中半径：边中把手位于边界中点，若沿用 36pt，
// 任一边 ≤72pt 的小选区内部全部被判成缩放，拖动（Move）永远无法触发。
static const CGFloat MTInteriorHandleBand = 22.0;
// 实时取景底色不能全透明：跨进程触摸抢占按合成内容透明度判定，全透明区域
// 会被窗口服务器跳过、触摸落到前台 App（表现为桌面正常、App 内选区穿透）。
// 取 8% 黑——肉眼不可察觉，但足以让窗口算「有内容」抢到触摸。
static const CGFloat MTLiveAreaClaimAlpha = 0.08;

typedef NS_ENUM(NSInteger, MTSelectionDragMode) {
    MTSelectionDragModeNone = 0,
    MTSelectionDragModeMove = 1,
    MTSelectionDragModeCreate = 2,
    MTSelectionDragModeHandle = 3,
};

@interface MTSelectionView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIImageView *backgroundImageView;
@property (nonatomic, strong) CAShapeLayer *dimLayer;
@property (nonatomic, strong) CAShapeLayer *borderLayer;
@property (nonatomic, strong) NSMutableArray<UIView *> *handles;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UILabel *modeLabel;
@property (nonatomic, strong) MTSelectionToolbar *toolbar;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong, nullable) UITapGestureRecognizer *floatDoubleTap;

@property (nonatomic, assign) CGRect selectionRect;
@property (nonatomic, assign) MTSelectionDragMode dragMode;
@property (nonatomic, assign) NSInteger activeHandleIndex;
@property (nonatomic, assign) CGPoint dragAnchor;
@property (nonatomic, assign) CGRect dragStartRect;
@property (nonatomic, assign) BOOL isInstantMode;
@property (nonatomic, assign) MTCaptureMode mode;
@property (nonatomic, assign) BOOL areaFrameFrozen;
@end

@implementation MTSelectionView

- (instancetype)initWithFrame:(CGRect)frame
                    baseImage:(UIImage *)baseImage
                         mode:(MTCaptureMode)mode
                     delegate:(id<MTSelectionViewDelegate>)delegate {
    if (self = [super initWithFrame:frame]) {
        _delegate = delegate;
        _mode = mode;
        _isInstantMode = (mode == MTCaptureModeInstant);
        _dragMode = MTSelectionDragModeNone;
        [self mtBuildContentWithBaseImage:baseImage];
        // 激活默认空选区：选区只在用户手动框选或「记住上次选区」恢复时出现。
        [self mtUpdateVisuals];
    }
    return self;
}

- (void)dealloc {
    [self prepareForDismissal];
}

#pragma mark - 构建

- (void)mtBuildContentWithBaseImage:(UIImage *)baseImage {
    BOOL liveArea = self.mode == MTCaptureModeArea;
    self.backgroundColor = liveArea
        ? [UIColor colorWithWhite:0.0 alpha:MTLiveAreaClaimAlpha]
        : [UIColor blackColor];

    _backgroundImageView = [[UIImageView alloc] initWithFrame:self.bounds];
    _backgroundImageView.image = liveArea ? nil : baseImage;
    _backgroundImageView.hidden = liveArea;
    _backgroundImageView.contentMode = UIViewContentModeScaleToFill;   // 归一化图与屏幕同比例
    _backgroundImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_backgroundImageView];

    _dimLayer = [CAShapeLayer layer];
    _dimLayer.fillRule = kCAFillRuleEvenOdd;
    _dimLayer.fillColor = [UIColor colorWithWhite:0.0 alpha:0.55].CGColor;
    [self.layer addSublayer:_dimLayer];

    _borderLayer = [CAShapeLayer layer];
    _borderLayer.fillColor = [UIColor clearColor].CGColor;
    _borderLayer.strokeColor = [UIColor whiteColor].CGColor;
    _borderLayer.lineWidth = 1.5;
    [self.layer addSublayer:_borderLayer];

    _handles = [[NSMutableArray alloc] init];
    for (NSInteger i = 0; i < 8; i++) {
        UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 14)];
        handle.backgroundColor = [UIColor whiteColor];
        handle.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:1.0].CGColor;
        handle.layer.borderWidth = 1.0;
        handle.layer.cornerRadius = 7.0;
        handle.userInteractionEnabled = NO;
        [self addSubview:handle];
        [_handles addObject:handle];
    }

    _sizeLabel = [[UILabel alloc] init];
    _sizeLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _sizeLabel.textColor = [UIColor whiteColor];
    _sizeLabel.textAlignment = NSTextAlignmentCenter;
    _sizeLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    _sizeLabel.layer.cornerRadius = 6.0;
    _sizeLabel.clipsToBounds = YES;
    [self addSubview:_sizeLabel];

    _modeLabel = [[UILabel alloc] init];
    _modeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _modeLabel.textColor = [UIColor whiteColor];
    _modeLabel.textAlignment = NSTextAlignmentCenter;
    _modeLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    _modeLabel.layer.cornerRadius = 9.0;
    _modeLabel.clipsToBounds = YES;
    switch (self.mode) {
        case MTCaptureModeFreeze: _modeLabel.text = @"  冻结截图  "; break;
        case MTCaptureModeInstant: _modeLabel.text = @"  即时区域  "; break;
        default: _modeLabel.text = @"  区域截图  "; break;
    }
    [_modeLabel sizeToFit];
    [self addSubview:_modeLabel];

    // 顺序、显隐、外观在打开时取快照；与设置预览共用同一工具栏布局。
    // SHELLX 扩展键只在 SHELLX 在场且总开关打开时出现（即时模式本就不含这些键）。
    NSArray<NSString *> *order = [MTEditorOrder visibleSelectionOrderForOrder:[MTEditorOrder currentSelectionOrder]
                                                                      hidden:[MTEditorOrder currentSelectionHidden]
                                                                     instant:_isInstantMode];
    // 冻结与滚动截图按钮仅区域模式显示；独立冻结/即时入口沿用已有快照交互。
    if (self.mode != MTCaptureModeArea) {
        NSMutableArray<NSString *> *filtered = [order mutableCopy];
        [filtered removeObject:@"long"];
        [filtered removeObject:@"freeze"];
        order = filtered;
    }
    if (![MTShellXBridge toolbarAvailable]) {
        NSMutableArray<NSString *> *withoutShellX = [order mutableCopy];
        [withoutShellX removeObjectsInArray:[MTEditorOrder shellxSelectionIdentifiers]];
        order = withoutShellX;
    }
    MTSelectionButtonStyle style = [MTEditorOrder selectionButtonStyle];
    CGFloat iconPointSize = [MTEditorOrder buttonIconPointSize];
    // 排布在创建时取快照：多排换行是默认，改为滑动后下次打开才按单排滚动。
    _toolbar = [[MTSelectionToolbar alloc] initWithIdentifiers:order style:style
        iconPointSize:iconPointSize arrangement:[MTEditorOrder selectionToolbarArrangement]];
    for (UIButton *button in _toolbar.buttons) {
        [button addTarget:self action:@selector(mtButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    [self addSubview:_toolbar];
    MTCaptureLogInfo(@"selection toolbar built: style=%ld size=%.1f buttons=%lu", (long)style,
              iconPointSize, (unsigned long)order.count);

    _panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mtHandlePan:)];
    _panGesture.delegate = self;
    [self addGestureRecognizer:_panGesture];

    // 双击选区悬浮，与工具栏「悬浮」按钮同一条委托路径；即时模式保持历史行为不参与（工具栏也无此键）。
    if (!_isInstantMode) {
        _floatDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                  action:@selector(mtHandleFloatDoubleTap:)];
        _floatDoubleTap.numberOfTapsRequired = 2;
        _floatDoubleTap.delegate = self;
        [self addGestureRecognizer:_floatDoubleTap];
    }
}

#pragma mark - 选区几何

- (void)applyDefaultSelectionRect:(CGRect)rect {
    self.selectionRect = rect;
    [self mtUpdateVisuals];
}

- (void)applyFrozenImage:(UIImage *)image {
    if (self.mode != MTCaptureModeArea || self.areaFrameFrozen || !image) return;
    self.areaFrameFrozen = YES;
    self.backgroundImageView.image = image;
    self.backgroundImageView.hidden = NO;
    self.backgroundColor = [UIColor blackColor];
    self.modeLabel.text = @"  冻结区域  ";
    for (UIButton *button in self.toolbar.buttons) {
        NSString *identifier = button.accessibilityIdentifier;
        if ([identifier isEqualToString:@"freeze"] || [identifier isEqualToString:@"long"]) {
            button.enabled = NO;
        }
    }
    [self setNeedsLayout];
}

- (void)showFreezeFailure {
    if (self.mode != MTCaptureModeArea || self.areaFrameFrozen) return;
    self.modeLabel.text = @"  冻结失败，请重试  ";
    [self setNeedsLayout];
}

- (void)mtSetSelectionRect:(CGRect)rect {
    CGRect clamped = MTClampSelectionRect(rect, self.bounds.size, MTSelectionMinimumSize);
    if (CGRectEqualToRect(clamped, CGRectZero)) {
        return;   // 太小的中间态直接忽略，保持上一个合法选区
    }
    self.selectionRect = clamped;
    [self mtUpdateVisuals];
}

- (void)mtUpdateVisuals {
    [self mtUpdateToolbarLayout];
    CGRect selection = self.selectionRect;

    UIBezierPath *full = [UIBezierPath bezierPathWithRect:self.bounds];
    [full appendPath:[UIBezierPath bezierPathWithRect:selection]];
    _dimLayer.path = full.CGPath;

    UIBezierPath *border = [UIBezierPath bezierPathWithRect:selection];
    _borderLayer.path = border.CGPath;

    // 角 0-3：左上/右上/右下/左下；边 4-7：上/右/下/左
    CGFloat w = selection.size.width, h = selection.size.height;
    CGFloat x = selection.origin.x, y = selection.origin.y;
    CGPoint centers[8] = {
        CGPointMake(x, y), CGPointMake(x + w, y), CGPointMake(x + w, y + h), CGPointMake(x, y + h),
        CGPointMake(x + w / 2, y), CGPointMake(x + w, y + h / 2), CGPointMake(x + w / 2, y + h), CGPointMake(x, y + h / 2),
    };
    for (NSInteger i = 0; i < 8; i++) {
        UIView *handle = self.handles[i];
        handle.center = centers[i];
        handle.hidden = CGRectIsEmpty(selection);
    }

    CGFloat pixelW = selection.size.width * [UIScreen mainScreen].scale;
    CGFloat pixelH = selection.size.height * [UIScreen mainScreen].scale;
    _sizeLabel.text = [NSString stringWithFormat:@"%.0f × %.0f px", pixelW, pixelH];
    [_sizeLabel sizeToFit];
    _sizeLabel.hidden = CGRectIsEmpty(selection);
    CGRect labelFrame = _sizeLabel.frame;
    labelFrame.origin.x = selection.origin.x + selection.size.width / 2 - labelFrame.size.width / 2 - 8;
    labelFrame.origin.y = selection.origin.y + selection.size.height + 10;
    if (self.mode == MTCaptureModeArea) {
        labelFrame.size.width += 16;
        labelFrame.size.height = fmax(labelFrame.size.height, 20);
        CGFloat labelTopLimit = CGRectGetMaxY(self.modeLabel.frame) + 10.0;
        CGFloat labelBottomLimit = self.bounds.size.height - self.safeAreaInsets.bottom - 10.0;
        BOOL toolbarVisible = !self.toolbar.hidden && !CGRectIsEmpty(self.toolbar.frame);
        BOOL toolbarBelowSelection = toolbarVisible && CGRectGetMinY(self.toolbar.frame) >= CGRectGetMaxY(selection);
        if (CGRectGetMaxY(labelFrame) > labelBottomLimit ||
            (toolbarVisible && CGRectIntersectsRect(labelFrame, self.toolbar.frame))) {
            // 默认位出界或被工具栏占位：工具栏在选框下方时标签排到工具栏下面，
            // 工具栏在选框上方时排到工具栏上面，其余退到选框上方且不越过模式标签。
            CGFloat belowToolbarY = CGRectGetMaxY(self.toolbar.frame) + 10.0;
            CGFloat aboveToolbarY = CGRectGetMinY(self.toolbar.frame) - labelFrame.size.height - 10.0;
            CGFloat aboveSelectionY = selection.origin.y - labelFrame.size.height - 10.0;
            if (toolbarBelowSelection && belowToolbarY + labelFrame.size.height <= labelBottomLimit) {
                labelFrame.origin.y = belowToolbarY;
            } else if (toolbarVisible &&
                       CGRectGetMaxY(self.toolbar.frame) <= CGRectGetMinY(selection) &&
                       aboveToolbarY >= labelTopLimit) {
                labelFrame.origin.y = aboveToolbarY;
            } else {
                labelFrame.origin.y = MAX(aboveSelectionY, labelTopLimit);
            }
        }
    } else {
        CGFloat labelBottomLimit = CGRectIsEmpty(self.toolbar.frame) ? self.bounds.size.height - 70.0
                                                                   : CGRectGetMinY(self.toolbar.frame) - 10.0;
        if (CGRectGetMaxY(labelFrame) > labelBottomLimit) {
            labelFrame.origin.y = selection.origin.y - labelFrame.size.height - 10;
        }
        labelFrame.size.width += 16;
        labelFrame.size.height = fmax(labelFrame.size.height, 20);
    }
    _sizeLabel.frame = CGRectIntegral(labelFrame);
}

- (void)mtUpdateToolbarLayout {
    BOOL areaMode = self.mode == MTCaptureModeArea;
    self.toolbar.hidden = areaMode && self.dragMode != MTSelectionDragModeNone;
    if (self.toolbar.hidden) return;  // 拖动过程不抢占触摸，也不反复移动隐藏的面板。

    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat left = areaMode ? safe.left + MTSelectionEdgeMargin : MTSelectionEdgeMargin;
    CGFloat right = areaMode ? safe.right + MTSelectionEdgeMargin : MTSelectionEdgeMargin;
    // 底部留白只在区域模式加厚：冻结/即时等模式的站位维持历史数值。
    CGFloat bottomMargin = areaMode ? MTSelectionAreaBottomMargin : MTSelectionEdgeMargin;
    CGFloat availableWidth = MAX(0.0, self.bounds.size.width - left - right);
    CGFloat toolbarWidth = [self.toolbar preferredWidthForAvailableWidth:availableWidth];
    CGFloat toolbarHeight = [self.toolbar preferredHeightForAvailableWidth:toolbarWidth];
    CGRect preferred = CGRectMake(left + (availableWidth - toolbarWidth) / 2.0,
                                  self.bounds.size.height - safe.bottom - bottomMargin - toolbarHeight,
                                  toolbarWidth, toolbarHeight);
    CGRect frame = preferred;
    if (areaMode) {
        CGFloat top = MAX(safe.top + MTSelectionEdgeMargin, CGRectGetMaxY(self.modeLabel.frame) + MTSelectionEdgeMargin);
        CGRect available = CGRectMake(left, top, availableWidth,
                                      MAX(0.0, self.bounds.size.height - safe.bottom - bottomMargin - top));
        frame = MTPlaceSelectionToolbar(preferred, self.selectionRect, available, 16.0);
        if (!CGRectEqualToRect(frame, preferred)) {
            // 几何层确实做了避让（全屏/近全屏时本应回退到底部而不发生）：
            // 把关键数值落日志，便于设备侧确认实际走的是哪条分支。
            MTCaptureLogInfo(@"selection toolbar relocated: bounds=(%.0f,%.0f) available=(%.0f,%.0f,%.0f,%.0f) selection=(%.0f,%.0f,%.0f,%.0f) frame=(%.0f,%.0f,%.0f,%.0f)",
                      self.bounds.size.width, self.bounds.size.height,
                      available.origin.x, available.origin.y, available.size.width, available.size.height,
                      self.selectionRect.origin.x, self.selectionRect.origin.y,
                      self.selectionRect.size.width, self.selectionRect.size.height,
                      frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
        }
    }
    self.toolbar.frame = frame;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGSize modeTextSize = [_modeLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 28.0)];
    CGFloat modeLabelWidth = modeTextSize.width + 16.0;
    _modeLabel.frame = CGRectMake((self.bounds.size.width - modeLabelWidth) / 2.0,
                                  self.safeAreaInsets.top + 10.0,
                                  modeLabelWidth,
                                  28.0);

    if (!CGRectIsEmpty(self.selectionRect)) {
        CGRect clamped = MTClampSelectionRect(self.selectionRect, self.bounds.size, MTSelectionMinimumSize);
        if (!CGRectEqualToRect(clamped, CGRectZero) && !CGRectEqualToRect(clamped, self.selectionRect)) {
            self.selectionRect = clamped;
        }
    }
    [self mtUpdateVisuals];
    [self bringSubviewToFront:self.modeLabel];
    [self bringSubviewToFront:self.toolbar];
}

#pragma mark - 手势

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // 操作栏按钮必须独占触摸，否则轻微手指移动会被选区 pan 取消。
    if ([touch.view isDescendantOfView:self.toolbar]) return NO;
    if (gestureRecognizer == self.floatDoubleTap) {
        // 双击只在选区内部生效：暗区双击不与“拖动新建选区”语义冲突。
        return CGRectContainsPoint(self.selectionRect, [touch locationInView:self]);
    }
    return YES;
}

- (void)mtHandlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self];
    CGPoint translation = [gesture translationInView:self];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            _dragStartRect = self.selectionRect;
            _dragAnchor = location;
            // 空选区时 8 个把手都堆在原点，手柄命中会误判：直接按新建选区处理。
            // 内部起点用窄边带命中把手，其余内部一律按移动；框外起点保留大半径方便抓角。
            CGFloat handleRadius = CGRectContainsPoint(_dragStartRect, location)
                ? MTInteriorHandleBand
                : MTHandleHitRadius;
            NSInteger handleIndex = CGRectIsEmpty(self.selectionRect)
                ? -1
                : [self mtHandleIndexAtPoint:location radius:handleRadius];
            if (handleIndex >= 0) {
                _dragMode = MTSelectionDragModeHandle;
                _activeHandleIndex = handleIndex;
            } else if (CGRectContainsPoint(self.selectionRect, location)) {
                _dragMode = MTSelectionDragModeMove;
            } else {
                _dragMode = MTSelectionDragModeCreate;
            }
            [self mtUpdateToolbarLayout];
            if (self.mode == MTCaptureModeArea) {
                MTCaptureLogInfo(@"selection drag began: kind=%ld rect=(%.0f,%.0f,%.0f,%.0f) at=(%.0f,%.0f) toolbarHidden=%d",
                          (long)_dragMode,
                          _dragStartRect.origin.x, _dragStartRect.origin.y,
                          _dragStartRect.size.width, _dragStartRect.size.height,
                          location.x, location.y, self.toolbar.hidden);
            }
            break;
        }
        case UIGestureRecognizerStateChanged: {
            switch (_dragMode) {
                case MTSelectionDragModeMove: {
                    CGRect rect = _dragStartRect;
                    rect.origin.x += translation.x;
                    rect.origin.y += translation.y;
                    [self mtSetSelectionRect:[self mtSnappedRect:rect]];
                    break;
                }
                case MTSelectionDragModeCreate: {
                    CGRect rect = CGRectMake(MIN(_dragAnchor.x, location.x),
                                             MIN(_dragAnchor.y, location.y),
                                             fabs(location.x - _dragAnchor.x),
                                             fabs(location.y - _dragAnchor.y));
                    [self mtSetSelectionRect:[self mtSnappedRect:rect]];
                    break;
                }
                case MTSelectionDragModeHandle: {
                    [self mtResizeWithHandle:_activeHandleIndex location:[self mtSnappedPoint:location]];
                    break;
                }
                default:
                    break;
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateFailed:
        case UIGestureRecognizerStateCancelled: {
            if (_dragMode != MTSelectionDragModeNone) {
                // 钳制不合法时落为空选区：没有可用的拖拽结果就不展示选区，不回退默认矩形。
                self.selectionRect = MTClampSelectionRect(self.selectionRect, self.bounds.size, MTSelectionMinimumSize);
            }
            _dragMode = MTSelectionDragModeNone;
            [self mtUpdateVisuals];
            if (self.mode == MTCaptureModeArea) {
                MTCaptureLogInfo(@"selection drag finished: state=%ld toolbarHidden=%d", (long)gesture.state, self.toolbar.hidden);
            }
            break;
        }
        default:
            break;
    }
}

#pragma mark - 边缘吸附

// 拖动过程实时吸附：SelectionSnapEdgeDistance（0=关闭）内选框边/把手对齐屏幕边缘。
// 只挂在本视图 pan 路径上；恢复上次选区、默认选区与「全屏」按钮不经过吸附。
- (CGRect)mtSnappedRect:(CGRect)rect {
    CGFloat distance = [MTCapturePreferences config].selectionSnapEdgeDistance;
    if (distance <= 0.0) return rect;
    return MTApplySelectionEdgeSnap(rect, self.bounds.size, distance);
}

// 手柄拖动按点位吸附：把手接近边缘时把拖动点吸到边缘，resize 的对应边随之贴边。
- (CGPoint)mtSnappedPoint:(CGPoint)point {
    CGFloat distance = [MTCapturePreferences config].selectionSnapEdgeDistance;
    if (distance <= 0.0) return point;
    CGSize size = self.bounds.size;
    if (point.x <= distance || size.width - point.x <= distance) {
        point.x = (point.x <= size.width - point.x) ? 0.0 : size.width;
    }
    if (point.y <= distance || size.height - point.y <= distance) {
        point.y = (point.y <= size.height - point.y) ? 0.0 : size.height;
    }
    return point;
}

- (void)mtHandleFloatDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    // 与工具栏「悬浮」按钮同样要求合法选区：细条/零矩形没有悬浮价值。
    if (CGRectIsEmpty(MTClampSelectionRect(self.selectionRect, self.bounds.size, MTSelectionMinimumSize))) {
        return;
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(selectionViewDidRequestFloat:displayRect:)]) {
        [self.delegate selectionViewDidRequestFloat:self displayRect:self.selectionRect];
    }
}

- (NSInteger)mtHandleIndexAtPoint:(CGPoint)point radius:(CGFloat)radius {
    NSInteger best = -1;
    CGFloat bestDistance = radius;
    for (NSInteger i = 0; i < 8; i++) {
        CGFloat distance = hypot(self.handles[i].center.x - point.x, self.handles[i].center.y - point.y);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = i;
        }
    }
    return best;
}

- (void)mtResizeWithHandle:(NSInteger)index location:(CGPoint)location {
    CGRect rect = _dragStartRect;
    CGFloat minX = MIN(rect.origin.x, rect.origin.x + rect.size.width);
    CGFloat maxX = MAX(rect.origin.x, rect.origin.x + rect.size.width);
    CGFloat minY = MIN(rect.origin.y, rect.origin.y + rect.size.height);
    CGFloat maxY = MAX(rect.origin.y, rect.origin.y + rect.size.height);

    switch (index) {
        case 0: minX = location.x; minY = location.y; break;
        case 1: maxX = location.x; minY = location.y; break;
        case 2: maxX = location.x; maxY = location.y; break;
        case 3: minX = location.x; maxY = location.y; break;
        case 4: minY = location.y; break;
        case 5: maxX = location.x; break;
        case 6: maxY = location.y; break;
        case 7: minX = location.x; break;
        default: return;
    }

    CGRect updated = CGRectMake(minX, minY, maxX - minX, maxY - minY);
    if (updated.size.width < MTSelectionMinimumSize || updated.size.height < MTSelectionMinimumSize) {
        return;   // 拖得太小的过程不抖动，松手时统一钳制
    }
    self.selectionRect = updated;
    [self mtUpdateVisuals];
}

#pragma mark - 按钮

- (void)mtButtonTapped:(UIButton *)sender {
    if (!self.userInteractionEnabled || self.toolbar.hidden || !sender.enabled) return;
    NSString *identifier = sender.accessibilityIdentifier;
    if ([identifier isEqualToString:@"freeze"]) {
        if (self.mode == MTCaptureModeArea && !self.areaFrameFrozen &&
            [self.delegate respondsToSelector:@selector(selectionViewDidRequestFreeze:)]) {
            [self.delegate selectionViewDidRequestFreeze:self];
        }
        return;
    }
    if ([identifier isEqualToString:@"cancel"]) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(selectionViewDidCancel:)]) {
            [self.delegate selectionViewDidCancel:self];
        }
        return;
    }
    if ([identifier isEqualToString:@"editor"]) {
        // 与悬浮/滚动/确认同口径：没有合法选区时不进编辑器。
        if (CGRectIsEmpty(MTClampSelectionRect(self.selectionRect, self.bounds.size, MTSelectionMinimumSize))) {
            return;
        }
        if (self.delegate && [self.delegate respondsToSelector:@selector(selectionViewDidRequestEditor:displayRect:)]) {
            [self.delegate selectionViewDidRequestEditor:self displayRect:self.selectionRect];
        }
        return;
    }
    if ([identifier isEqualToString:@"float"]) {
        // 悬浮与确认同样要求合法选区：细条/零矩形没有悬浮价值。
        if (CGRectIsEmpty(MTClampSelectionRect(self.selectionRect, self.bounds.size, MTSelectionMinimumSize))) {
            return;
        }
        if (self.delegate && [self.delegate respondsToSelector:@selector(selectionViewDidRequestFloat:displayRect:)]) {
            [self.delegate selectionViewDidRequestFloat:self displayRect:self.selectionRect];
        }
        return;
    }
    if ([identifier isEqualToString:@"long"]) {
        // 滚动截图同样要求合法选区：细条/零矩形作为采集裁片与滑动视口无意义。
        if (CGRectIsEmpty(MTClampSelectionRect(self.selectionRect, self.bounds.size, MTSelectionMinimumSize))) {
            return;
        }
        if (self.delegate && [self.delegate respondsToSelector:@selector(selectionViewDidRequestLong:displayRect:)]) {
            [self.delegate selectionViewDidRequestLong:self displayRect:self.selectionRect];
        }
        return;
    }
    if ([identifier isEqualToString:@"selectall"]) {
        [self mtSetSelectionRect:self.bounds];
        return;
    }
    if ([identifier isEqualToString:@"markup"]) {
        // 全屏标记无视当前框选：选区是否合法都直接交给协调器收窗重抓屏。
        if (self.delegate && [self.delegate respondsToSelector:@selector(selectionViewDidRequestFullscreenMarkup:)]) {
            [self.delegate selectionViewDidRequestFullscreenMarkup:self];
        }
        return;
    }
    // 自定义 URL 按钮：id 存在于 SelectionCustomButtons 记录时交给协调器打开。
    NSString *customURLString = [MTEditorOrder customURLForSelectionIdentifier:identifier];
    if (customURLString.length > 0) {
        NSURL *url = [NSURL URLWithString:customURLString];
        if (url && self.delegate && [self.delegate respondsToSelector:@selector(selectionView:didRequestCustomURL:)]) {
            [self.delegate selectionView:self didRequestCustomURL:url];
        }
        return;
    }
    // SHELLX 扩展键：交给协调器外调，不走本方输出动作。
    // id→动作映射（MTEditorOrder）与 shellxSelectionIdentifiers 一一对应，缺一即静默失效。
    NSNumber *shellxAction = [MTEditorOrder shellxSelectionActionMap][identifier];
    if (shellxAction) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(selectionViewDidRequestShellXAction:action:)]) {
            [self.delegate selectionViewDidRequestShellXAction:self action:(MTShellXAction)shellxAction.integerValue];
        }
        return;
    }

    // 完成键（PreviewOnly=默认动作）已随 2.0.8 移除：默认配置下与保存完全重复。
    MTOutputAction action = MTOutputActionPreviewOnly;
    if ([identifier isEqualToString:@"save"]) action = MTOutputActionSave;
    else if ([identifier isEqualToString:@"copy"]) action = MTOutputActionCopy;

    if (CGRectIsEmpty(MTClampSelectionRect(self.selectionRect, self.bounds.size, MTSelectionMinimumSize))) {
        return;   // 没有合法选区时不触发确认
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(selectionView:didConfirmDisplayRect:action:)]) {
        [self.delegate selectionView:self didConfirmDisplayRect:self.selectionRect action:action];
    }
}

#pragma mark - 清理

- (void)prepareForDismissal {
    if (_panGesture) {
        [self removeGestureRecognizer:_panGesture];
        _panGesture = nil;
    }
    if (_floatDoubleTap) {
        [self removeGestureRecognizer:_floatDoubleTap];
        _floatDoubleTap = nil;
    }
    _delegate = nil;
    _dimLayer = nil;
    _borderLayer = nil;
    [_handles removeAllObjects];
    _backgroundImageView.image = nil;
}

@end
