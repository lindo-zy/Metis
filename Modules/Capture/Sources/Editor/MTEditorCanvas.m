#import "MTEditorCanvas.h"
#import "MTEditorRenderer.h"
#import "MTUndoManager.h"
#import "../Common/MTCaptureLog.h"

// 马赛克预览底图密度：按屏幕密度生成（导出走源图全密度），整图一份常驻。
static const CGFloat MTPixelatedMinScale = 1.0;

static CGPoint CGPointAdd(CGPoint a, CGPoint b) {
    return CGPointMake(a.x + b.x, a.y + b.y);
}

typedef NS_ENUM(NSInteger, MTCanvasInteraction) {
    MTCanvasInteractionIdle = 0,
    MTCanvasInteractionDrawing,
    MTCanvasInteractionMovingSelection,
    MTCanvasInteractionDraggingCrop,
};

typedef NS_ENUM(NSInteger, MTCropHandle) {
    MTCropHandleNone = 0,
    MTCropHandleTopLeft,
    MTCropHandleTopRight,
    MTCropHandleBottomLeft,
    MTCropHandleBottomRight,
    MTCropHandleTopEdge,
    MTCropHandleBottomEdge,
    MTCropHandleLeftEdge,
    MTCropHandleRightEdge,
    MTCropHandleInterior,
};

@interface MTEditorCanvas () <UIGestureRecognizerDelegate, UITextViewDelegate>
@property (nonatomic, strong, readwrite) MTEditorDocument *document;
@property (nonatomic, strong) MTUndoManager *mtUndoManager;
@property (nonatomic, strong, readwrite, nullable) MTAnnotation *selectedAnnotation;
@property (nonatomic, assign, readwrite) BOOL cropActive;
@property (nonatomic, assign, readwrite) BOOL textEditing;
@property (nonatomic, strong, nullable) MTAnnotation *activeAnnotation;
@property (nonatomic, strong, nullable) UIImage *pixelatedImage;
@property (nonatomic, assign) BOOL pixelatedGenerating;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *gestureAnchor;   // 交互临时状态
@property (nonatomic, strong, nullable) MTAnnotation *transformBaseline;                   // 变换手势起始快照
@property (nonatomic, assign) CGFloat pinchLastScale;
@property (nonatomic, assign) CGFloat rotationLastAngle;
@property (nonatomic, assign) MTCropHandle cropHandle;
@property (nonatomic, assign) CGRect cropRect;
@property (nonatomic, assign) CGRect cropRectBaseline;
@property (nonatomic, strong, nullable) UITextView *activeTextView;
// 裁剪/旋转烘焙前的文档快照（撤销用）。
@property (nonatomic, strong, nullable) UIImage *docBaselineImage;
@property (nonatomic, strong, nullable) NSArray<MTAnnotation *> *docBaselineAnnotations;
@end

@implementation MTEditorCanvas

- (instancetype)initWithFrame:(CGRect)frame document:(MTEditorDocument *)document {
    if (self = [super initWithFrame:frame]) {
        NSParameterAssert(document);
        _document = document;
        _mtUndoManager = [[MTUndoManager alloc] init];
        _gestureAnchor = [[NSMutableDictionary alloc] init];
        _currentTool = MTAnnotationTypeBrush;
        _currentColor = [UIColor redColor];
        _currentLineWidth = 8.0;
        _currentFillStyle = MTAnnotationFillStyleHollow;
        _currentTextFontSize = [self mtDefaultTextFontSize];
        self.backgroundColor = [UIColor clearColor];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(mtHandlePan:)];
        pan.maximumNumberOfTouches = 1;
        pan.delegate = self;
        [self addGestureRecognizer:pan];

        UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self
                                                                                    action:@selector(mtHandlePinch:)];
        pinch.delegate = self;
        [self addGestureRecognizer:pinch];

        UIRotationGestureRecognizer *rotation = [[UIRotationGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(mtHandleRotation:)];
        rotation.delegate = self;
        [self addGestureRecognizer:rotation];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(mtHandleTap:)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(mtKeyboardFrameChanged:)
                                                     name:UIKeyboardWillChangeFrameNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [self prepareForDismissal];
}

#pragma mark - 尺寸辅助

- (CGFloat)mtShortSide {
    return MIN(self.bounds.size.width, self.bounds.size.height);
}

- (CGFloat)mtHitSlop {
    return MAX(18.0, [self mtShortSide] / 40.0);
}

- (CGFloat)mtDefaultTextFontSize {
    return MAX(18.0, MIN(120.0, [self mtShortSide] / 22.0));
}

- (CGFloat)mtSelectionUnit {
    return MAX(3.0, [self mtShortSide] / 200.0);
}

- (CGFloat)mtMosaicBlockSize {
    return MAX(10.0, MIN(40.0, [self mtShortSide] / 40.0));
}

#pragma mark - 工具切换

- (void)setCurrentTool:(MTAnnotationType)currentTool {
    if (_currentTool == currentTool) return;
    if (self.cropActive) {
        [self cancelCrop];
    }
    [self commitActiveText];
    _currentTool = currentTool;
    [self mtSetSelectedAnnotation:nil];
    [self setNeedsDisplay];
}

#pragma mark - 绘制

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    if (self.cropActive) {
        [self mtDirectDrawCropOverlayInContext:ctx];
        return;
    }

    for (MTAnnotation *annotation in self.document.annotations) {
        [MTEditorRenderer drawAnnotation:annotation
                               inContext:ctx
                             sourceImage:self.document.sourceImage
                          pixelatedImage:self.pixelatedImage];
    }
    if (self.activeAnnotation) {
        [MTEditorRenderer drawAnnotation:self.activeAnnotation
                               inContext:ctx
                             sourceImage:self.document.sourceImage
                          pixelatedImage:self.pixelatedImage];
    }
    if (self.selectedAnnotation) {
        [self mtDirectDrawSelectionChromeFor:self.selectedAnnotation inContext:ctx];
    }

    if (!self.pixelatedImage && !self.pixelatedGenerating && [self mtDocumentHasMosaic]) {
        [self requestPixelatedPreview];
    }
}

- (BOOL)mtDocumentHasMosaic {
    for (MTAnnotation *annotation in self.document.annotations) {
        if (annotation.type == MTAnnotationTypeMosaic) return YES;
    }
    return NO;
}

