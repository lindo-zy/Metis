#import "MTDeviceFramePhotoMaterialController.h"
#import "MTDeviceFrameRenderer.h"
#import "MTDeviceFrameViewController.h"

static UIColor *MTMaterialAccent(void){return [UIColor colorWithRed:1 green:0.78 blue:0.08 alpha:1];}

@interface MTFrameMaterialCanvas : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) CGSize pixelSize;
@property (nonatomic) MTDeviceFrameQuad quad;
@property (nonatomic) NSInteger selectedCorner;
@property (nonatomic, strong) NSArray<UIButton *> *handles;
@property (nonatomic, copy) void (^changed)(void);
@property (nonatomic, copy) void (^viewportChanged)(void);
@property (nonatomic) CGFloat zoomScale;
@property (nonatomic) CGPoint zoomOffset;
@property (nonatomic) CGPoint pinchAnchor;
@property (nonatomic) BOOL pinching;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinch;
@property (nonatomic, strong) UIPanGestureRecognizer *canvasPan;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTap;
@property (nonatomic, strong) UIStackView *zoomTools;
@property (nonatomic, strong) UILabel *zoomLabel;
@property (nonatomic, strong) UIButton *zoomOutButton;
@property (nonatomic, strong) UIButton *zoomInButton;
- (CGRect)viewport;
- (void)fitCanvas;
- (void)focusSelectedCorner;
- (void)moveCorner:(CGPoint)delta;
- (void)invalidate;
@end

