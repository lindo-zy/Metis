#import "MTDeviceFrameViewController.h"
#import "MTDeviceFrameRenderer.h"
#import "MTDeviceFrameTemplateStore.h"
#import "MTDeviceFramePhotoMaterialController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>

static UIColor *MTFrameAccent(void) { return [UIColor colorWithRed:1 green:0.78 blue:0.08 alpha:1]; }
static UIColor *MTFrameCardColor(void) { return [UIColor colorWithWhite:0.14 alpha:1]; }

@interface MTDeviceFrameViewController () <PHPickerViewControllerDelegate>
@property (nonatomic, strong) UIImage *source;
@property (nonatomic, strong) UIImage *previewSource;
@property (nonatomic) CGSize sourcePixels;
@property (nonatomic, strong) MTDeviceFrameConfiguration *style;
@property (nonatomic, copy) NSArray<MTDeviceFrameTemplate *> *templates;
@property (nonatomic, copy) void (^completion)(BOOL, MTDeviceFrameConfiguration *, MTOutputAction);
@property (nonatomic, strong) UIView *navigation;
@property (nonatomic, strong) UIView *previewCard;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UILabel *previewTitle;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UILabel *detail;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIButton *editButton;
@property (nonatomic, strong) UIButton *originalButton;
@property (nonatomic, strong) UIStackView *outputButtons;
@property (nonatomic, strong) UIView *library;
@property (nonatomic, strong) UILabel *libraryTitle;
@property (nonatomic, strong) UILabel *libraryEmpty;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) NSArray<UIButton *> *materialButtons;
@property (nonatomic, strong) UIPageControl *pages;
@property (nonatomic, strong) UIView *options;
@property (nonatomic, strong) UILabel *randomLabel;
@property (nonatomic, strong) UILabel *landscapeLabel;
@property (nonatomic, strong) UISwitch *randomSwitch;
@property (nonatomic, strong) UISwitch *landscapeSwitch;
@property (nonatomic, strong) UILabel *helper;
@property (nonatomic, strong) NSCache<NSString *,UIImage *> *thumbnailCache;
@property (nonatomic) BOOL original;
@property (nonatomic) BOOL invalidated;
@property (nonatomic) BOOL rendering;
@property (nonatomic) BOOL importing;
@property (nonatomic) BOOL pendingRender;
@property (nonatomic) BOOL previewReady;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) dispatch_queue_t renderQueue;
@property (nonatomic, strong) PHPickerViewController *photoPicker;
@property (nonatomic, strong) NSProgress *photoLoadingProgress;
@property (nonatomic, strong) NSProgress *photoOperation;
@property (nonatomic, strong) MTDeviceFramePhotoMaterialController *photoMaterialController;
@end

@implementation MTDeviceFrameViewController
+ (UIImage *)exampleImage {
    CGSize size=CGSizeMake(393,852);
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat new];format.scale=1;format.opaque=YES;
    return [[[UIGraphicsImageRenderer alloc]initWithSize:size format:format]imageWithActions:^(UIGraphicsImageRendererContext *ctx){
        [[UIColor colorWithWhite:0.96 alpha:1]setFill];UIRectFill((CGRect){CGPointZero,size});
        [@"9:41" drawAtPoint:CGPointMake(28,24) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.blackColor}];
        [@"Metis" drawAtPoint:CGPointMake(28,110) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:38 weight:UIFontWeightBold],NSForegroundColorAttributeName:UIColor.blackColor}];
        [@"套壳素材预览" drawAtPoint:CGPointMake(28,164) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:18],NSForegroundColorAttributeName:UIColor.darkGrayColor}];
        NSArray *rows=@[@"截图",@"套壳设置",@"素材编辑",@"自动合成并输出"];
        for (NSUInteger i=0;i<rows.count;i++) {
            CGRect row=CGRectMake(24,230+i*78,345,64);[UIColor.whiteColor setFill];
            [[UIBezierPath bezierPathWithRoundedRect:row cornerRadius:14]fill];
            [rows[i]drawAtPoint:CGPointMake(42,row.origin.y+22)withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:17],NSForegroundColorAttributeName:UIColor.blackColor}];
        }
    }];
}