- (void)mtDirectDrawSelectionChromeFor:(MTAnnotation *)annotation inContext:(CGContextRef)ctx {
    CGRect bounds = CGRectInset(annotation.boundsInImageSpace, -[self mtSelectionUnit] * 2.0,
                                [self mtSelectionUnit] * 2.0);
    bounds = CGRectMake(bounds.origin.x, bounds.origin.y,
                        MAX(bounds.size.width, [self mtSelectionUnit] * 8),
                        MAX(bounds.size.height, [self mtSelectionUnit] * 8));

    CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(ctx, [self mtSelectionUnit] * 0.6);
    CGFloat dash = [self mtSelectionUnit] * 2.0;
    CGContextSetLineDash(ctx, 0, (const CGFloat[]){dash, dash}, 2);
    CGContextStrokeRect(ctx, bounds);
    CGContextSetLineDash(ctx, 0, NULL, 0);

    CGFloat r = [self mtSelectionUnit] * 1.6;
    CGPoint corners[4] = {
        CGPointMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds)),
        CGPointMake(CGRectGetMaxX(bounds), CGRectGetMinY(bounds)),
        CGPointMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds)),
        CGPointMake(CGRectGetMaxX(bounds), CGRectGetMaxY(bounds)),
    };
    for (NSUInteger i = 0; i < 4; i++) {
        CGRect dot = CGRectMake(corners[i].x - r, corners[i].y - r, r * 2, r * 2);
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.1 alpha:0.9].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectInset(dot, -r * 0.35, -r * 0.35));
        CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
        CGContextFillEllipseInRect(ctx, dot);
    }
}

#pragma mark - 裁剪模式

- (void)beginCrop {
    if (self.cropActive) return;
    [self commitActiveText];
    [self mtSetSelectedAnnotation:nil];
    CGFloat inset = [self mtShortSide] * 0.04;
    self.cropRect = CGRectInset(CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height),
                                inset, inset);
    self.cropActive = YES;
    [self setNeedsDisplay];
}

- (void)cancelCrop {
    if (!self.cropActive) return;
    self.cropActive = NO;
    self.cropHandle = MTCropHandleNone;
    [self setNeedsDisplay];
}

- (BOOL)applyCrop {
    if (!self.cropActive) return NO;
    CGRect cropRect = [self mtSanitizedCropRect];
    UIImage *cropped = [MTEditorRenderer cropImage:self.document.sourceImage toRect:cropRect];
    if (!cropped) {
        MTCaptureLogWarn(@"editor crop failed: source unavailable");
        return NO;
    }
    NSArray<MTAnnotation *> *remapped = [MTEditorRenderer annotationsByApplyingCrop:cropRect
                                                                       toAnnotations:self.document.annotations];

    UIImage *oldImage = self.document.sourceImage;
    NSArray<MTAnnotation *> *oldAnnotations = self.document.annotations;
    [self.document replaceContentWithImage:cropped annotations:remapped];

    __weak typeof(self) weakSelf = self;
    [self.mtUndoManager pushUndoBlock:^{
        [weakSelf mtRestoreDocumentImage:oldImage annotations:oldAnnotations];
    } redoBlock:^{
        [weakSelf mtRestoreDocumentImage:cropped annotations:remapped];
    } pinsImage:YES];

    self.cropActive = NO;
    self.cropHandle = MTCropHandleNone;
    self.pixelatedImage = nil;
    self.pixelatedGenerating = NO;
    [self setNeedsDisplay];
    [self mtNotifyContentChanged];
    [self.delegate canvasDidChangeGeometry:self];
    [self requestPixelatedPreview];
    return YES;
}

- (void)mtRestoreDocumentImage:(UIImage *)image annotations:(NSArray<MTAnnotation *> *)annotations {
    [self.document replaceContentWithImage:image annotations:[annotations copy]];
    [self mtSetSelectedAnnotation:nil];
    self.pixelatedImage = nil;
    self.pixelatedGenerating = NO;
    [self setNeedsDisplay];
    [self mtNotifyContentChanged];
    [self.delegate canvasDidChangeGeometry:self];
    [self requestPixelatedPreview];
}

- (CGRect)mtSanitizedCropRect {
    CGRect bounds = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    CGRect rect = CGRectIntersection(self.cropRect, bounds);
    if (CGRectIsEmpty(rect)) {
        rect = bounds;
    }
    return rect;
}

- (MTCropHandle)mtCropHandleAtPoint:(CGPoint)point {
    CGFloat hit = MAX(24.0, [self mtShortSide] * 0.06);
    CGRect rect = self.cropRect;

    BOOL nearLeft = fabs(point.x - CGRectGetMinX(rect)) <= hit;
    BOOL nearRight = fabs(point.x - CGRectGetMaxX(rect)) <= hit;
    BOOL nearTop = fabs(point.y - CGRectGetMinY(rect)) <= hit;
    BOOL nearBottom = fabs(point.y - CGRectGetMaxY(rect)) <= hit;

    if (nearLeft && nearTop) return MTCropHandleTopLeft;
    if (nearRight && nearTop) return MTCropHandleTopRight;
    if (nearLeft && nearBottom) return MTCropHandleBottomLeft;
    if (nearRight && nearBottom) return MTCropHandleBottomRight;
    if (nearTop && CGRectContainsPoint(CGRectInset(rect, -hit, -hit), point)) return MTCropHandleTopEdge;
    if (nearBottom && CGRectContainsPoint(CGRectInset(rect, -hit, -hit), point)) return MTCropHandleBottomEdge;
    if (nearLeft) return MTCropHandleLeftEdge;
    if (nearRight) return MTCropHandleRightEdge;
    if (CGRectContainsPoint(rect, point)) return MTCropHandleInterior;
    return MTCropHandleNone;
}