@implementation MTFrameMaterialCanvas
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=[UIColor colorWithWhite:0.14 alpha:1];self.layer.cornerRadius=16;self.clipsToBounds=YES;_zoomScale=1;
        NSArray *names=@[@"屏幕左上角",@"屏幕右上角",@"屏幕右下角",@"屏幕左下角"];
        NSMutableArray *handles=[NSMutableArray new];
        for(NSInteger i=0;i<4;i++) {
            UIButton *handle=[UIButton buttonWithType:UIButtonTypeCustom];handle.tag=i;
            [handle setTitle:[NSString stringWithFormat:@"%ld",(long)i+1]forState:UIControlStateNormal];
            [handle setTitleColor:UIColor.blackColor forState:UIControlStateNormal];handle.titleLabel.font=[UIFont boldSystemFontOfSize:12];
            handle.accessibilityLabel=names[i];handle.accessibilityHint=@"拖动定位，也可用下方方向按钮按像素微调";
            [handle addTarget:self action:@selector(selectHandle:)forControlEvents:UIControlEventTouchUpInside];
            UIPanGestureRecognizer *drag=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(drag:)];
            drag.maximumNumberOfTouches=1;drag.delegate=self;[handle addGestureRecognizer:drag];
            [self addSubview:handle];[handles addObject:handle];
        }
        self.handles=handles;
        self.pinch=[[UIPinchGestureRecognizer alloc]initWithTarget:self action:@selector(pinchCanvas:)];self.pinch.delegate=self;[self addGestureRecognizer:self.pinch];
        self.canvasPan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(panCanvas:)];self.canvasPan.maximumNumberOfTouches=1;
        self.canvasPan.delegate=self;[self addGestureRecognizer:self.canvasPan];
        self.doubleTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(doubleTapCanvas:)];self.doubleTap.numberOfTapsRequired=2;
        self.doubleTap.delegate=self;[self addGestureRecognizer:self.doubleTap];
        self.zoomLabel=[UILabel new];self.zoomLabel.font=[UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
        self.zoomLabel.textColor=UIColor.secondaryLabelColor;self.zoomLabel.textAlignment=NSTextAlignmentCenter;
        self.zoomLabel.accessibilityLabel=@"画布缩放比例";
        self.zoomOutButton=[self zoomButton:@"minus.magnifyingglass" title:nil action:@selector(zoomOut)];self.zoomOutButton.accessibilityLabel=@"缩小画布";
        self.zoomInButton=[self zoomButton:@"plus.magnifyingglass" title:nil action:@selector(zoomIn)];self.zoomInButton.accessibilityLabel=@"放大画布";
        UIButton *fit=[self zoomButton:nil title:@"适应" action:@selector(fitCanvas)];fit.accessibilityLabel=@"显示完整画布";
        self.zoomTools=[[UIStackView alloc]initWithArrangedSubviews:@[self.zoomLabel,self.zoomOutButton,self.zoomInButton,fit]];
        self.zoomTools.distribution=UIStackViewDistributionFillEqually;[self addSubview:self.zoomTools];[self updateZoomTools];
    }return self;
}
- (UIButton *)zoomButton:(NSString *)symbol title:(NSString *)title action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];button.tintColor=MTMaterialAccent();
    button.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    if(symbol)[button setImage:[UIImage systemImageNamed:symbol]forState:UIControlStateNormal];
    if(title)[button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return button;
}
- (CGRect)viewport {
    CGFloat top=self.bounds.size.height<120 ? 8 : 50;
    CGFloat x=MIN(26,self.bounds.size.width*0.12),bottom=MIN(26,self.bounds.size.height*0.15);
    return CGRectMake(x,top,MAX(1,self.bounds.size.width-2*x),MAX(1,self.bounds.size.height-top-bottom));
}
- (CGRect)imageRect {return MTDeviceFrameZoomRect(self.pixelSize,[self viewport],self.zoomScale,self.zoomOffset);}
- (void)updateZoomTools {
    self.zoomLabel.text=[NSString stringWithFormat:@"%.1f×",self.zoomScale];
    self.zoomLabel.accessibilityValue=[NSString stringWithFormat:@"%.0f%%",self.zoomScale*100];
    self.zoomOutButton.enabled=self.zoomScale>1.001;self.zoomInButton.enabled=self.zoomScale<7.999;
}
- (void)setZoom:(CGFloat)zoom oldAnchor:(CGPoint)oldAnchor newAnchor:(CGPoint)newAnchor {
    if(!isfinite(zoom))return;zoom=MAX(1,MIN(8,zoom));
    self.zoomOffset=MTDeviceFrameZoomOffset(self.pixelSize,[self viewport],self.zoomScale,self.zoomOffset,zoom,oldAnchor,newAnchor);
    self.zoomScale=zoom;[self updateZoomTools];[self setNeedsLayout];if(self.viewportChanged)self.viewportChanged();
}
- (void)fitCanvas {
    self.zoomScale=1;self.zoomOffset=CGPointZero;[self updateZoomTools];[self setNeedsLayout];if(self.viewportChanged)self.viewportChanged();
}
- (void)zoomIn {CGPoint center=CGPointMake(CGRectGetMidX([self viewport]),CGRectGetMidY([self viewport]));[self setZoom:self.zoomScale*1.5 oldAnchor:center newAnchor:center];}
- (void)zoomOut {CGPoint center=CGPointMake(CGRectGetMidX([self viewport]),CGRectGetMidY([self viewport]));[self setZoom:self.zoomScale/1.5 oldAnchor:center newAnchor:center];}
- (void)pinchCanvas:(UIPinchGestureRecognizer *)gesture {
    if(gesture.state==UIGestureRecognizerStateEnded || gesture.state==UIGestureRecognizerStateCancelled || gesture.state==UIGestureRecognizerStateFailed){self.pinching=NO;return;}
    if(gesture.state!=UIGestureRecognizerStateBegan && gesture.state!=UIGestureRecognizerStateChanged)return;
    CGPoint anchor=[gesture locationInView:self];
    if(gesture.state==UIGestureRecognizerStateBegan){self.pinching=YES;self.pinchAnchor=anchor;}
    [self setZoom:self.zoomScale*gesture.scale oldAnchor:self.pinchAnchor newAnchor:anchor];
    self.pinchAnchor=anchor;gesture.scale=1;
}
- (void)panCanvas:(UIPanGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan && gesture.state!=UIGestureRecognizerStateChanged)return;
    CGPoint delta=[gesture translationInView:self];[gesture setTranslation:CGPointZero inView:self];
    if(self.pinching || self.pinch.numberOfTouches>1 || gesture.numberOfTouches!=1)return;
    CGPoint center=CGPointMake(CGRectGetMidX([self viewport]),CGRectGetMidY([self viewport]));
    self.zoomOffset=MTDeviceFrameZoomOffset(self.pixelSize,[self viewport],self.zoomScale,self.zoomOffset,self.zoomScale,center,CGPointMake(center.x+delta.x,center.y+delta.y));[self setNeedsLayout];
}
- (void)doubleTapCanvas:(UITapGestureRecognizer *)gesture {
    CGPoint anchor=[gesture locationInView:self];[self setZoom:self.zoomScale>1.01 ? 1 : 3 oldAnchor:anchor newAnchor:anchor];
}
- (void)focusSelectedCorner {
    if(self.zoomScale<=1.01)return;
    CGPoint points[]={self.quad.topLeft,self.quad.topRight,self.quad.bottomRight,self.quad.bottomLeft};
    CGPoint point=[self displayPoint:points[self.selectedCorner]];
    CGRect area=[self viewport];CGPoint center=CGPointMake(CGRectGetMidX(area),CGRectGetMidY(area));
    self.zoomOffset=MTDeviceFrameZoomOffset(self.pixelSize,area,self.zoomScale,self.zoomOffset,self.zoomScale,point,center);[self setNeedsLayout];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if(gesture==self.canvasPan && self.zoomScale<=1.01)return NO;
    if([gesture isKindOfClass:UIPanGestureRecognizer.class] && (self.pinching || self.pinch.numberOfTouches>1))return NO;
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if(gesture!=self.canvasPan && gesture!=self.doubleTap && gesture!=self.pinch)return YES;
    for(UIView *view=touch.view;view && view!=self;view=view.superview)
        if([view isKindOfClass:UIControl.class])return gesture==self.pinch && [view isKindOfClass:UIButton.class] && [self.handles containsObject:(UIButton *)view];
    return CGRectContainsPoint([self viewport],[touch locationInView:self]);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return gesture==self.pinch || other==self.pinch;
}
- (CGPoint)displayPoint:(CGPoint)p {
    CGRect r=[self imageRect];return CGPointMake(r.origin.x+p.x*r.size.width/self.pixelSize.width,r.origin.y+p.y*r.size.height/self.pixelSize.height);
}
- (void)layoutSubviews {
    [super layoutSubviews];if(self.pixelSize.width<=0 || self.pixelSize.height<=0)return;
    CGRect area=[self viewport],image=[self imageRect];
    self.zoomOffset=CGPointMake(CGRectGetMidX(image)-CGRectGetMidX(area),CGRectGetMidY(image)-CGRectGetMidY(area));
    self.zoomTools.hidden=self.bounds.size.height<120;
    self.zoomTools.frame=CGRectMake(MAX(0,self.bounds.size.width-188),1,180,44);
    CGPoint points[]={self.quad.topLeft,self.quad.topRight,self.quad.bottomRight,self.quad.bottomLeft};
    for(NSInteger i=0;i<4;i++){self.handles[i].bounds=CGRectMake(0,0,44,44);self.handles[i].center=[self displayPoint:points[i]];
        self.handles[i].hidden=!CGRectContainsPoint(CGRectInset(area,-0.5,-0.5),self.handles[i].center);}
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    if(!self.image || self.pixelSize.width<=0 || self.pixelSize.height<=0)return;
    CGContextRef context=UIGraphicsGetCurrentContext();CGContextSaveGState(context);
    CGContextClipToRect(context,[self viewport]);
    [self.image drawInRect:[self imageRect]];
    UIBezierPath *path=[UIBezierPath bezierPath];CGPoint p[]={self.quad.topLeft,self.quad.topRight,self.quad.bottomRight,self.quad.bottomLeft};
    [path moveToPoint:[self displayPoint:p[0]]];for(NSUInteger i=1;i<4;i++)[path addLineToPoint:[self displayPoint:p[i]]];[path closePath];
    [MTMaterialAccent()setStroke];path.lineWidth=1.5;[path stroke];
    CGContextRestoreGState(context);
    for(NSUInteger i=0;i<4;i++) {
        CGPoint center=[self displayPoint:p[i]];if(!CGRectContainsPoint(CGRectInset([self viewport],-0.5,-0.5),center))continue;
        CGFloat radius=(NSInteger)i==self.selectedCorner ? 11 : 9;
        UIBezierPath *dot=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x-radius,center.y-radius,2*radius,2*radius)];
        [MTMaterialAccent()setFill];[dot fill];[UIColor.whiteColor setStroke];dot.lineWidth=1;[dot stroke];
    }
}
- (void)selectHandle:(UIButton *)sender {self.selectedCorner=sender.tag;[self setNeedsDisplay];if(self.changed)self.changed();}
- (void)moveCorner:(CGPoint)delta {
    MTDeviceFrameQuad q=self.quad;CGPoint *point=NULL;
    switch(self.selectedCorner){case 0:point=&q.topLeft;break;case 1:point=&q.topRight;break;case 2:point=&q.bottomRight;break;case 3:point=&q.bottomLeft;break;default:return;}
    point->x=MAX(0,MIN(self.pixelSize.width,point->x+delta.x));point->y=MAX(0,MIN(self.pixelSize.height,point->y+delta.y));
    if(MTDeviceFrameValidQuad(q,self.pixelSize)){self.quad=q;[self setNeedsLayout];if(self.changed)self.changed();}
}
- (void)drag:(UIPanGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan && gesture.state!=UIGestureRecognizerStateChanged)return;
    if(self.pinching || self.pinch.numberOfTouches>1 || gesture.numberOfTouches!=1){[gesture setTranslation:CGPointZero inView:self];return;}
    self.selectedCorner=gesture.view.tag;CGRect r=[self imageRect];if(r.size.width<=0 || r.size.height<=0)return;
    CGPoint delta=[gesture translationInView:self];[gesture setTranslation:CGPointZero inView:self];
    [self moveCorner:CGPointMake(delta.x*self.pixelSize.width/r.size.width,delta.y*self.pixelSize.height/r.size.height)];
}
- (void)invalidate {
    self.changed=nil;self.viewportChanged=nil;self.image=nil;
    for(UIGestureRecognizer *gesture in [self.gestureRecognizers copy]){gesture.delegate=nil;[self removeGestureRecognizer:gesture];}
    for(UIButton *handle in self.handles)for(UIGestureRecognizer *gesture in [handle.gestureRecognizers copy])[handle removeGestureRecognizer:gesture];
}
@end

