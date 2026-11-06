#import "MTDeviceFramePhotoMaterialController.h"

static UIColor *MTMaterialAccent(void){return [UIColor colorWithRed:1 green:0.78 blue:0.08 alpha:1];}

@interface MTFrameMaterialCanvas : UIView
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) CGSize pixelSize;
@property (nonatomic) MTDeviceFrameQuad quad;
@property (nonatomic, strong) NSArray<UIButton *> *handles;
- (void)invalidate;
@end

@implementation MTFrameMaterialCanvas
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=[UIColor colorWithWhite:0.18 alpha:1];self.layer.cornerRadius=14;self.clipsToBounds=YES;
        NSArray *names=@[@"屏幕左上角",@"屏幕右上角",@"屏幕右下角",@"屏幕左下角"];
        NSMutableArray *handles=[NSMutableArray new];
        for(NSInteger i=0;i<4;i++) {
            UIButton *handle=[UIButton buttonWithType:UIButtonTypeCustom];handle.tag=i;
            handle.backgroundColor=MTMaterialAccent();handle.layer.cornerRadius=22;
            [handle setTitle:[NSString stringWithFormat:@"%ld",(long)i+1] forState:UIControlStateNormal];
            [handle setTitleColor:UIColor.blackColor forState:UIControlStateNormal];handle.accessibilityLabel=names[i];
            [handle addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(drag:)]];
            [self addSubview:handle];[handles addObject:handle];
        }
        self.handles=handles;
    }return self;
}
- (CGRect)imageRect { return MTDeviceFrameAspectFit(self.pixelSize,CGRectInset(self.bounds,24,24)); }
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
    UIBezierPath *quad=[UIBezierPath bezierPath];
    CGPoint points[]={self.quad.topLeft,self.quad.topRight,self.quad.bottomRight,self.quad.bottomLeft};
    [quad moveToPoint:[self displayPoint:points[0]]];for(NSInteger i=1;i<4;i++)[quad addLineToPoint:[self displayPoint:points[i]]];[quad closePath];
    [[MTMaterialAccent() colorWithAlphaComponent:0.16]setFill];[quad fill];
    [MTMaterialAccent()setStroke];quad.lineWidth=2;[quad stroke];
}
- (void)drag:(UIPanGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateChanged)return;
    CGRect r=[self imageRect];if(r.size.width<=0 || r.size.height<=0)return;
    CGPoint delta=[gesture translationInView:self];[gesture setTranslation:CGPointZero inView:self];
    MTDeviceFrameQuad candidate=self.quad;
    CGPoint *point=NULL;
    switch(gesture.view.tag){case 0:point=&candidate.topLeft;break;case 1:point=&candidate.topRight;break;
        case 2:point=&candidate.bottomRight;break;case 3:point=&candidate.bottomLeft;break;default:return;}
    point->x=MAX(0,MIN(self.pixelSize.width,point->x+delta.x*self.pixelSize.width/r.size.width));
    point->y=MAX(0,MIN(self.pixelSize.height,point->y+delta.y*self.pixelSize.height/r.size.height));
    if(MTDeviceFrameValidQuad(candidate,self.pixelSize)){self.quad=candidate;[self setNeedsLayout];}
}
- (void)invalidate {
    for(UIButton *handle in self.handles)for(UIGestureRecognizer *gesture in [handle.gestureRecognizers copy])[handle removeGestureRecognizer:gesture];
    self.image=nil;
}
@end

@interface MTDeviceFramePhotoMaterialController ()
@property (nonatomic, strong) UIImage *source;
@property (nonatomic, strong) UIImage *preview;
@property (nonatomic, strong) MTFrameMaterialCanvas *canvas;
@property (nonatomic) MTDeviceFrameQuad initialQuad;
@property (nonatomic) BOOL cutout;
@property (nonatomic) BOOL saving;
@property (nonatomic) BOOL invalidated;
@property (nonatomic) BOOL recalibrating;
@property (nonatomic, copy) NSString *initialName;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) NSProgress *operation;
@property (nonatomic, copy) void (^completion)(MTDeviceFrameTemplate *);
@end