- (void)mtDirectDrawCropOverlayInContext:(CGContextRef)ctx {
    CGRect rect = [self mtSanitizedCropRect];
    CGFloat unit = [self mtSelectionUnit];

    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, NULL, CGRectInfinite);
    CGPathAddRect(path, NULL, rect);
    CGContextSetFillColorWithColor(ctx, [UIColor blackColor].CGColor);
    CGContextSetAlpha(ctx, 0.55);
    CGContextAddPath(ctx, path);
    CGContextEOFillPath(ctx);
    CGPathRelease(path);
    CGContextSetAlpha(ctx, 1.0);

    CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(ctx, unit * 0.6);
    CGContextStrokeRect(ctx, rect);

    // 三分线
    CGContextSetAlpha(ctx, 0.45);
    CGContextSetLineWidth(ctx, unit * 0.35);
    for (NSUInteger i = 1; i < 3; i++) {
        CGFloat fx = CGRectGetMinX(rect) + rect.size.width * i / 3.0;
        CGFloat fy = CGRectGetMinY(rect) + rect.size.height * i / 3.0;
        CGContextMoveToPoint(ctx, fx, CGRectGetMinY(rect));
        CGContextAddLineToPoint(ctx, fx, CGRectGetMaxY(rect));
        CGContextMoveToPoint(ctx, CGRectGetMinX(rect), fy);
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(rect), fy);
    }
    CGContextStrokePath(ctx);
    CGContextSetAlpha(ctx, 1.0);

    // 角部 L 手柄
    CGFloat arm = MAX(20.0, [self mtShortSide] * 0.05);
    CGFloat handleWidth = unit * 1.4;
    CGContextSetLineWidth(ctx, handleWidth);
    CGPoint cornerPairs[8][2] = {
        { CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect) + arm), CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect)) },
        { CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect)), CGPointMake(CGRectGetMinX(rect) + arm, CGRectGetMinY(rect)) },
        { CGPointMake(CGRectGetMaxX(rect) - arm, CGRectGetMinY(rect)), CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect)) },
        { CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect)), CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect) + arm) },
        { CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect) - arm), CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect)) },
        { CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect)), CGPointMake(CGRectGetMinX(rect) + arm, CGRectGetMaxY(rect)) },
        { CGPointMake(CGRectGetMaxX(rect) - arm, CGRectGetMaxY(rect)), CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)) },
        { CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)), CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect) - arm) },
    };
    for (NSUInteger i = 0; i < 8; i++) {
        CGContextMoveToPoint(ctx, cornerPairs[i][0].x, cornerPairs[i][0].y);
        CGContextAddLineToPoint(ctx, cornerPairs[i][1].x, cornerPairs[i][1].y);
    }
    CGContextStrokePath(ctx);
}

#pragma mark - 手势路由

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        if (self.cropActive) return NO;
        // 点击落在文字输入框内时让 UITextView 自己处理（光标定位），框外则提交文字。
        if (self.textEditing && self.activeTextView) {
            CGPoint point = [gestureRecognizer locationInView:self];
            return !CGRectContainsPoint(self.activeTextView.frame, point);
        }
        return YES;
    }
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        if (self.textEditing) return NO;
        if (self.cropActive) return YES;
        if (self.currentTool == MTAnnotationTypePan) return NO;
        return YES;
    }
    if ([gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]]) {
        return !self.cropActive && !self.textEditing && self.selectedAnnotation != nil;
    }
    if ([gestureRecognizer isKindOfClass:[UIRotationGestureRecognizer class]]) {
        return !self.cropActive && !self.textEditing &&
               self.selectedAnnotation.type == MTAnnotationTypeSticker;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 画布内部手势（拖动选中标注 + 捏合缩放 + 贴纸旋转）允许同时进行；
    // 与滚动容器的平移/缩放互斥，避免操纵标注时画面漂移。
    if (gestureRecognizer.view == self && otherGestureRecognizer.view == self) {
        return (self.selectedAnnotation != nil && !self.cropActive);
    }
    return NO;
}

- (nullable MTAnnotation *)mtTopmostAnnotationAtPoint:(CGPoint)point {
    NSArray<MTAnnotation *> *annotations = self.document.annotations;
    CGFloat slop = [self mtHitSlop];
    for (NSUInteger i = annotations.count; i > 0; i--) {
        MTAnnotation *annotation = annotations[i - 1];
        if ([annotation containsImagePoint:point slop:slop]) {
            return annotation;
        }
    }
    return nil;
}

- (void)mtHandlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            [self mtPanBeganAtPoint:point gesture:gesture];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            [self mtPanChangedAtPoint:point];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            [self mtPanEnded];
            break;
        }
        default:
            break;
    }
}

- (void)mtPanBeganAtPoint:(CGPoint)point gesture:(UIPanGestureRecognizer *)gesture {
    if (self.cropActive) {
        MTCropHandle handle = [self mtCropHandleAtPoint:point];
        if (handle == MTCropHandleNone) return;
        self.cropHandle = handle;
        self.cropRectBaseline = self.cropRect;
        self.gestureAnchor[@"start"] = [NSValue valueWithCGPoint:point];
        [self mtSetInteraction:MTCanvasInteractionDraggingCrop];
        return;
    }

    if (self.selectedAnnotation &&
        [self.selectedAnnotation containsImagePoint:point slop:[self mtHitSlop]]) {
        self.transformBaseline = [self.selectedAnnotation copy];
        self.gestureAnchor[@"start"] = [NSValue valueWithCGPoint:point];
        self.gestureAnchor[@"last"] = [NSValue valueWithCGPoint:point];
        [self mtSetInteraction:MTCanvasInteractionMovingSelection];
        return;
    }

    if (self.currentTool == MTAnnotationTypePan || self.currentTool == MTAnnotationTypeText) {
        return;
    }

    [self mtBeginAnnotationAtPoint:point];
}

- (void)mtPanChangedAtPoint:(CGPoint)point {
    switch ([self mtInteraction]) {
        case MTCanvasInteractionDraggingCrop: {
            NSValue *startValue = self.gestureAnchor[@"start"];
            if (!startValue) return;
            [self mtCropDragFrom:[startValue CGPointValue] to:point];
            break;
        }
        case MTCanvasInteractionMovingSelection: {
            NSValue *lastValue = self.gestureAnchor[@"last"];
            if (!self.selectedAnnotation || !lastValue) return;
            // 增量平移：避免抓取瞬间把标注中心吸附到手指造成跳变。
            CGPoint last = [lastValue CGPointValue];
            CGPoint delta = CGPointMake(point.x - last.x, point.y - last.y);
            if (fabs(delta.x) < 0.5 && fabs(delta.y) < 0.5) return;
            [self.selectedAnnotation translateToCenter:
                CGPointAdd(self.selectedAnnotation.centerInImageSpace, delta)];
            self.gestureAnchor[@"last"] = [NSValue valueWithCGPoint:point];
            [self mtClampAnnotationIntoCanvas:self.selectedAnnotation];
            [self setNeedsDisplay];
            break;
        }
        case MTCanvasInteractionDrawing: {
            [self mtUpdateAnnotationAtPoint:point];
            break;
        }
        default:
            break;
    }
}