@interface MTDeviceFramePhotoMaterialController ()
@property (nonatomic, strong) UIImage *source;
@property (nonatomic, strong) UIImage *preview;
@property (nonatomic, strong) UIImage *detailPreview;
@property (nonatomic) BOOL highDetailPreview;
@property (nonatomic, strong) MTFrameMaterialCanvas *canvas;
@property (nonatomic) MTDeviceFrameQuad initialQuad;
@property (nonatomic) CGFloat initialRadius;
@property (nonatomic) BOOL initialManualRadius;
@property (nonatomic) BOOL manualRadius;
@property (nonatomic) BOOL transparent;
@property (nonatomic) BOOL saving;
@property (nonatomic) BOOL invalidated;
@property (nonatomic) BOOL rendering;
@property (nonatomic) BOOL pendingRender;
@property (nonatomic) BOOL previewReady;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) CGFloat keyboardHeight;
@property (nonatomic, copy) NSString *initialName;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UIView *nameCard;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *canvasLabel;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UISegmentedControl *corners;
@property (nonatomic, strong) UIStackView *arrows;
@property (nonatomic, strong) UIView *radiusCard;
@property (nonatomic, strong) UILabel *radiusLabel;
@property (nonatomic, strong) UILabel *radiusValue;
@property (nonatomic, strong) UISlider *radiusSlider;
@property (nonatomic, strong) UISegmentedControl *radiusMode;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSProgress *operation;
@property (nonatomic, strong) dispatch_queue_t renderQueue;
@property (nonatomic, copy) void (^completion)(MTDeviceFrameTemplate *);
@end