- (instancetype)initWithImage:(UIImage *)image configuration:(MTDeviceFrameConfiguration *)configuration
                   completion:(void (^)(BOOL,MTDeviceFrameConfiguration *,MTOutputAction))completion {
    if ((self=[super initWithNibName:nil bundle:nil])) {
        _source=image;_sourcePixels=CGSizeMake(image.size.width*image.scale,image.size.height*image.scale);
        _style=[configuration copy] ?: [MTDeviceFrameConfiguration rememberedConfiguration];
        _style.background=0;_style.paddingFraction=0;_style.shadow=NO;
        _completion=[completion copy];_templates=[MTDeviceFrameTemplateStore templates];
        _renderQueue=dispatch_queue_create("com.lindo.metis.capture.frame.preview",DISPATCH_QUEUE_SERIAL);
        _thumbnailCache=[NSCache new];_thumbnailCache.totalCostLimit=4*1024*1024;
        MTDeviceFrameTemplate *frame=[MTDeviceFrameTemplateStore resolveTemplateForConfiguration:_style templates:_templates];
        _style.templateIdentifier=(frame ?: _templates.firstObject).identifier ?: @"";
        self.modalPresentationStyle=UIModalPresentationFullScreen;self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    }return self;
}
- (MTDeviceFrameTemplate *)frame {
    for (MTDeviceFrameTemplate *frame in self.templates) if ([frame.identifier isEqualToString:self.style.templateIdentifier]) return frame;
    return nil;
}
- (UILabel *)label:(NSString *)text size:(CGFloat)size color:(UIColor *)color {
    UILabel *label=[UILabel new];label.text=text;label.font=[UIFont systemFontOfSize:size];label.textColor=color;
    label.adjustsFontSizeToFitWidth=YES;label.minimumScaleFactor=0.75;return label;
}
- (UIButton *)button:(NSString *)title selector:(SEL)selector {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];return button;
}
- (UIView *)card {
    UIView *view=[UIView new];view.backgroundColor=MTFrameCardColor();view.layer.cornerRadius=16;return view;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=[UIColor colorWithWhite:0.06 alpha:1];self.view.tintColor=MTFrameAccent();
    self.title=self.configurationOnly ? @"套壳设置" : @"套壳截图";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(apply)];
    self.navigationItem.rightBarButtonItem.tintColor=MTFrameAccent();
    self.navigation=[UIView new];[self.view addSubview:self.navigation];self.navigation.hidden=self.configurationOnly;
    UIButton *cancel=[self button:@"取消" selector:@selector(cancel)];cancel.tag=1;[self.navigation addSubview:cancel];
    UILabel *title=[self label:self.title size:17 color:UIColor.whiteColor];title.font=[UIFont boldSystemFontOfSize:17];title.textAlignment=NSTextAlignmentCenter;
    title.tag=2;[self.navigation addSubview:title];
    self.applyButton=[self button:@"应用" selector:@selector(apply)];self.applyButton.tag=3;[self.navigation addSubview:self.applyButton];
    self.previewCard=[self card];[self.view addSubview:self.previewCard];
    self.previewTitle=[self label:@"实时预览" size:13 color:UIColor.secondaryLabelColor];[self.previewCard addSubview:self.previewTitle];
    self.originalButton=[self button:@"恢复原图" selector:@selector(restoreOriginal)];self.originalButton.hidden=self.configurationOnly;[self.previewCard addSubview:self.originalButton];
    self.preview=[UIImageView new];self.preview.contentMode=UIViewContentModeScaleAspectFit;
    self.preview.accessibilityLabel=@"完整套壳效果预览";self.preview.isAccessibilityElement=YES;[self.previewCard addSubview:self.preview];
    self.emptyLabel=[self label:@"从相册导入第一份素材\n选择图片后即可定位屏幕四角" size:15 color:UIColor.secondaryLabelColor];
    self.emptyLabel.numberOfLines=2;self.emptyLabel.textAlignment=NSTextAlignmentCenter;[self.previewCard addSubview:self.emptyLabel];
    self.detail=[self label:@"" size:11 color:UIColor.secondaryLabelColor];[self.previewCard addSubview:self.detail];
    self.editButton=[self button:@"编辑素材" selector:@selector(calibrateSelectedTemplate)];
    [self.editButton setImage:[UIImage systemImageNamed:@"pencil"]forState:UIControlStateNormal];
    self.editButton.layer.cornerRadius=12;self.editButton.layer.borderWidth=1;self.editButton.layer.borderColor=MTFrameAccent().CGColor;
    [self.previewCard addSubview:self.editButton];
    self.spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped=YES;[self.previewCard addSubview:self.spinner];
    self.library=[UIView new];[self.view addSubview:self.library];
    self.libraryTitle=[self label:@"我的素材" size:18 color:UIColor.whiteColor];self.libraryTitle.font=[UIFont boldSystemFontOfSize:18];[self.library addSubview:self.libraryTitle];
    self.importButton=[self button:@" 相册导入" selector:@selector(presentPhotoPicker)];self.importButton.backgroundColor=MTFrameAccent();self.importButton.tintColor=UIColor.blackColor;
    [self.importButton setTitleColor:UIColor.blackColor forState:UIControlStateNormal];[self.importButton setImage:[UIImage systemImageNamed:@"photo"]forState:UIControlStateNormal];
    self.importButton.layer.cornerRadius=12;[self.library addSubview:self.importButton];
    self.libraryEmpty=[self label:@"仅支持相册图片素材" size:14 color:UIColor.secondaryLabelColor];self.libraryEmpty.textAlignment=NSTextAlignmentCenter;[self.library addSubview:self.libraryEmpty];
    NSMutableArray *buttons=[NSMutableArray new];
    for (NSInteger i=0;i<3;i++) {
        UIButton *button=[self button:@"" selector:@selector(templateTapped:)];button.backgroundColor=MTFrameCardColor();button.layer.cornerRadius=12;
        UIImageView *image=[UIImageView new];image.tag=101;image.contentMode=UIViewContentModeScaleAspectFit;image.userInteractionEnabled=NO;[button addSubview:image];
        UILabel *name=[self label:@"" size:12 color:UIColor.whiteColor];name.tag=102;name.textAlignment=NSTextAlignmentCenter;[button addSubview:name];
        UIImageView *check=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];check.tag=103;check.tintColor=MTFrameAccent();[button addSubview:check];
        [button addGestureRecognizer:[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(deleteTemplate:)]];
        [self.library addSubview:button];[buttons addObject:button];
    }
    self.materialButtons=buttons;self.pages=[UIPageControl new];self.pages.currentPageIndicatorTintColor=MTFrameAccent();
    self.pages.pageIndicatorTintColor=UIColor.darkGrayColor;[self.pages addTarget:self action:@selector(pageChanged:)forControlEvents:UIControlEventValueChanged];[self.library addSubview:self.pages];
    self.options=[self card];[self.view addSubview:self.options];
    self.randomLabel=[self label:@"随机素材" size:16 color:UIColor.whiteColor];[self.options addSubview:self.randomLabel];
    self.landscapeLabel=[self label:@"自动适配横屏" size:16 color:UIColor.whiteColor];[self.options addSubview:self.landscapeLabel];
    self.randomSwitch=[UISwitch new];self.randomSwitch.onTintColor=MTFrameAccent();self.randomSwitch.tag=6;self.randomSwitch.accessibilityLabel=@"随机素材";
    self.landscapeSwitch=[UISwitch new];self.landscapeSwitch.onTintColor=MTFrameAccent();self.landscapeSwitch.tag=5;self.landscapeSwitch.accessibilityLabel=@"自动适配横屏";
    for (UISwitch *toggle in @[self.randomSwitch,self.landscapeSwitch]) {[toggle addTarget:self action:@selector(switchChanged:)forControlEvents:UIControlEventValueChanged];[self.options addSubview:toggle];}
    self.helper=[self label:@"保存后，套壳截图自动使用当前配置" size:11 color:UIColor.secondaryLabelColor];self.helper.textAlignment=NSTextAlignmentCenter;[self.view addSubview:self.helper];
    self.outputButtons=[[UIStackView alloc]initWithArrangedSubviews:@[[self button:@"复制" selector:@selector(copyOutput)],[self button:@"分享" selector:@selector(shareOutput)],[self button:@"保存" selector:@selector(saveOutput)]]];
    self.outputButtons.spacing=10;self.outputButtons.distribution=UIStackViewDistributionFillEqually;self.outputButtons.hidden=self.configurationOnly;
    for (UIButton *b in self.outputButtons.arrangedSubviews) {b.backgroundColor=MTFrameCardColor();b.layer.cornerRadius=12;}
    UIButton *save=self.outputButtons.arrangedSubviews.lastObject;save.backgroundColor=MTFrameAccent();[save setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [self.view addSubview:self.outputButtons];[self revealSelectedPage];[self refreshControls];[self schedulePreview];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];UIEdgeInsets safe=self.view.safeAreaInsets;
    CGRect bounds=UIEdgeInsetsInsetRect(self.view.bounds,safe);CGFloat gap=12,inset=16;
    CGFloat top=CGRectGetMinY(bounds),width=bounds.size.width-2*inset,left=bounds.origin.x+inset;
    if (!self.configurationOnly) {
        self.navigation.frame=CGRectMake(left,top,width,48);
        [self.navigation viewWithTag:1].frame=CGRectMake(0,0,60,48);
        [self.navigation viewWithTag:2].frame=CGRectMake(65,0,width-130,48);
        self.applyButton.frame=CGRectMake(width-60,0,60,48);top+=48;
    }
    CGFloat bottom=CGRectGetMaxY(bounds)-8;
    if (!self.configurationOnly) {self.outputButtons.frame=CGRectMake(left,bottom-44,width,44);bottom-=56;}
    CGFloat available=bottom-top;BOOL wide=width>600 || (width>bounds.size.height && width>400);
    CGFloat libraryHeight=self.templates.count>3 ? 168 : 148;
    CGFloat optionsHeight=100;
    if(wide && available<300){libraryHeight-=36;optionsHeight=84;}
    BOOL compactOptions=wide && available<250;
    if(compactOptions){optionsHeight=44;libraryHeight=MAX(80,available-optionsHeight-8);}
    self.helper.hidden=compactOptions;
    if (wide) {
        CGFloat rightWidth=MIN(340,width*0.48);CGFloat previewWidth=width-rightWidth-gap;
        self.previewCard.frame=CGRectMake(left,top,previewWidth,available);
        CGFloat x=left+previewWidth+gap;self.library.frame=CGRectMake(x,top,rightWidth,libraryHeight);
        self.options.frame=CGRectMake(x,top+libraryHeight+8,rightWidth,optionsHeight);
        self.helper.frame=CGRectMake(x,CGRectGetMaxY(self.options.frame)+8,rightWidth,18);
    } else {
        self.helper.frame=CGRectMake(left,bottom-18,width,18);
        self.options.frame=CGRectMake(left,CGRectGetMinY(self.helper.frame)-gap-100,width,100);
        self.library.frame=CGRectMake(left,CGRectGetMinY(self.options.frame)-gap-libraryHeight,width,libraryHeight);
        self.previewCard.frame=CGRectMake(left,top,width,MAX(60,CGRectGetMinY(self.library.frame)-top-gap));
    }
    CGRect card=self.previewCard.bounds;CGFloat footer=40;
    self.previewTitle.frame=CGRectMake(12,8,card.size.width-(self.configurationOnly ? 24 : 110),20);
    self.originalButton.frame=CGRectMake(card.size.width-100,0,88,36);
    self.preview.frame=CGRectMake(12,34,card.size.width-24,MAX(1,card.size.height-34-footer));
    self.emptyLabel.frame=self.preview.frame;self.spinner.center=CGPointMake(CGRectGetMidX(card),CGRectGetMidY(card));
    self.editButton.frame=CGRectMake(card.size.width-114,card.size.height-36,102,30);
    self.detail.frame=CGRectMake(12,card.size.height-36,MAX(1,card.size.width-134),30);
    CGFloat w=self.library.bounds.size.width;
    self.libraryTitle.frame=CGRectMake(0,0,MAX(1,w-125),40);self.importButton.frame=CGRectMake(w-116,0,116,40);
    CGFloat itemWidth=(w-20)/3;CGFloat itemHeight=self.library.bounds.size.height-48-(self.templates.count>3 ? 20 : 0);
    for (NSUInteger i=0;i<3;i++) {
        UIButton *b=self.materialButtons[i];b.frame=CGRectMake(i*(itemWidth+10),48,itemWidth,itemHeight);
        [b viewWithTag:101].frame=CGRectMake(5,5,itemWidth-10,itemHeight-29);
        [b viewWithTag:102].frame=CGRectMake(4,itemHeight-24,itemWidth-8,20);
        [b viewWithTag:103].frame=CGRectMake(itemWidth-27,6,21,21);
    }
    self.libraryEmpty.frame=CGRectMake(0,48,w,itemHeight);self.pages.frame=CGRectMake(0,48+itemHeight,w,20);
    CGFloat ow=self.options.bounds.size.width;
    if(compactOptions) {
        CGFloat half=ow/2;
        self.randomLabel.frame=CGRectMake(8,0,MAX(1,half-70),44);self.landscapeLabel.frame=CGRectMake(half+8,0,MAX(1,half-70),44);
        self.randomSwitch.frame=CGRectMake(half-58,6,51,31);self.landscapeSwitch.frame=CGRectMake(ow-58,6,51,31);
    } else {
        CGFloat half=self.options.bounds.size.height/2;
        self.randomLabel.frame=CGRectMake(14,0,MAX(1,ow-88),half);self.landscapeLabel.frame=CGRectMake(14,half,MAX(1,ow-88),half);
        self.randomSwitch.frame=CGRectMake(ow-65,(half-31)/2,51,31);self.landscapeSwitch.frame=CGRectMake(ow-65,half+(half-31)/2,51,31);
    }
}
- (void)revealSelectedPage {
    for (NSUInteger i=0;i<self.templates.count;i++) if ([self.templates[i].identifier isEqualToString:self.style.templateIdentifier]) {self.pages.currentPage=i/3;break;}
}
- (void)refreshControls {
    if (!self.isViewLoaded)return;
    self.pages.numberOfPages=(self.templates.count+2)/3;self.pages.hidden=self.templates.count<=3;
    self.libraryEmpty.hidden=self.templates.count!=0;
    self.libraryTitle.text=self.templates.count ? [NSString stringWithFormat:@"我的素材 · %lu",(unsigned long)self.templates.count] : @"我的素材";
    self.randomSwitch.on=self.style.randomize;self.landscapeSwitch.on=self.style.autoLandscape;
    self.randomSwitch.enabled=self.templates.count>0 && !self.importing;
    self.landscapeSwitch.enabled=!self.importing;self.importButton.enabled=!self.importing && self.templates.count<32;
    for (NSUInteger i=0;i<3;i++) {
        UIButton *button=self.materialButtons[i];NSUInteger index=self.pages.currentPage*3+i;
        button.hidden=index>=self.templates.count;if(button.hidden)continue;
        MTDeviceFrameTemplate *frame=self.templates[index];button.tag=index;button.enabled=!self.importing;
        button.accessibilityIdentifier=frame.identifier;button.accessibilityLabel=frame.name;button.accessibilityHint=@"轻点选用，长按删除素材";
        BOOL selected=!self.original && [frame.identifier isEqualToString:self.style.templateIdentifier];
        button.layer.borderWidth=selected ? 2 : 0;button.layer.borderColor=MTFrameAccent().CGColor;
        button.accessibilityTraits=UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
        [button viewWithTag:103].hidden=!selected;((UILabel *)[button viewWithTag:102]).text=frame.name;
        UIImageView *image=(UIImageView *)[button viewWithTag:101];image.image=[self.thumbnailCache objectForKey:frame.identifier];
        if (!image.image) {
            __weak typeof(self) weakSelf=self;
            dispatch_async(self.renderQueue,^{@autoreleasepool {
                CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:frame.overlayPath],NULL);
                CGImageRef cg=source ? CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(id)kCGImageSourceThumbnailMaxPixelSize:@240}) : NULL;
                UIImage *thumbnail=cg ? [UIImage imageWithCGImage:cg] : nil;if(cg)CGImageRelease(cg);if(source)CFRelease(source);
                dispatch_async(dispatch_get_main_queue(),^{
                    __strong typeof(weakSelf) self=weakSelf;if(!self || self.invalidated)return;
                    if(thumbnail)[self.thumbnailCache setObject:thumbnail forKey:frame.identifier cost:thumbnail.size.width*thumbnail.size.height*4];
                    if([button.accessibilityIdentifier isEqualToString:frame.identifier])image.image=thumbnail;
                });
            }});
        }
    }
    [self updateOutputState];[self.view setNeedsLayout];
}
- (void)pageChanged:(UIPageControl *)sender { [self refreshControls]; }
- (void)templateTapped:(UIButton *)sender {
    if(self.importing || sender.tag<0 || sender.tag>=(NSInteger)self.templates.count)return;
    self.original=NO;self.style.randomize=NO;self.style.templateIdentifier=self.templates[sender.tag].identifier;
    [self refreshControls];[self schedulePreview];
}
- (void)restoreOriginal {if(self.configurationOnly || self.importing)return;self.original=YES;self.style.randomize=NO;[self refreshControls];[self schedulePreview];}
- (void)switchChanged:(UISwitch *)sender {
    if(sender.tag==5)self.style.autoLandscape=sender.on;
    else {self.style.randomize=sender.on;if(sender.on){self.original=NO;MTDeviceFrameTemplate *frame=[MTDeviceFrameTemplateStore resolveTemplateForConfiguration:self.style templates:self.templates];self.style.templateIdentifier=frame.identifier ?: @"";[self revealSelectedPage];}}
    [self refreshControls];[self schedulePreview];
}
- (void)schedulePreview {
    if(self.invalidated)return;
    self.navigationItem.rightBarButtonItem.title=@"保存";
    self.generation++;self.pendingRender=YES;self.previewReady=NO;
    self.preview.image=nil;self.emptyLabel.hidden=self.original || [self frame]!=nil;
    [self updateOutputState];[self.spinner startAnimating];if(!self.rendering)[self renderNextPreview];
}
- (void)renderNextPreview {
    if(self.invalidated || !self.pendingRender || self.rendering)return;
    self.pendingRender=NO;self.rendering=YES;NSUInteger generation=self.generation;
    MTDeviceFrameConfiguration *style=[self.style copy];MTDeviceFrameTemplate *frame=[self frame];
    UIImage *source=self.previewSource ?: self.source;BOOL original=self.original;__weak typeof(self) weakSelf=self;
    dispatch_async(self.renderQueue,^{@autoreleasepool {
        UIImage *small=[MTDeviceFramePhotoMaterial previewForImage:source];
        UIImage *result=original ? small : (frame ? [MTDeviceFrameRenderer renderImage:small configuration:style template:frame previewEdge:1200] : nil);
        dispatch_async(dispatch_get_main_queue(),^{
            __strong typeof(weakSelf) self=weakSelf;if(!self || self.invalidated)return;
            self.rendering=NO;if(small){self.previewSource=small;self.source=nil;}
            if(generation==self.generation) {
                self.preview.image=result;self.previewReady=result!=nil;[self.spinner stopAnimating];
                CGSize canvas=frame.canvasSize;if(style.autoLandscape && self.sourcePixels.width>self.sourcePixels.height && canvas.height>canvas.width)canvas=CGSizeMake(canvas.height,canvas.width);
                if(original)canvas=self.sourcePixels;
                self.detail.text=result ? [NSString stringWithFormat:@"%@ · %.0f × %.0f",original ? @"原图" : @"完整画布",canvas.width,canvas.height] : (frame ? @"合成失败，请重新导入素材" : @"尚未导入素材");
                [self updateOutputState];
            }
            [self renderNextPreview];
        });
    }});
}
- (void)updateOutputState {
    BOOL ready=self.previewReady && !self.importing && !self.invalidated;
    self.applyButton.enabled=ready;self.navigationItem.rightBarButtonItem.enabled=ready;
    self.editButton.enabled=!self.original && [self frame]!=nil && !self.importing && !self.invalidated;
    self.originalButton.enabled=!self.importing && !self.invalidated;
    for(UIButton *button in self.outputButtons.arrangedSubviews)button.enabled=ready;
}
- (void)finish:(MTOutputAction)action {
    if(!self.previewReady || self.importing || self.invalidated || self.presentedViewController)return;
    MTDeviceFrameConfiguration *style=self.original ? nil : [self.style copy];
    if(self.configurationOnly){[style remember];self.navigationItem.rightBarButtonItem.title=@"已保存";return;}
    void (^completion)(BOOL,MTDeviceFrameConfiguration *,MTOutputAction)=self.completion;
    [self invalidate];if(completion)completion(YES,style,action);
}
- (void)apply {[self finish:MTOutputActionPreviewOnly];}
- (void)copyOutput {[self finish:MTOutputActionCopy];}
- (void)shareOutput {[self finish:MTOutputActionShare];}
- (void)saveOutput {[self finish:MTOutputActionSave];}
- (void)cancel {
    void (^completion)(BOOL,MTDeviceFrameConfiguration *,MTOutputAction)=self.completion;
    [self invalidate];if(completion)completion(NO,nil,MTOutputActionPreviewOnly);
}
- (void)invalidate {
    self.invalidated=YES;self.generation++;self.pendingRender=NO;self.completion=nil;
    self.photoPicker.delegate=nil;self.photoPicker=nil;
    [self.photoLoadingProgress cancel];self.photoLoadingProgress=nil;[self.photoOperation cancel];self.photoOperation=nil;
    [self.photoMaterialController invalidate];self.photoMaterialController=nil;
    self.source=nil;self.previewSource=nil;self.preview.image=nil;[self.thumbnailCache removeAllObjects];
}
- (void)dealloc {_photoPicker.delegate=nil;[_photoLoadingProgress cancel];[_photoOperation cancel];[_photoMaterialController invalidate];}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if(self.isBeingDismissed || self.navigationController.isBeingDismissed || self.isMovingFromParentViewController)[self invalidate];
}
- (void)presentPhotoPicker {
    if(self.invalidated || self.importing || self.presentedViewController || self.photoPicker)return;
    PHPickerConfiguration *configuration=[[PHPickerConfiguration alloc]init];
    configuration.filter=PHPickerFilter.imagesFilter;configuration.selectionLimit=1;
    configuration.preferredAssetRepresentationMode=PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker=[[PHPickerViewController alloc]initWithConfiguration:configuration];
    picker.delegate=self;picker.modalInPresentation=YES;self.photoPicker=picker;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    if(self.invalidated || picker!=self.photoPicker)return;
    picker.delegate=nil;self.photoPicker=nil;
    NSItemProvider *provider=results.firstObject.itemProvider;
    __weak typeof(self) weakSelf=self;
    [picker dismissViewControllerAnimated:YES completion:^{
        __strong typeof(weakSelf) self=weakSelf;
        if(!self || self.invalidated || !provider)return;
        NSString *identifier=nil;
        for(NSString *candidate in provider.registeredTypeIdentifiers) {
            UTType *type=[UTType typeWithIdentifier:candidate];
            if([type conformsToType:UTTypeImage]){identifier=candidate;if([type conformsToType:UTTypePNG])break;}
        }
        if(!identifier){[self showError:@"所选相册项目无法作为图片素材读取"];return;}
        self.importing=YES;[self updateOutputState];[self refreshControls];[self.spinner startAnimating];
        NSProgress *operation=[NSProgress progressWithTotalUnitCount:1];self.photoOperation=operation;
        self.photoLoadingProgress=[provider loadFileRepresentationForTypeIdentifier:identifier completionHandler:^(NSURL *URL,NSError *loadError) {
            @autoreleasepool {
                if(operation.cancelled)return;
                NSError *error=loadError;
                UIImage *image=URL && !error ? [MTDeviceFramePhotoMaterial imageFromPhotoURL:URL error:&error] : nil;
                BOOL transparent=NO;
                MTDeviceFrameQuad quad=image ? [MTDeviceFramePhotoMaterial suggestedScreenForImage:image hasTransparentScreen:&transparent] : MTDeviceFrameQuadForRect(CGRectZero);
                UIImage *preview=image ? [MTDeviceFramePhotoMaterial previewForImage:image] : nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) self=weakSelf;
                    if(!self || self.invalidated || operation.cancelled || self.photoOperation!=operation)return;
                    self.photoOperation=nil;self.photoLoadingProgress=nil;self.importing=NO;[self.spinner stopAnimating];
                    [self updateOutputState];[self refreshControls];
                    if(!image || !preview){[self showError:error.localizedDescription ?: @"相册素材读取失败，请重试"];return;}
                    [self presentPhotoMaterial:image preview:preview quad:quad transparent:transparent];
                });
            }
        }];
    }];
}
- (void)presentPhotoMaterial:(UIImage *)image preview:(UIImage *)preview quad:(MTDeviceFrameQuad)quad transparent:(BOOL)transparent {
    if(self.invalidated || self.presentedViewController)return;
    __weak typeof(self) weakSelf=self;
    MTDeviceFramePhotoMaterialController *controller=[[MTDeviceFramePhotoMaterialController alloc]initWithImage:image
        preview:preview suggestedQuad:quad transparentScreen:transparent completion:^(MTDeviceFrameTemplate *frame) {
            [weakSelf materialDidFinish:frame];
        }];
    [self presentMaterialController:controller];
}
- (void)calibrateSelectedTemplate {
    MTDeviceFrameTemplate *frame=[self frame];
    if(self.invalidated || self.original || frame.kind!=3 || self.importing || self.presentedViewController)return;
    self.importing=YES;[self updateOutputState];[self refreshControls];[self.spinner startAnimating];
    NSProgress *operation=[NSProgress progressWithTotalUnitCount:1];self.photoOperation=operation;
    __weak typeof(self) weakSelf=self;
    dispatch_async(self.renderQueue, ^{
        @autoreleasepool {
            if(operation.cancelled)return;
            NSError *error=nil;UIImage *image=[MTDeviceFramePhotoMaterial sourceImageForTemplate:frame error:&error];
            UIImage *preview=image ? [MTDeviceFramePhotoMaterial previewForImage:image] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self=weakSelf;
                if(!self || self.invalidated || operation.cancelled || self.photoOperation!=operation)return;
                self.photoOperation=nil;self.importing=NO;[self.spinner stopAnimating];[self updateOutputState];[self refreshControls];
                if(!image || !preview){[self showError:error.localizedDescription ?: @"素材读取失败，请重新导入"];return;}
                MTDeviceFramePhotoMaterialController *controller=[[MTDeviceFramePhotoMaterialController alloc]initWithTemplate:frame image:image preview:preview
                    completion:^(MTDeviceFrameTemplate *result){[weakSelf materialDidFinish:result];}];
                [self presentMaterialController:controller];
            });
        }
    });
}
- (void)materialDidFinish:(MTDeviceFrameTemplate *)frame {
    if(self.invalidated || !self.photoMaterialController ||
       self.presentedViewController!=self.photoMaterialController.navigationController)return;
    self.photoMaterialController=nil;
    __weak typeof(self) weakSelf=self;
    [self dismissViewControllerAnimated:YES completion:^{
        __strong typeof(weakSelf) self=weakSelf;if(!self || self.invalidated)return;
        if(frame){self.templates=[MTDeviceFrameTemplateStore templates];self.style.templateIdentifier=frame.identifier;self.original=NO;self.style.randomize=NO;[self revealSelectedPage];}
        [self refreshControls];[self schedulePreview];
    }];
}
- (void)presentMaterialController:(MTDeviceFramePhotoMaterialController *)controller {
    if(self.invalidated || self.presentedViewController)return;
    controller.screenshot=self.previewSource ?: self.source;
    self.photoMaterialController=controller;
    UINavigationController *navigation=[[UINavigationController alloc]initWithRootViewController:controller];
    navigation.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;navigation.navigationBar.tintColor=MTFrameAccent();
    navigation.modalPresentationStyle=UIModalPresentationFullScreen;navigation.modalInPresentation=YES;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)showError:(NSString *)message {
    if(self.invalidated || !self.view.window || self.presentedViewController)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"套壳素材" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)deleteTemplate:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan || self.importing || self.presentedViewController)return;
    NSInteger index=gesture.view.tag;if(index<0 || index>=(NSInteger)self.templates.count)return;
    MTDeviceFrameTemplate *frame=self.templates[index];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"删除素材？" message:frame.name preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        __strong typeof(weakSelf) self=weakSelf;if(!self || self.invalidated)return;
        NSError *error=nil;if(![MTDeviceFrameTemplateStore removeTemplate:frame error:&error]){[self showError:error.localizedDescription ?: @"删除失败"];return;}
        self.templates=[MTDeviceFrameTemplateStore templates];
        if(![self frame])self.style.templateIdentifier=self.templates.firstObject.identifier ?: @"";
        if(!self.templates.count)self.style.randomize=NO;
        [self revealSelectedPage];[self refreshControls];[self schedulePreview];
    }]];[self presentViewController:alert animated:YES completion:nil];
}
@end