- (void)mtPanEnded {
    switch ([self mtInteraction]) {
        case MTCanvasInteractionDraggingCrop: {
            // 裁剪框拖动不单独入撤销栈（应用时整体快照）。
            break;
        }
        case MTCanvasInteractionMovingSelection: {
            [self mtPushTransformUndoIfChanged];
            [self mtNotifyContentChanged];
            break;
        }
        case MTCanvasInteractionDrawing: {
            [self mtCommitActiveAnnotation];
            break;
        }
        default:
            break;
    }
    [self mtSetInteraction:MTCanvasInteractionIdle];
    [self.gestureAnchor removeAllObjects];
    self.transformBaseline = nil;
}

- (MTCanvasInteraction)mtInteraction {
    NSNumber *value = self.gestureAnchor[@"mode"];
    return value ? (MTCanvasInteraction)value.integerValue : MTCanvasInteractionIdle;
}

- (void)mtSetInteraction:(MTCanvasInteraction)mode {
    self.gestureAnchor[@"mode"] = @(mode);
}

#pragma mark - 绘制标注

- (void)mtBeginAnnotationAtPoint:(CGPoint)point {
    MTAnnotationType tool = self.currentTool;
    CGSize imageSize = self.document.sourceImage.size;
    if (imageSize.width <= 0 || imageSize.height <= 0) return;
    point = CGPointMake(MAX(0, MIN(point.x, imageSize.width)),
                        MAX(0, MIN(point.y, imageSize.height)));

    MTAnnotation *annotation = [[MTAnnotation alloc] initWithType:tool
                                                            color:self.currentColor
                                                        lineWidth:self.currentLineWidth
                                                            alpha:1.0];
    if (tool == MTAnnotationTypeMosaic && !self.pixelatedImage) {
        [self requestPixelatedPreview];   // 起笔预热：首笔涂抹即显马赛克，不落灰色占位
    }
    annotation.fillStyle = self.currentFillStyle;
    switch (tool) {
        case MTAnnotationTypeBrush:
        case MTAnnotationTypeHighlight:
        case MTAnnotationTypeMosaic:
        case MTAnnotationTypeLine:
        case MTAnnotationTypeArrow:
            [annotation.points addObject:[NSValue valueWithCGPoint:point]];
            break;
        default:
            annotation.rect = CGRectMake(point.x, point.y, 0, 0);
            break;
    }
    self.activeAnnotation = annotation;
    self.gestureAnchor[@"anchor"] = [NSValue valueWithCGPoint:point];
    [self mtSetInteraction:MTCanvasInteractionDrawing];
    [self setNeedsDisplay];
}

- (void)mtUpdateAnnotationAtPoint:(CGPoint)point {
    MTAnnotation *annotation = self.activeAnnotation;
    if (!annotation) return;
    CGSize imageSize = self.document.sourceImage.size;
    point = CGPointMake(MAX(0, MIN(point.x, imageSize.width)),
                        MAX(0, MIN(point.y, imageSize.height)));

    switch (annotation.type) {
        case MTAnnotationTypeBrush:
        case MTAnnotationTypeHighlight:
        case MTAnnotationTypeMosaic: {
            NSUInteger count = annotation.points.count;
            if (count == 0 ||
                !CGPointEqualToPoint([annotation.points[count - 1] CGPointValue], point)) {
                [annotation.points addObject:[NSValue valueWithCGPoint:point]];
            }
            break;
        }
        case MTAnnotationTypeLine:
        case MTAnnotationTypeArrow: {
            CGPoint start = [annotation.points.firstObject CGPointValue];
            annotation.points = [NSMutableArray arrayWithObjects:
                                 [NSValue valueWithCGPoint:start],
                                 [NSValue valueWithCGPoint:point], nil];
            break;
        }
        default: {
            NSValue *anchorValue = self.gestureAnchor[@"anchor"];
            if (!anchorValue) return;
            CGPoint anchor = [anchorValue CGPointValue];
            annotation.rect = CGRectMake(MIN(anchor.x, point.x), MIN(anchor.y, point.y),
                                         fabs(point.x - anchor.x), fabs(point.y - anchor.y));
            break;
        }
    }
    [self setNeedsDisplay];
}

- (void)mtCommitActiveAnnotation {
    MTAnnotation *annotation = self.activeAnnotation;
    self.activeAnnotation = nil;
    if (!annotation) return;

    BOOL hasContent = NO;
    switch (annotation.type) {
        case MTAnnotationTypeBrush:
        case MTAnnotationTypeHighlight:
        case MTAnnotationTypeLine:
        case MTAnnotationTypeArrow:
        case MTAnnotationTypeMosaic:
            hasContent = (annotation.points.count >= 2) || (annotation.points.count == 1 && (annotation.type == MTAnnotationTypeBrush || annotation.type == MTAnnotationTypeMosaic));
            break;
        default:
            hasContent = (annotation.rect.size.width >= 6 && annotation.rect.size.height >= 6);
            break;
    }
    if (!hasContent) {
        [self setNeedsDisplay];
        [self mtNotifyContentChanged];   // 无效笔迹也走回收检查（如释放起笔时预热的底图）
        return;   // 过小的误触不进入文档
    }

    [self mtAddAnnotationWithUndo:annotation];
    [self setNeedsDisplay];
    [self mtNotifyContentChanged];
}

/// 统一入口：加入文档 + 入撤销栈 + 刷新。
- (void)mtAddAnnotationWithUndo:(MTAnnotation *)annotation {
    [self.document addAnnotation:annotation];
    NSString *annotationID = annotation.annotationID;
    NSUInteger addedIndex = [self.document indexOfAnnotationWithID:annotationID];
    MTAnnotation *copyForRedo = [annotation copy];
    __weak typeof(self) weakSelf = self;
    [self.mtUndoManager pushUndoBlock:^{
        [weakSelf mtRemoveAnnotationByID:annotationID];
    } redoBlock:^{
        [weakSelf mtReinsertAnnotation:copyForRedo atIndex:addedIndex];
    }];
}

- (void)mtRemoveAnnotationByID:(NSString *)annotationID {
    NSUInteger index = [self.document indexOfAnnotationWithID:annotationID];
    if (index == NSNotFound) return;
    [self.document removeAnnotationWithID:annotationID];
    if ([self.selectedAnnotation.annotationID isEqualToString:annotationID]) {
        [self mtSetSelectedAnnotation:nil];
    }
    [self setNeedsDisplay];
    [self mtNotifyContentChanged];
}