@implementation MTDeviceFramePhotoMaterialController
- (instancetype)initWithImage:(UIImage *)image preview:(UIImage *)preview suggestedQuad:(MTDeviceFrameQuad)quad
            transparentScreen:(BOOL)transparent completion:(void (^)(MTDeviceFrameTemplate *))completion {
    if((self=[super initWithNibName:nil bundle:nil])) {
        _source=image;_preview=preview;_initialQuad=quad;_transparent=transparent;_initialRadius=transparent ? 0 : 24;
        _completion=[completion copy];_initialName=@"相册素材";
        _renderQueue=dispatch_queue_create("com.lindo.metis.capture.frame.material",DISPATCH_QUEUE_SERIAL);
        self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    }return self;
}
- (instancetype)initWithTemplate:(MTDeviceFrameTemplate *)frame image:(UIImage *)image preview:(UIImage *)preview
                     completion:(void (^)(MTDeviceFrameTemplate *))completion {
    BOOL transparent=NO;[MTDeviceFramePhotoMaterial suggestedScreenForImage:image hasTransparentScreen:&transparent];
    if((self=[self initWithImage:image preview:preview suggestedQuad:frame.screenQuad transparentScreen:transparent completion:completion])) {
        _initialName=frame.name;_initialRadius=frame.screenCornerRadius;
        _manualRadius=frame.adjustsTransparentCorners;_initialManualRadius=_manualRadius;
    }return self;
}
- (UILabel *)label:(NSString *)text size:(CGFloat)size {
    UILabel *label=[UILabel new];label.text=text;label.textColor=UIColor.secondaryLabelColor;label.font=[UIFont systemFontOfSize:size];
    label.adjustsFontSizeToFitWidth=YES;label.minimumScaleFactor=0.75;return label;
}
- (UIButton *)button:(NSString *)text selector:(SEL)selector {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:text forState:UIControlStateNormal];
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"素材编辑";self.view.tintColor=MTMaterialAccent();self.modalInPresentation=YES;
    self.view.backgroundColor=[UIColor colorWithWhite:0.06 alpha:1];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.screenshot=self.screenshot ?: [MTDeviceFrameViewController exampleImage];
    self.nameCard=[UIView new];self.nameCard.backgroundColor=[UIColor colorWithWhite:0.14 alpha:1];self.nameCard.layer.cornerRadius=14;[self.view addSubview:self.nameCard];
    self.nameLabel=[self label:@"素材名称" size:14];[self.nameCard addSubview:self.nameLabel];
    self.nameField=[UITextField new];self.nameField.text=self.initialName;self.nameField.placeholder=@"相册素材";self.nameField.textColor=UIColor.whiteColor;
    self.nameField.font=[UIFont systemFontOfSize:16];self.nameField.clearButtonMode=UITextFieldViewModeWhileEditing;self.nameField.returnKeyType=UIReturnKeyDone;
    self.nameField.accessibilityLabel=@"素材名称";
    [self.nameField addTarget:self.nameField action:@selector(resignFirstResponder)forControlEvents:UIControlEventEditingDidEndOnExit];[self.nameCard addSubview:self.nameField];
    self.canvas=[[MTFrameMaterialCanvas alloc]initWithFrame:CGRectZero];self.canvas.image=self.preview;
    self.canvas.pixelSize=CGSizeMake(CGImageGetWidth(self.source.CGImage),CGImageGetHeight(self.source.CGImage));self.canvas.quad=self.initialQuad;[self.view addSubview:self.canvas];
    self.canvasLabel=[self label:@"实时合成" size:13];[self.canvas addSubview:self.canvasLabel];
    self.hint=[self label:@"双指缩放 · 拖动画布 · 拖动四角贴边" size:12];self.hint.textAlignment=NSTextAlignmentCenter;[self.view addSubview:self.hint];
    self.corners=[[UISegmentedControl alloc]initWithItems:@[@"左上",@"右上",@"右下",@"左下"]];self.corners.selectedSegmentIndex=0;
    self.corners.selectedSegmentTintColor=MTMaterialAccent();[self.corners setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.blackColor}forState:UIControlStateSelected];
    self.corners.accessibilityLabel=@"选择微调的屏幕角";[self.corners addTarget:self action:@selector(cornerChanged:)forControlEvents:UIControlEventValueChanged];[self.view addSubview:self.corners];
    NSMutableArray *buttons=[NSMutableArray new];NSArray *symbols=@[@"arrow.left",@"arrow.up",@"arrow.down",@"arrow.right"];
    NSArray *names=@[@"向左微调 1 像素",@"向上微调 1 像素",@"向下微调 1 像素",@"向右微调 1 像素"];
    for(NSInteger i=0;i<4;i++){UIButton *button=[self button:@"" selector:@selector(nudge:)];button.tag=i;
        [button setImage:[UIImage systemImageNamed:symbols[i]]forState:UIControlStateNormal];button.accessibilityLabel=names[i];
        button.backgroundColor=[UIColor colorWithWhite:0.16 alpha:1];button.layer.cornerRadius=10;[buttons addObject:button];}
    [buttons addObject:[self button:@"重置" selector:@selector(reset)]];
    self.arrows=[[UIStackView alloc]initWithArrangedSubviews:buttons];self.arrows.spacing=8;self.arrows.distribution=UIStackViewDistributionFillEqually;[self.view addSubview:self.arrows];
    self.radiusCard=[UIView new];self.radiusCard.backgroundColor=[UIColor colorWithWhite:0.14 alpha:1];self.radiusCard.layer.cornerRadius=14;[self.view addSubview:self.radiusCard];
    self.radiusLabel=[self label:@"屏幕圆角" size:14];self.radiusLabel.textColor=UIColor.whiteColor;[self.radiusCard addSubview:self.radiusLabel];
    self.radiusValue=[self label:@"" size:14];self.radiusValue.textAlignment=NSTextAlignmentRight;[self.radiusCard addSubview:self.radiusValue];
    self.radiusSlider=[UISlider new];self.radiusSlider.minimumValue=0;self.radiusSlider.maximumValue=100;self.radiusSlider.value=self.initialRadius;
    self.radiusSlider.accessibilityLabel=@"屏幕圆角";
    self.radiusMode=[[UISegmentedControl alloc]initWithItems:@[@"原遮罩",@"手动圆角"]];self.radiusMode.hidden=!self.transparent;
    self.radiusMode.selectedSegmentIndex=self.manualRadius ? 1 : 0;self.radiusMode.selectedSegmentTintColor=MTMaterialAccent();
    [self.radiusMode setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.blackColor}forState:UIControlStateSelected];
    self.radiusMode.accessibilityLabel=@"圆角模式";[self.radiusMode addTarget:self action:@selector(radiusModeChanged:)forControlEvents:UIControlEventValueChanged];
    [self.radiusCard addSubview:self.radiusMode];
    [self.radiusSlider addTarget:self action:@selector(radiusChanged:)forControlEvents:UIControlEventValueChanged];[self.radiusCard addSubview:self.radiusSlider];
    self.saveButton=[self button:@"保存素材" selector:@selector(save)];self.saveButton.backgroundColor=MTMaterialAccent();self.saveButton.layer.cornerRadius=14;
    self.saveButton.titleLabel.font=[UIFont boldSystemFontOfSize:17];[self.saveButton setTitleColor:UIColor.blackColor forState:UIControlStateNormal];[self.view addSubview:self.saveButton];
    self.spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];self.spinner.hidesWhenStopped=YES;[self.canvas addSubview:self.spinner];
    __weak typeof(self) weakSelf=self;self.canvas.changed=^{__strong typeof(weakSelf) self=weakSelf;if(!self)return;self.corners.selectedSegmentIndex=self.canvas.selectedCorner;[self schedulePreview];};
    self.canvas.viewportChanged=^{
        __strong typeof(weakSelf) self=weakSelf;if(!self)return;
        BOOL high=self.canvas.zoomScale>1.01;if(high==self.highDetailPreview)return;
        self.highDetailPreview=high;[self schedulePreview];
    };
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:)name:UIKeyboardWillChangeFrameNotification object:nil];
    [self schedulePreview];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];CGRect safe=UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
    CGFloat left=safe.origin.x+16,top=safe.origin.y+10,w=safe.size.width-32,bottom=CGRectGetMaxY(safe)-8;
    BOOL wide=w>600 || (w>safe.size.height && w>400);
    // 名称编辑时让输入框保持在键盘上方；收起后恢复完整的固定画布。
    if(self.keyboardHeight>0)bottom=MIN(bottom,self.view.bounds.size.height-self.keyboardHeight-8);
    CGFloat controlLeft=left,controlWidth=w;
    if(wide){controlWidth=MIN(340,w*0.48);controlLeft=left+w-controlWidth;self.canvas.frame=CGRectMake(left,top,w-controlWidth-12,bottom-top);}
    BOOL compact=wide && bottom-top<310;
    CGFloat nameHeight=compact ? 36 : 48,saveHeight=compact ? 40 : 48;
    CGFloat radiusHeight=(compact ? 44 : 52)+(self.transparent ? 36 : 0),arrowHeight=compact ? 40 : 44,cornerHeight=compact ? 32 : 36,gap=compact ? 6 : 8;
    BOOL tight=compact && self.transparent;
    if(tight){nameHeight=28;saveHeight=36;radiusHeight=64;arrowHeight=36;cornerHeight=28;gap=3;}
    self.nameCard.frame=CGRectMake(controlLeft,top,controlWidth,nameHeight);
    self.nameLabel.frame=CGRectMake(12,0,74,nameHeight);self.nameField.frame=CGRectMake(94,0,MAX(1,controlWidth-106),nameHeight);
    self.saveButton.frame=CGRectMake(controlLeft,bottom-saveHeight,controlWidth,saveHeight);
    self.radiusCard.frame=CGRectMake(controlLeft,CGRectGetMinY(self.saveButton.frame)-gap-radiusHeight,controlWidth,radiusHeight);
    if(self.transparent) {
        CGFloat row=tight ? 30 : 40;
        self.radiusLabel.frame=CGRectMake(12,0,72,row);self.radiusMode.frame=CGRectMake(88,2,MAX(1,controlWidth-100),row-4);
        self.radiusSlider.frame=CGRectMake(12,row,MAX(1,controlWidth-82),radiusHeight-row);
        self.radiusValue.frame=CGRectMake(controlWidth-62,row,50,radiusHeight-row);
    } else {
        self.radiusLabel.frame=CGRectMake(12,0,72,radiusHeight);self.radiusValue.frame=CGRectMake(controlWidth-62,0,50,radiusHeight);
        self.radiusSlider.frame=CGRectMake(90,0,MAX(1,controlWidth-160),radiusHeight);
    }
    self.arrows.frame=CGRectMake(controlLeft,CGRectGetMinY(self.radiusCard.frame)-gap-arrowHeight,controlWidth,arrowHeight);
    self.corners.frame=CGRectMake(controlLeft,CGRectGetMinY(self.arrows.frame)-gap-cornerHeight,controlWidth,cornerHeight);
    self.hint.frame=CGRectMake(controlLeft,CGRectGetMinY(self.corners.frame)-gap-18,controlWidth,18);
    if(!wide){CGFloat y=CGRectGetMaxY(self.nameCard.frame)+10;self.canvas.frame=CGRectMake(left,y,w,MAX(60,CGRectGetMinY(self.hint.frame)-8-y));}
    self.canvasLabel.frame=CGRectMake(12,10,MAX(1,self.canvas.bounds.size.width-204),20);
    self.spinner.center=CGPointMake(CGRectGetMidX(self.canvas.bounds),CGRectGetMidY(self.canvas.bounds));
}
- (void)keyboardChanged:(NSNotification *)notification {
    CGRect screen=[notification.userInfo[UIKeyboardFrameEndUserInfoKey]CGRectValue];
    CGRect local=[self.view convertRect:screen fromView:nil];
    self.keyboardHeight=MAX(0,self.view.bounds.size.height-CGRectGetMinY(local));[self.view setNeedsLayout];
}
- (void)cornerChanged:(UISegmentedControl *)sender {self.canvas.selectedCorner=sender.selectedSegmentIndex;[self.canvas focusSelectedCorner];[self.canvas setNeedsDisplay];}
- (void)nudge:(UIButton *)sender {
    CGPoint delta[]={CGPointMake(-1,0),CGPointMake(0,-1),CGPointMake(0,1),CGPointMake(1,0)};
    if(sender.tag>=0 && sender.tag<4)[self.canvas moveCorner:delta[sender.tag]];
}
- (void)reset {self.canvas.quad=self.initialQuad;self.radiusSlider.value=self.initialRadius;self.manualRadius=self.initialManualRadius;[self.canvas setNeedsLayout];[self schedulePreview];}
- (void)radiusChanged:(UISlider *)sender {sender.value=round(sender.value);if(self.transparent)self.manualRadius=YES;[self schedulePreview];}
- (void)radiusModeChanged:(UISegmentedControl *)sender {
    self.manualRadius=sender.selectedSegmentIndex==1;
    if(self.manualRadius && self.radiusSlider.value==0)self.radiusSlider.value=24;
    [self schedulePreview];
}
- (void)updateSaveState {
    BOOL enabled=self.previewReady && !self.saving && !self.invalidated;
    self.navigationItem.rightBarButtonItem.enabled=enabled;self.saveButton.enabled=enabled;
}
- (void)schedulePreview {
    if(self.invalidated || self.saving)return;
    self.radiusMode.selectedSegmentIndex=self.manualRadius ? 1 : 0;
    self.radiusValue.text=self.transparent && !self.manualRadius ? @"原遮罩" : [NSString stringWithFormat:@"%.0f",self.radiusSlider.value];
    self.radiusSlider.accessibilityValue=self.radiusValue.text;
    self.generation++;self.pendingRender=YES;self.previewReady=NO;[self updateSaveState];[self.spinner startAnimating];[self renderNextPreview];
}
- (void)renderNextPreview {
    if(self.invalidated || self.rendering || !self.pendingRender)return;
    self.pendingRender=NO;self.rendering=YES;NSUInteger generation=self.generation;
    MTDeviceFrameQuad q=self.canvas.quad;CGSize original=self.canvas.pixelSize;
    UIImage *preview=self.highDetailPreview ? self.detailPreview : self.preview;
    UIImage *source=self.source,*screenshot=self.screenshot;BOOL high=self.highDetailPreview,adjust=self.transparent && self.manualRadius;CGFloat radius=self.radiusSlider.value;
    __weak typeof(self) weakSelf=self;
    dispatch_async(self.renderQueue,^{@autoreleasepool {
        UIImage *working=preview ?: [MTDeviceFramePhotoMaterial previewForImage:source maximumEdge:high ? 2400 : 1200];
        CGSize size=working.CGImage ? CGSizeMake(CGImageGetWidth(working.CGImage),CGImageGetHeight(working.CGImage)) : CGSizeZero;
        CGFloat sx=size.width/original.width,sy=size.height/original.height;
        MTDeviceFrameQuad scaled={CGPointMake(q.topLeft.x*sx,q.topLeft.y*sy),CGPointMake(q.topRight.x*sx,q.topRight.y*sy),CGPointMake(q.bottomRight.x*sx,q.bottomRight.y*sy),CGPointMake(q.bottomLeft.x*sx,q.bottomLeft.y*sy)};
        UIImage *overlay=[MTDeviceFramePhotoMaterial overlayForImage:working screenQuad:scaled cutout:YES cornerRadius:radius error:nil];
        UIImage *result=overlay ? [MTDeviceFrameRenderer renderImage:screenshot overlay:overlay screenQuad:scaled cornerRadius:adjust ? radius : 0] : nil;
        dispatch_async(dispatch_get_main_queue(),^{
            __strong typeof(weakSelf) self=weakSelf;if(!self || self.invalidated)return;self.rendering=NO;
            if(high && working)self.detailPreview=working;
            if(generation==self.generation){self.canvas.image=result ?: working;[self.canvas setNeedsDisplay];self.previewReady=result!=nil;
                self.canvasLabel.text=result ? @"实时合成" : @"预览失败，请调整四角后重试";[self.spinner stopAnimating];[self updateSaveState];}
            [self renderNextPreview];
        });
    }});
}
- (void)save {
    if(self.saving || self.invalidated || !self.previewReady)return;
    [self.view endEditing:YES];self.saving=YES;[self updateSaveState];
    self.canvas.userInteractionEnabled=NO;self.corners.enabled=NO;self.arrows.userInteractionEnabled=NO;self.radiusSlider.enabled=NO;self.radiusMode.enabled=NO;self.nameField.enabled=NO;
    UIImage *source=self.source;MTDeviceFrameQuad q=self.canvas.quad;CGFloat radius=self.radiusSlider.value;BOOL adjust=self.transparent && self.manualRadius;
    NSString *name=[self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!name.length)name=@"相册素材";
    NSProgress *operation=[NSProgress progressWithTotalUnitCount:1];self.operation=operation;__weak typeof(self) weakSelf=self;
    dispatch_async(self.renderQueue,^{@autoreleasepool {
        NSError *error=nil;MTDeviceFrameTemplate *frame=operation.cancelled ? nil : [MTDeviceFramePhotoMaterial importImage:source name:name screenQuad:q cornerRadius:radius adjustTransparentCorners:adjust error:&error];
        dispatch_async(dispatch_get_main_queue(),^{
            __strong typeof(weakSelf) self=weakSelf;
            if(!self || self.invalidated || operation.cancelled){if(frame)dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{[MTDeviceFrameTemplateStore removeTemplate:frame error:nil];});return;}
            self.operation=nil;self.saving=NO;[self updateSaveState];
            self.canvas.userInteractionEnabled=YES;self.corners.enabled=YES;self.arrows.userInteractionEnabled=YES;self.radiusSlider.enabled=YES;self.radiusMode.enabled=YES;self.nameField.enabled=YES;
            if(!frame){UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"保存失败" message:error.localizedDescription ?: @"请重试" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil];return;}
            [self finish:frame];
        });
    }});
}
- (void)finish:(MTDeviceFrameTemplate *)frame {void (^completion)(MTDeviceFrameTemplate *)=self.completion;[self invalidate];if(completion)completion(frame);}
- (void)cancel {[self finish:nil];}
- (void)invalidate {
    self.invalidated=YES;self.generation++;self.pendingRender=NO;self.completion=nil;[self.operation cancel];self.operation=nil;
    [self.canvas invalidate];self.source=nil;self.preview=nil;self.detailPreview=nil;self.screenshot=nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)dealloc {[_operation cancel];[_canvas invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