@implementation MTDeviceFramePhotoMaterialController
- (instancetype)initWithImage:(UIImage *)image preview:(UIImage *)preview suggestedQuad:(MTDeviceFrameQuad)quad
            transparentScreen:(BOOL)transparent completion:(void (^)(MTDeviceFrameTemplate *))completion {
    if((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        _source=image;_preview=preview;_initialQuad=quad;_cutout=!transparent;_completion=[completion copy];_initialName=@"相册素材";
        self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    }return self;
}
- (instancetype)initWithTemplate:(MTDeviceFrameTemplate *)frame image:(UIImage *)image preview:(UIImage *)preview
                     completion:(void (^)(MTDeviceFrameTemplate *))completion {
    if((self=[self initWithImage:image preview:preview suggestedQuad:frame.screenQuad transparentScreen:YES completion:completion])) {
        _recalibrating=YES;_initialName=[frame.name stringByAppendingString:@"（校准）"];
    }return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=self.recalibrating ? @"定位素材四角" : @"校准套壳素材";self.view.tintColor=MTMaterialAccent();self.modalInPresentation=YES;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:self.recalibrating ? @"另存素材" : @"导入" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.canvas=[[MTFrameMaterialCanvas alloc]initWithFrame:CGRectZero];self.canvas.image=self.preview;
    self.canvas.pixelSize=CGSizeMake(CGImageGetWidth(self.source.CGImage),CGImageGetHeight(self.source.CGImage));self.canvas.quad=self.initialQuad;
    self.tableView.tableHeaderView=self.canvas;self.tableView.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=56;
    self.nameField=[UITextField new];self.nameField.text=self.initialName;self.nameField.placeholder=@"素材名称";
    self.nameField.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];self.nameField.clearButtonMode=UITextFieldViewModeWhileEditing;
    self.nameField.returnKeyType=UIReturnKeyDone;
    [self.nameField addTarget:self.nameField action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];CGFloat width=self.tableView.bounds.size.width,height=MAX(220,MIN(500,self.view.bounds.size.height*0.58));
    if(self.canvas.frame.size.width!=width || self.canvas.frame.size.height!=height){self.canvas.frame=CGRectMake(0,0,width,height);self.tableView.tableHeaderView=self.canvas;}
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return 2;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    if(path.row==0){
        self.nameField.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:self.nameField];
        [NSLayoutConstraint activateConstraints:@[[self.nameField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [self.nameField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [self.nameField.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [self.nameField.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
            [self.nameField.heightAnchor constraintGreaterThanOrEqualToConstant:32]]];
    }else{
        cell.textLabel.text=@"挖空所选屏幕区域";cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];cell.textLabel.numberOfLines=0;
        UISwitch *toggle=[UISwitch new];toggle.on=self.cutout;toggle.onTintColor=MTMaterialAccent();
        [toggle addTarget:self action:@selector(cutoutChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;
    }cell.contentView.userInteractionEnabled=!self.saving;return cell;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if(self.recalibrating)return @"拖动四角定位屏幕：1 左上、2 右上、3 右下、4 左下。保存为新素材并自动选中，原素材保留。默认保留已有透明开孔和摄像头遮罩；开启挖空会额外清除所选区域。保存配置后，截图继续自动套壳输出。";
    return @"拖动四角对齐机壳屏幕：1 左上、2 右上、3 右下、4 左下。透明 PNG 已有屏幕开孔时可关闭挖空，保留圆角和摄像头遮罩；普通图片请开启。此步骤仅在导入素材时进行，截图后仍自动套壳输出。";
}
- (void)cutoutChanged:(UISwitch *)sender{self.cutout=sender.on;}
- (void)save {
    if(self.saving || self.invalidated)return;
    [self.view endEditing:YES];self.saving=YES;self.navigationItem.rightBarButtonItem.enabled=NO;self.tableView.userInteractionEnabled=NO;
    UIImage *source=self.source;MTDeviceFrameQuad quad=self.canvas.quad;BOOL cutout=self.cutout;
    NSString *name=[self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!name.length)name=@"相册素材";
    NSProgress *operation=[NSProgress progressWithTotalUnitCount:1];self.operation=operation;
    __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {
            NSError *error=nil;
            MTDeviceFrameTemplate *frame=operation.cancelled ? nil : [MTDeviceFramePhotoMaterial importImage:source name:name screenQuad:quad cutout:cutout error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self=weakSelf;
                if(!self || self.invalidated || operation.cancelled){
                    if(frame)dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{[MTDeviceFrameTemplateStore removeTemplate:frame error:nil];});
                    return;
                }
                self.operation=nil;self.saving=NO;self.navigationItem.rightBarButtonItem.enabled=YES;self.tableView.userInteractionEnabled=YES;
                if(!frame){
                    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"导入失败" message:error.localizedDescription ?: @"请重试" preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil];return;
                }
                [self finish:frame];
            });
        }
    });
}
- (void)finish:(MTDeviceFrameTemplate *)frame {
    void (^completion)(MTDeviceFrameTemplate *)=self.completion;[self invalidate];if(completion)completion(frame);
}
- (void)cancel{[self finish:nil];}
- (void)invalidate {
    self.invalidated=YES;self.completion=nil;[self.operation cancel];self.operation=nil;
    [self.canvas invalidate];self.source=nil;self.preview=nil;
}
- (void)dealloc{[_operation cancel];[_canvas invalidate];}
@end