- (void)mtReinsertAnnotation:(MTAnnotation *)annotation atIndex:(NSUInteger)index {
    if (!annotation) return;
    NSUInteger existing = [self.document indexOfAnnotationWithID:annotation.annotationID];
    if (existing != NSNotFound) {
        [self.document removeAnnotationWithID:annotation.annotationID];
    }
    [self.document insertAnnotation:annotation atIndex:MIN(index, self.document.annotations.count)];
    [self setNeedsDisplay];
    [self mtNotifyContentChanged];
}

#pragma mark - 选中与变换

- (void)mtSetSelectedAnnotation:(nullable MTAnnotation *)annotation {
    if (_selectedAnnotation == annotation) return;
    _selectedAnnotation = annotation;
    [self setNeedsDisplay];
    if (self.delegate && [self.delegate respondsToSelector:@selector(canvasDidChangeSelection:)]) {
        [self.delegate canvasDidChangeSelection:self];
    }
}

- (void)mtHandleTap:(UITapGestureRecognizer *)gesture {
    if (self.cropActive) return;
    if (self.textEditing) {
        [self commitActiveText];
        return;
    }

    CGPoint point = [gesture locationInView:self];

    switch (self.currentTool) {
        case MTAnnotationTypeMagnifier:
            [self mtPlaceMagnifierAtPoint:point];
            return;
        case MTAnnotationTypeSticker:
            [self mtPlaceStickerAtPoint:point];
            return;
        case MTAnnotationTypeStamp:
            [self mtPlaceStampAtPoint:point];
            return;
        case MTAnnotationTypeText:
            [self beginTextInputAtPoint:point];
            return;
        default:
            break;
    }

    MTAnnotation *hit = [self mtTopmostAnnotationAtPoint:point];
    [self mtSetSelectedAnnotation:hit];
}

- (void)mtPlaceMagnifierAtPoint:(CGPoint)point {
    CGFloat radius = [self mtShortSide] * 0.08;
    MTAnnotation *annotation = [[MTAnnotation alloc] initWithType:MTAnnotationTypeMagnifier
                                                            color:self.currentColor
                                                        lineWidth:1.0
                                                            alpha:1.0];
    annotation.rect = CGRectMake(point.x - radius, point.y - radius, radius * 2, radius * 2);
    annotation.zoom = 2.5;
    [self mtAddAnnotationWithUndo:annotation];
    [self mtSetSelectedAnnotation:annotation];
    [self mtNotifyContentChanged];
}

- (void)mtPlaceStickerAtPoint:(CGPoint)point {
    NSString *emoji = self.currentStickerText ?: @"✅";
    CGFloat size = [self mtShortSide] * 0.12;
    MTAnnotation *annotation = [[MTAnnotation alloc] initWithType:MTAnnotationTypeSticker
                                                            color:self.currentColor
                                                        lineWidth:1.0
                                                            alpha:1.0];
    annotation.rect = CGRectMake(point.x - size / 2.0, point.y - size / 2.0, size, size);
    annotation.stickerText = emoji;
    annotation.fontSize = size;
    [self mtAddAnnotationWithUndo:annotation];
    [self mtSetSelectedAnnotation:annotation];
    [self mtNotifyContentChanged];
}

- (void)mtPlaceStampAtPoint:(CGPoint)point {
    CGFloat size = [self mtShortSide] * 0.075;
    MTAnnotation *annotation = [[MTAnnotation alloc] initWithType:MTAnnotationTypeStamp
                                                            color:self.currentColor
                                                        lineWidth:1.0
                                                            alpha:1.0];
    annotation.rect = CGRectMake(point.x - size / 2.0, point.y - size / 2.0, size, size);
    annotation.stampNumber = [self.document nextStampNumber];
    annotation.fontSize = size * 0.52;
    [self mtAddAnnotationWithUndo:annotation];
    [self mtSetSelectedAnnotation:annotation];
    [self mtNotifyContentChanged];
}

- (void)mtHandlePinch:(UIPinchGestureRecognizer *)gesture {
    MTAnnotation *selected = self.selectedAnnotation;
    if (!selected || self.cropActive || self.textEditing) return;

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            self.transformBaseline = [selected copy];
            self.pinchLastScale = 1.0;
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat delta = gesture.scale / MAX(self.pinchLastScale, 0.0001);
            if (delta > 0.9 && delta < 1.1) break;   // 抑制抖动
            [selected applyScale:delta];
            self.pinchLastScale = gesture.scale;
            [self setNeedsDisplay];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            [self mtPushTransformUndoIfChanged];
            [self mtNotifyContentChanged];
            self.transformBaseline = nil;
            break;
        }
        default:
            break;
    }
}

- (void)mtHandleRotation:(UIRotationGestureRecognizer *)gesture {
    MTAnnotation *selected = self.selectedAnnotation;
    if (!selected || self.cropActive || self.textEditing) return;

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            self.transformBaseline = [selected copy];
            self.rotationLastAngle = 0.0;
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat delta = gesture.rotation - self.rotationLastAngle;
            [selected applyRotation:delta];
            self.rotationLastAngle = gesture.rotation;
            [self setNeedsDisplay];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            [self mtPushTransformUndoIfChanged];
            [self mtNotifyContentChanged];
            self.transformBaseline = nil;
            break;
        }
        default:
            break;
    }
}

- (void)mtPushTransformUndoIfChanged {
    MTAnnotation *baseline = self.transformBaseline;
    MTAnnotation *current = self.selectedAnnotation;
    if (!baseline || !current) return;
    if ([self mtAnnotation:baseline equalToGeometryOf:current]) return;

    MTAnnotation *before = [baseline copy];
    MTAnnotation *after = [current copy];
    NSString *annotationID = current.annotationID;
    __weak typeof(self) weakSelf = self;
    [self.mtUndoManager pushUndoBlock:^{
        [weakSelf mtReplaceAnnotationWithID:annotationID with:before];
    } redoBlock:^{
        [weakSelf mtReplaceAnnotationWithID:annotationID with:after];
    }];
}

- (BOOL)mtAnnotation:(MTAnnotation *)a equalToGeometryOf:(MTAnnotation *)b {
    return CGRectEqualToRect(a.rect, b.rect) &&
           a.points.count == b.points.count &&
           CGRectEqualToRect(a.boundsInImageSpace, b.boundsInImageSpace) &&
           fabs(a.rotation - b.rotation) < 0.001 &&
           fabs(a.fontSize - b.fontSize) < 0.01;
}

