#import "MTDeviceFramePhotoMaterialController.h"
#import "MTDeviceFrameRenderer.h"
#import "MTDeviceFrameViewController.h"

static UIColor *MTMaterialAccent(void){return [UIColor colorWithRed:1 green:0.78 blue:0.08 alpha:1];}

@interface MTFrameMaterialCanvas : UIView
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) CGSize pixelSize;
@property (nonatomic) MTDeviceFrameQuad quad;
@property (nonatomic) NSInteger selectedCorner;
@property (nonatomic, strong) NSArray<UIButton *> *handles;
@property (nonatomic, copy) void (^changed)(void);
- (void)moveCorner:(CGPoint)delta;
- (void)invalidate;
@end

@implementation MTFrameMaterialCanvas
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=[UIColor colorWithWhite:0.14 alpha:1];self.layer.cornerRadius=16;self.clipsToBounds=YES;
        NSArray *names=@[@"屏幕左上角",@"屏幕右上角",@"屏幕右下角",@"屏幕左下角"];
        NSMutableArray *handles=[NSMutableArray new];
        for(NSInteger i=0;i<4;i++) {
            UIButton *handle=[UIButton buttonWithType:UIButtonTypeCustom];handle.tag=i;
            [handle setTitle:[NSString stringWithFormat:@"%ld",(long)i+1]forState:UIControlStateNormal];
            [handle setTitleColor:UIColor.blackColor forState:UIControlStateNormal];handle.titleLabel.font=[UIFont boldSystemFontOfSize:12];
            handle.accessibilityLabel=names[i];handle.accessibilityHint=@"拖动定位，也可用下方方向按钮按像素微调";
            [handle addTarget:self action:@selector(selectHandle:)forControlEvents:UIControlEventTouchUpInside];
            [handle addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(drag:)]];
            [self addSubview:handle];[handles addObject:handle];
        }
        self.handles=handles;
    }return self;
}
- (CGRect)imageRect {return MTDeviceFrameAspectFit(self.pixelSize,CGRectInset(self.bounds,26,34));}
- (CGPoint)displayPoint:(CGPoint)p {
    CGRect r=[self imageRect];return CGPointMake(r.origin.x+p.x*r.size.width/self.pixelSize.width,r.origin.y+p.y*r.size.height/self.pixelSize.height);
}
- (void)layoutSubviews {
    [super layoutSubviews];if(self.pixelSize.width<=0 || self.pixelSize.height<=0)return;
    CGPoint points[]={self.quad.topLeft,self.quad.topRight,self.quad.bottomRight,self.quad.bottomLeft};
    for(NSInteger i=0;i<4;i++){self.handles[i].bounds=CGRectMake(0,0,44,44);self.handles[i].center=[self displayPoint:points[i]];}
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    if(!self.image || self.pixelSize.width<=0 || self.pixelSize.height<=0)return;
    [self.image drawInRect:[self imageRect]];
    UIBezierPath *path=[UIBezierPath bezierPath];CGPoint p[]={self.quad.topLeft,self.quad.topRight,self.quad.bottomRight,self.quad.bottomLeft};
    [path moveToPoint:[self displayPoint:p[0]]];for(NSUInteger i=1;i<4;i++)[path addLineToPoint:[self displayPoint:p[i]]];[path closePath];
    [MTMaterialAccent()setStroke];path.lineWidth=1.5;[path stroke];
    for(NSUInteger i=0;i<4;i++) {
        CGPoint center=[self displayPoint:p[i]];CGFloat radius=(NSInteger)i==self.selectedCorner ? 11 : 9;
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
    self.selectedCorner=gesture.view.tag;CGRect r=[self imageRect];if(r.size.width<=0 || r.size.height<=0)return;
    CGPoint delta=[gesture translationInView:self];[gesture setTranslation:CGPointZero inView:self];
    [self moveCorner:CGPointMake(delta.x*self.pixelSize.width/r.size.width,delta.y*self.pixelSize.height/r.size.height)];
}
- (void)invalidate {
    self.changed=nil;self.image=nil;
    for(UIButton *handle in self.handles)for(UIGestureRecognizer *gesture in [handle.gestureRecognizers copy])[handle removeGestureRecognizer:gesture];
}
@end

@interface MTDeviceFramePhotoMaterialController ()
@property (nonatomic, strong) UIImage *source;
@property (nonatomic, strong) UIImage *preview;
@property (nonatomic, strong) MTFrameMaterialCanvas *canvas;
@property (nonatomic) MTDeviceFrameQuad initialQuad;
@property (nonatomic) CGFloat initialRadius;
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
    self.hint=[self label:self.transparent ? @"拖动四角贴合屏幕 · 保留原素材开孔" : @"拖动四角，让截图贴合屏幕" size:12];self.hint.textAlignment=NSTextAlignmentCenter;[self.view addSubview:self.hint];
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
    self.radiusSlider.enabled=!self.transparent;self.radiusSlider.accessibilityLabel=@"屏幕圆角";
    [self.radiusSlider addTarget:self action:@selector(radiusChanged:)forControlEvents:UIControlEventValueChanged];[self.radiusCard addSubview:self.radiusSlider];
    self.saveButton=[self button:@"保存素材" selector:@selector(save)];self.saveButton.backgroundColor=MTMaterialAccent();self.saveButton.layer.cornerRadius=14;
    self.saveButton.titleLabel.font=[UIFont boldSystemFontOfSize:17];[self.saveButton setTitleColor:UIColor.blackColor forState:UIControlStateNormal];[self.view addSubview:self.saveButton];
    self.spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];self.spinner.hidesWhenStopped=YES;[self.canvas addSubview:self.spinner];
    __weak typeof(self) weakSelf=self;self.canvas.changed=^{__strong typeof(weakSelf) self=weakSelf;if(!self)return;self.corners.selectedSegmentIndex=self.canvas.selectedCorner;[self schedulePreview];};
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
    CGFloat radiusHeight=compact ? 44 : 52,arrowHeight=compact ? 40 : 44,cornerHeight=compact ? 32 : 36,gap=compact ? 6 : 8;
    self.nameCard.frame=CGRectMake(controlLeft,top,controlWidth,nameHeight);
    self.nameLabel.frame=CGRectMake(12,0,74,nameHeight);self.nameField.frame=CGRectMake(94,0,MAX(1,controlWidth-106),nameHeight);
    self.saveButton.frame=CGRectMake(controlLeft,bottom-saveHeight,controlWidth,saveHeight);
    self.radiusCard.frame=CGRectMake(controlLeft,CGRectGetMinY(self.saveButton.frame)-gap-radiusHeight,controlWidth,radiusHeight);
    self.radiusLabel.frame=CGRectMake(12,0,72,radiusHeight);self.radiusValue.frame=CGRectMake(controlWidth-62,0,50,radiusHeight);
    self.radiusSlider.frame=CGRectMake(90,0,MAX(1,controlWidth-160),radiusHeight);
    self.arrows.frame=CGRectMake(controlLeft,CGRectGetMinY(self.radiusCard.frame)-gap-arrowHeight,controlWidth,arrowHeight);
    self.corners.frame=CGRectMake(controlLeft,CGRectGetMinY(self.arrows.frame)-gap-cornerHeight,controlWidth,cornerHeight);
    self.hint.frame=CGRectMake(controlLeft,CGRectGetMinY(self.corners.frame)-gap-18,controlWidth,18);
    if(!wide){CGFloat y=CGRectGetMaxY(self.nameCard.frame)+10;self.canvas.frame=CGRectMake(left,y,w,MAX(60,CGRectGetMinY(self.hint.frame)-8-y));}
    self.canvasLabel.frame=CGRectMake(12,7,MAX(1,self.canvas.bounds.size.width-24),20);
    self.spinner.center=CGPointMake(CGRectGetMidX(self.canvas.bounds),CGRectGetMidY(self.canvas.bounds));
}
- (void)keyboardChanged:(NSNotification *)notification {
    CGRect screen=[notification.userInfo[UIKeyboardFrameEndUserInfoKey]CGRectValue];
    CGRect local=[self.view convertRect:screen fromView:nil];
    self.keyboardHeight=MAX(0,self.view.bounds.size.height-CGRectGetMinY(local));[self.view setNeedsLayout];
}
- (void)cornerChanged:(UISegmentedControl *)sender {self.canvas.selectedCorner=sender.selectedSegmentIndex;[self.canvas setNeedsDisplay];}
- (void)nudge:(UIButton *)sender {
    CGPoint delta[]={CGPointMake(-1,0),CGPointMake(0,-1),CGPointMake(0,1),CGPointMake(1,0)};
    if(sender.tag>=0 && sender.tag<4)[self.canvas moveCorner:delta[sender.tag]];
}
- (void)reset {self.canvas.quad=self.initialQuad;self.radiusSlider.value=self.initialRadius;[self.canvas setNeedsLayout];[self schedulePreview];}
- (void)radiusChanged:(UISlider *)sender {sender.value=round(sender.value);[self schedulePreview];}
- (void)updateSaveState {
    BOOL enabled=self.previewReady && !self.saving && !self.invalidated;
    self.navigationItem.rightBarButtonItem.enabled=enabled;self.saveButton.enabled=enabled;
}
- (void)schedulePreview {
    if(self.invalidated || self.saving)return;
    self.radiusValue.text=self.transparent ? @"原遮罩" : [NSString stringWithFormat:@"%.0f",self.radiusSlider.value];
    self.radiusSlider.accessibilityValue=self.radiusValue.text;
    self.generation++;self.pendingRender=YES;self.previewReady=NO;[self updateSaveState];[self.spinner startAnimating];[self renderNextPreview];
}
- (void)renderNextPreview {
    if(self.invalidated || self.rendering || !self.pendingRender)return;
    self.pendingRender=NO;self.rendering=YES;NSUInteger generation=self.generation;
    MTDeviceFrameQuad q=self.canvas.quad;CGSize original=self.canvas.pixelSize;
    UIImage *preview=self.preview,*screenshot=self.screenshot;CGFloat radius=self.radiusSlider.value;
    __weak typeof(self) weakSelf=self;
    dispatch_async(self.renderQueue,^{@autoreleasepool {
        CGSize size=CGSizeMake(CGImageGetWidth(preview.CGImage),CGImageGetHeight(preview.CGImage));
        CGFloat sx=size.width/original.width,sy=size.height/original.height;
        MTDeviceFrameQuad scaled={CGPointMake(q.topLeft.x*sx,q.topLeft.y*sy),CGPointMake(q.topRight.x*sx,q.topRight.y*sy),CGPointMake(q.bottomRight.x*sx,q.bottomRight.y*sy),CGPointMake(q.bottomLeft.x*sx,q.bottomLeft.y*sy)};
        UIImage *overlay=[MTDeviceFramePhotoMaterial overlayForImage:preview screenQuad:scaled cutout:YES cornerRadius:radius error:nil];
        UIImage *result=overlay ? [MTDeviceFrameRenderer renderImage:screenshot overlay:overlay screenQuad:scaled] : nil;
        dispatch_async(dispatch_get_main_queue(),^{
            __strong typeof(weakSelf) self=weakSelf;if(!self || self.invalidated)return;self.rendering=NO;
            if(generation==self.generation){self.canvas.image=result ?: preview;[self.canvas setNeedsDisplay];self.previewReady=result!=nil;
                self.canvasLabel.text=result ? @"实时合成" : @"预览失败，请调整四角后重试";[self.spinner stopAnimating];[self updateSaveState];}
            [self renderNextPreview];
        });
    }});
}
- (void)save {
    if(self.saving || self.invalidated || !self.previewReady)return;
    [self.view endEditing:YES];self.saving=YES;[self updateSaveState];
    self.canvas.userInteractionEnabled=NO;self.corners.enabled=NO;self.arrows.userInteractionEnabled=NO;self.radiusSlider.enabled=NO;self.nameField.enabled=NO;
    UIImage *source=self.source;MTDeviceFrameQuad q=self.canvas.quad;CGFloat radius=self.radiusSlider.value;
    NSString *name=[self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!name.length)name=@"相册素材";
    NSProgress *operation=[NSProgress progressWithTotalUnitCount:1];self.operation=operation;__weak typeof(self) weakSelf=self;
    dispatch_async(self.renderQueue,^{@autoreleasepool {
        NSError *error=nil;MTDeviceFrameTemplate *frame=operation.cancelled ? nil : [MTDeviceFramePhotoMaterial importImage:source name:name screenQuad:q cornerRadius:radius error:&error];
        dispatch_async(dispatch_get_main_queue(),^{
            __strong typeof(weakSelf) self=weakSelf;
            if(!self || self.invalidated || operation.cancelled){if(frame)dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{[MTDeviceFrameTemplateStore removeTemplate:frame error:nil];});return;}
            self.operation=nil;self.saving=NO;[self updateSaveState];
            self.canvas.userInteractionEnabled=YES;self.corners.enabled=YES;self.arrows.userInteractionEnabled=YES;self.radiusSlider.enabled=!self.transparent;self.nameField.enabled=YES;
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
    [self.canvas invalidate];self.source=nil;self.preview=nil;self.screenshot=nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)dealloc {[_operation cancel];[_canvas invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