- (void)mtReplaceAnnotationWithID:(NSString *)annotationID with:(MTAnnotation *)replacement {
    NSUInteger index = [self.document indexOfAnnotationWithID:annotationID];
    if (index == NSNotFound || !replacement) return;
    MTAnnotation *copy = [replacement copy];
    [self.document removeAnnotationWithID:annotationID];
    [self.document insertAnnotation:copy atIndex:index];
    if ([self.selectedAnnotation.annotationID isEqualToString:annotationID]) {
        // 同一标注的几何替换：走统一 setter 触发选中回调（copy 指针不同必然生效）。
        [self mtSetSelectedAnnotation:copy];
    } else {
        [self setNeedsDisplay];
    }
    [self mtNotifyContentChanged];
}

- (void)mtClampAnnotationIntoCanvas:(MTAnnotation *)annotation {
    CGRect bounds = annotation.boundsInImageSpace;
    CGSize canvasSize = self.bounds.size;
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;
    CGFloat dx = 0;
    CGFloat dy = 0;
    if (bounds.size.width <= canvasSize.width) {
        if (CGRectGetMinX(bounds) < 0) dx = -CGRectGetMinX(bounds);
        else if (CGRectGetMaxX(bounds) > canvasSize.width) dx = canvasSize.width - CGRectGetMaxX(bounds);
    }
    if (bounds.size.height <= canvasSize.height) {
        if (CGRectGetMinY(bounds) < 0) dy = -CGRectGetMinY(bounds);
        else if (CGRectGetMaxY(bounds) > canvasSize.height) dy = canvasSize.height - CGRectGetMaxY(bounds);
    }
    if (fabs(dx) > 0.5 || fabs(dy) > 0.5) {
        [annotation translateToCenter:CGPointAdd(annotation.centerInImageSpace,
                                                 CGPointMake(dx, dy))];
    }
}

#pragma mark - 删除 / 置顶

- (void)deleteSelectedAnnotation {
    MTAnnotation *selected = self.selectedAnnotation;
    if (!selected) return;
    NSUInteger fromIndex = [self.document indexOfAnnotationWithID:selected.annotationID];
    if (fromIndex == NSNotFound) {
        [self mtSetSelectedAnnotation:nil];
        return;
    }
    MTAnnotation *removed = [selected copy];
    NSString *annotationID = removed.annotationID;
    [self.document removeAnnotationWithID:annotationID];
    [self mtSetSelectedAnnotation:nil];

    __weak typeof(self) weakSelf = self;
    [self.mtUndoManager pushUndoBlock:^{
        [weakSelf mtReinsertAnnotation:removed atIndex:fromIndex];
    } redoBlock:^{
        [weakSelf mtRemoveAnnotationByID:annotationID];
    }];
    [self setNeedsDisplay];
    [self mtNotifyContentChanged];
}

- (void)bringSelectedAnnotationToFront {
    MTAnnotation *selected = self.selectedAnnotation;
    if (!selected) return;
    NSString *annotationID = selected.annotationID;
    NSUInteger fromIndex = [self.document indexOfAnnotationWithID:annotationID];
    if (fromIndex == NSNotFound) return;
    NSUInteger toIndex = self.document.annotations.count - 1;
    if (fromIndex == toIndex) return;

    MTAnnotation *moved = [selected copy];
    [self.document removeAnnotationWithID:annotationID];
    [self.document insertAnnotation:moved atIndex:toIndex];

    __weak typeof(self) weakSelf = self;
    [self.mtUndoManager pushUndoBlock:^{
        [weakSelf mtMoveAnnotationWithID:annotationID toIndex:fromIndex];
    } redoBlock:^{
        [weakSelf mtMoveAnnotationWithID:annotationID toIndex:toIndex];
    }];
    [self mtSetSelectedAnnotation:moved];
    [self mtNotifyContentChanged];
}

- (void)mtMoveAnnotationWithID:(NSString *)annotationID toIndex:(NSUInteger)targetIndex {
    NSUInteger index = [self.document indexOfAnnotationWithID:annotationID];
    if (index == NSNotFound) return;
    MTAnnotation *annotation = self.document.annotations[index];
    [self.document removeAnnotationWithID:annotationID];
    NSUInteger clamped = MIN(targetIndex, self.document.annotations.count);
    [self.document insertAnnotation:annotation atIndex:clamped];
    annotation.zIndex = clamped;
    [self setNeedsDisplay];
    [self mtNotifyContentChanged];
}

#pragma mark - 撤销

- (BOOL)canUndo {
    return [self.mtUndoManager canUndo];
}

- (BOOL)canRedo {
    return [self.mtUndoManager canRedo];
}

- (void)undo {
    [self commitActiveText];
    [self.mtUndoManager undo];
    // 撤销后选中对象可能已不在文档里，做一致性清理。
    if (self.selectedAnnotation &&
        [self.document indexOfAnnotationWithID:self.selectedAnnotation.annotationID] == NSNotFound) {
        [self mtSetSelectedAnnotation:nil];
    } else {
        [self setNeedsDisplay];
    }
    [self mtNotifyContentChanged];
}

- (void)redo {
    [self commitActiveText];
    [self.mtUndoManager redo];
    if (self.selectedAnnotation &&
        [self.document indexOfAnnotationWithID:self.selectedAnnotation.annotationID] == NSNotFound) {
        [self mtSetSelectedAnnotation:nil];
    } else {
        [self setNeedsDisplay];
    }
    [self mtNotifyContentChanged];
}

- (void)mtNotifyContentChanged {
    // 马赛克清零后释放整图底图（约一份全屏位图），不留到会话结束。
    if (!self.pixelatedGenerating && self.pixelatedImage && ![self mtDocumentHasMosaic]) {
        self.pixelatedImage = nil;
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(canvasDidChangeContent:)]) {
        [self.delegate canvasDidChangeContent:self];
    }
}

#pragma mark - 文字输入

- (void)beginTextInputAtPoint:(CGPoint)point {
    [self commitActiveText];

    CGFloat width = MAX(140.0, MIN(self.bounds.size.width * 0.7, 600.0));
    CGFloat initialHeight = self.currentTextFontSize * 1.6;
    CGRect frame = CGRectMake(point.x - width / 2.0, point.y - initialHeight / 2.0, width, initialHeight);
    frame = CGRectIntersection(frame, CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height));
    if (CGRectIsEmpty(frame)) return;

    UITextView *textView = [[UITextView alloc] initWithFrame:frame];
    textView.font = [UIFont fontWithName:@"PingFangSC-Semibold" size:self.currentTextFontSize]
        ?: [UIFont boldSystemFontOfSize:self.currentTextFontSize];
    textView.textColor = self.currentColor;
    textView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    textView.layer.borderColor = [UIColor whiteColor].CGColor;
    textView.layer.borderWidth = 1.0;
    textView.autocorrectionType = UITextAutocorrectionTypeNo;
    textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone;
    textView.returnKeyType = UIReturnKeyDefault;
    textView.delegate = self;
    textView.inputAccessoryView = [self mtTextInputAccessoryBar];

    UITextPosition *begin = textView.beginningOfDocument;
    textView.selectedTextRange = [textView textRangeFromPosition:begin toPosition:begin];

    self.activeTextView = textView;
    [self addSubview:textView];
    self.textEditing = YES;
    if (self.delegate) {
        [self.delegate canvasDidStartTextInput:self];
        [self.delegate canvas:self didUpdateTextInputFrame:textView.frame];
    }
    if (![textView becomeFirstResponder]) {
        [self mtRetryEditorKeyboardWithAttempt:1 textView:textView];
    }
}

/// SpringBoard 下键盘偶发首次唤起失败（ShellX ss_retryEditorKeyboard 同款处理）：
/// 延迟重试最多 2 次；仍失败则通知调用方走弹窗输入兜底。
- (void)mtRetryEditorKeyboardWithAttempt:(NSInteger)attempt textView:(UITextView *)textView {
    if (attempt > 2 || textView != self.activeTextView) return;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || textView != strongSelf.activeTextView) return;
        if (textView.isFirstResponder) return;
        if (![textView becomeFirstResponder]) {
            if (attempt >= 2) {
                CGPoint pendingPoint = CGPointMake(CGRectGetMidX(textView.frame),
                                                   CGRectGetMidY(textView.frame));
                [strongSelf mtTeardownTextInput];
                if (strongSelf.delegate) {
                    [strongSelf.delegate canvasKeyboardUnavailable:strongSelf pendingTextPoint:pendingPoint];
                }
            } else {
                [strongSelf mtRetryEditorKeyboardWithAttempt:attempt + 1 textView:textView];
            }
        }
    });
}

- (UIView *)mtTextInputAccessoryBar {
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 44)];
    bar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.98];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.frame = CGRectMake(12, 0, 64, 44);
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    cancel.tintColor = UIColor.systemRedColor;
    [cancel addTarget:self action:@selector(cancelActiveText) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:cancel];

    UIButton *commit = [UIButton buttonWithType:UIButtonTypeSystem];
    commit.frame = CGRectMake(bar.bounds.size.width - 76, 0, 64, 44);
    commit.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [commit setTitle:@"完成" forState:UIControlStateNormal];
    commit.tintColor = [UIColor whiteColor];
    commit.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [commit addTarget:self action:@selector(commitActiveText) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:commit];

    return bar;
}

- (void)commitActiveText {
    UITextView *textView = self.activeTextView;
    if (!textView) return;
    NSString *content = [textView.text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    CGRect frame = textView.frame;
    UIColor *color = textView.textColor ?: self.currentColor;
    CGFloat fontSize = self.currentTextFontSize;
    [self mtTeardownTextInput];

    if (content.length == 0) return;

    UIFont *font = [UIFont fontWithName:@"PingFangSC-Semibold" size:fontSize]
        ?: [UIFont boldSystemFontOfSize:fontSize];
    CGFloat maxWidth = MAX(80.0, MIN(frame.size.width, 900.0));

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *measureAttributes = @{
        NSFontAttributeName: font,
        NSParagraphStyleAttributeName: style,
    };
    CGRect textBounds = [content boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                              options:NSStringDrawingUsesLineFragmentOrigin
                                           attributes:measureAttributes
                                              context:nil];

    MTAnnotation *annotation = [[MTAnnotation alloc] initWithType:MTAnnotationTypeText
                                                            color:color
                                                        lineWidth:1.0
                                                            alpha:1.0];
    annotation.rect = CGRectMake(frame.origin.x, frame.origin.y,
                                 ceil(textBounds.size.width) + 4, ceil(textBounds.size.height) + 4);
    annotation.text = [content copy];
    annotation.fontSize = fontSize;
    [self mtClampAnnotationIntoCanvas:annotation];
    CGRect clampedRect = annotation.rect;
    clampedRect.origin.x = MAX(0, clampedRect.origin.x);
    clampedRect.origin.y = MAX(0, clampedRect.origin.y);
    annotation.rect = clampedRect;

    [self mtAddAnnotationWithUndo:annotation];
    [self setNeedsDisplay];
    [self mtNotifyContentChanged];
}

- (void)cancelActiveText {
    if (!self.activeTextView) return;
    [self mtTeardownTextInput];
}

- (void)mtTeardownTextInput {
    UITextView *textView = self.activeTextView;
    self.activeTextView = nil;
    self.textEditing = NO;
    if (textView) {
        [textView resignFirstResponder];
        [textView removeFromSuperview];
    }
    if (self.delegate) {
        [self.delegate canvasDidEndTextInput:self];
    }
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    if (textView == self.activeTextView) {
        [self commitActiveText];
    }
}

- (void)mtKeyboardFrameChanged:(NSNotification *)notification {
    if (!self.activeTextView) return;
    CGRect keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    if (CGRectIsEmpty(keyboardFrame)) return;
    if (self.delegate) {
        [self.delegate canvas:self didUpdateTextInputFrame:self.activeTextView.frame];
    }
}

#pragma mark - 旋转 / 底图

- (BOOL)rotateImage90Clockwise {
    UIImage *rotated = [MTEditorRenderer rotateImage90Clockwise:self.document.sourceImage];
    if (!rotated) return NO;
    NSArray<MTAnnotation *> *remapped = [MTEditorRenderer annotationsByRotating90Clockwise:self.document.annotations
                                                                             sourceImageSize:self.document.sourceImage.size];

    UIImage *oldImage = self.document.sourceImage;
    NSArray<MTAnnotation *> *oldAnnotations = self.document.annotations;
    [self.document replaceContentWithImage:rotated annotations:remapped];

    __weak typeof(self) weakSelf = self;
    [self.mtUndoManager pushUndoBlock:^{
        [weakSelf mtRestoreDocumentImage:oldImage annotations:oldAnnotations];
    } redoBlock:^{
        [weakSelf mtRestoreDocumentImage:rotated annotations:remapped];
    } pinsImage:YES];

    [self mtSetSelectedAnnotation:nil];
    self.pixelatedImage = nil;
    self.pixelatedGenerating = NO;
    [self setNeedsDisplay];
    [self mtNotifyContentChanged];
    [self.delegate canvasDidChangeGeometry:self];
    [self requestPixelatedPreview];
    return YES;
}

- (void)requestPixelatedPreview {
    if (self.pixelatedGenerating || self.pixelatedImage) return;
    UIImage *source = self.document.sourceImage;
    if (!source.CGImage) return;

    self.pixelatedGenerating = YES;
    CGFloat blockSize = [self mtMosaicBlockSize];
    CGFloat screenScale = MAX(UIScreen.mainScreen.scale, MTPixelatedMinScale);
    CGFloat outputScale = MIN(MAX(source.scale, MTPixelatedMinScale), MAX(screenScale, MTPixelatedMinScale));
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *pixelated = [MTEditorRenderer pixelatedImageForSourceImage:source
                                                                  blockSize:blockSize
                                                                outputScale:outputScale];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.pixelatedGenerating = NO;
            // 生成期间底图可能已被裁剪/旋转换掉，仅当源图未变才采用。
            if (strongSelf.document.sourceImage == source) {
                strongSelf.pixelatedImage = pixelated;
                [strongSelf setNeedsDisplay];
            }
        });
    });
}

#pragma mark - 外部接线

- (void)placeTextAnnotationWithText:(NSString *)text atCanvasPoint:(CGPoint)point {
    if (text.length == 0) return;
    CGSize canvasSize = self.bounds.size;
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;

    UIFont *font = [UIFont fontWithName:@"PingFangSC-Semibold" size:self.currentTextFontSize]
        ?: [UIFont boldSystemFontOfSize:self.currentTextFontSize];
    NSDictionary *attributes = @{ NSFontAttributeName: font };
    CGRect textBounds = [text boundingRectWithSize:CGSizeMake(MAX(80.0, canvasSize.width * 0.7), CGFLOAT_MAX)
                                           options:NSStringDrawingUsesLineFragmentOrigin
                                        attributes:attributes
                                           context:nil];

    MTAnnotation *annotation = [[MTAnnotation alloc] initWithType:MTAnnotationTypeText
                                                            color:self.currentColor
                                                        lineWidth:1.0
                                                            alpha:1.0];
    annotation.rect = CGRectMake(point.x, point.y,
                                 ceil(textBounds.size.width) + 4, ceil(textBounds.size.height) + 4);
    annotation.text = [text copy];
    annotation.fontSize = self.currentTextFontSize;
    [self mtClampAnnotationIntoCanvas:annotation];
    CGRect clampedRect = annotation.rect;
    clampedRect.origin.x = MAX(0, clampedRect.origin.x);
    clampedRect.origin.y = MAX(0, clampedRect.origin.y);
    annotation.rect = clampedRect;

    [self mtAddAnnotationWithUndo:annotation];
    [self setNeedsDisplay];
    [self mtNotifyContentChanged];
}

- (void)prepareForDismissal {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillChangeFrameNotification
                                                  object:nil];
    if (self.activeTextView) {
        [self mtTeardownTextInput];
    }
    self.delegate = nil;
    self.activeAnnotation = nil;
    _selectedAnnotation = nil;
    self.transformBaseline = nil;
    [self.gestureAnchor removeAllObjects];
    self.pixelatedImage = nil;
    [self.mtUndoManager removeAllActions];
}

#pragma mark - 几何工具

// 拖动裁剪手柄。
- (void)mtCropDragFrom:(CGPoint)start to:(CGPoint)current {
    CGRect rect = self.cropRectBaseline;
    CGPoint delta = CGPointMake(current.x - start.x, current.y - start.y);
    CGFloat minSize = [self mtShortSide] * 0.1;
    CGRect bounds = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);

    switch (self.cropHandle) {
        case MTCropHandleInterior:
            rect = CGRectOffset(rect, delta.x, delta.y);
            break;
        case MTCropHandleTopLeft:
            rect = CGRectMake(MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y),
                              CGRectGetMaxX(rect) - MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              CGRectGetMaxY(rect) - MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y));
            break;
        case MTCropHandleTopRight:
            rect = CGRectMake(CGRectGetMinX(rect),
                              MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y),
                              MAX(minSize, CGRectGetMaxX(rect) + delta.x - CGRectGetMinX(rect)),
                              CGRectGetMaxY(rect) - MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y));
            break;
        case MTCropHandleBottomLeft:
            rect = CGRectMake(MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              CGRectGetMinY(rect),
                              CGRectGetMaxX(rect) - MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              MAX(minSize, CGRectGetMaxY(rect) + delta.y - CGRectGetMinY(rect)));
            break;
        case MTCropHandleBottomRight:
            rect = CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect),
                              MAX(minSize, CGRectGetMaxX(rect) + delta.x - CGRectGetMinX(rect)),
                              MAX(minSize, CGRectGetMaxY(rect) + delta.y - CGRectGetMinY(rect)));
            break;
        case MTCropHandleTopEdge:
            rect = CGRectMake(CGRectGetMinX(rect),
                              MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y),
                              rect.size.width,
                              CGRectGetMaxY(rect) - MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y));
            break;
        case MTCropHandleBottomEdge:
            rect = CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect),
                              rect.size.width,
                              MAX(minSize, CGRectGetMaxY(rect) + delta.y - CGRectGetMinY(rect)));
            break;
        case MTCropHandleLeftEdge:
            rect = CGRectMake(MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              CGRectGetMinY(rect),
                              CGRectGetMaxX(rect) - MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              rect.size.height);
            break;
        case MTCropHandleRightEdge:
            rect = CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect),
                              MAX(minSize, CGRectGetMaxX(rect) + delta.x - CGRectGetMinX(rect)),
                              rect.size.height);
            break;
        default:
            return;
    }
    self.cropRect = CGRectIntersection(rect, bounds);
    [self setNeedsDisplay];
}

@end
