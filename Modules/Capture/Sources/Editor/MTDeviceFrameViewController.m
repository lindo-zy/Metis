#import "MTDeviceFrameViewController.h"
#import "MTDeviceFrameRenderer.h"
#import "MTDeviceFrameTemplateStore.h"
#import "MTDeviceFramePhotoMaterialController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <PhotosUI/PhotosUI.h>

static UIColor *MTFrameAccent(void) { return [UIColor colorWithRed:1 green:0.78 blue:0.08 alpha:1]; }

@interface MTFrameCheckerView : UIView
@end
@implementation MTFrameCheckerView
- (void)drawRect:(CGRect)rect {
    for (NSInteger y=0;y<ceil(self.bounds.size.height/14);y++) {
        for (NSInteger x=0;x<ceil(self.bounds.size.width/14);x++) {
            [[UIColor colorWithWhite:(x+y)%2 ? 0.28 : 0.23 alpha:1] setFill];
            UIRectFill(CGRectMake(x*14,y*14,14,14));
        }
    }
}
@end

@interface MTDeviceFrameViewController () <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate, PHPickerViewControllerDelegate>
@property (nonatomic, strong) UIImage *source;
@property (nonatomic, strong) UIImage *previewSource;
@property (nonatomic) CGSize sourcePixels;
@property (nonatomic, strong) MTDeviceFrameConfiguration *style;
@property (nonatomic, copy) NSArray<MTDeviceFrameTemplate *> *templates;
@property (nonatomic, copy) void (^completion)(BOOL, MTDeviceFrameConfiguration *, MTOutputAction);
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UILabel *detail;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIStackView *outputButtons;
@property (nonatomic, strong) UIScrollView *templateScroll;
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
- (instancetype)initWithImage:(UIImage *)image configuration:(MTDeviceFrameConfiguration *)configuration
                   completion:(void (^)(BOOL,MTDeviceFrameConfiguration *,MTOutputAction))completion {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _source = image;
        _sourcePixels = CGSizeMake(image.size.width*image.scale,image.size.height*image.scale);
        _style = [configuration copy] ?: [MTDeviceFrameConfiguration rememberedConfiguration];
        _completion = [completion copy];
        _templates = [MTDeviceFrameTemplateStore templates];
        _renderQueue = dispatch_queue_create("com.lindo.metis.capture.frame.preview", DISPATCH_QUEUE_SERIAL);
        if (![self frame]) _style.templateIdentifier = @"island";
        if (!configuration && _style.randomize) [self randomizeTemplate];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    return self;
}
- (MTDeviceFrameTemplate *)frame {
    for (MTDeviceFrameTemplate *t in self.templates) if ([t.identifier isEqualToString:self.style.templateIdentifier]) return t;
    return nil;
}
- (void)randomizeTemplate {
    if (self.templates.count) self.style.templateIdentifier = self.templates[arc4random_uniform((uint32_t)self.templates.count)].identifier;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.view.tintColor = MTFrameAccent();
    UIView *navigation = [UIView new]; navigation.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *cancel = [self button:@"取消" selector:@selector(cancel)];
    self.applyButton = [self button:self.configurationOnly ? @"保存配置" : @"应用" selector:@selector(apply)];
    UILabel *title = [UILabel new]; title.text = self.configurationOnly ? @"套壳素材" : @"套壳截图";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; title.textAlignment = NSTextAlignmentCenter;
    for (UIView *v in @[cancel,title,self.applyButton]) { v.translatesAutoresizingMaskIntoConstraints = NO; [navigation addSubview:v]; }
    [self.view addSubview:navigation];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.translatesAutoresizingMaskIntoConstraints = NO; self.table.backgroundColor = UIColor.clearColor;
    self.table.delegate = self; self.table.dataSource = self; self.table.separatorColor = [UIColor colorWithWhite:0.24 alpha:1];
    self.table.estimatedRowHeight = 56; self.table.rowHeight = UITableViewAutomaticDimension;
    [self.view addSubview:self.table];
    self.outputButtons = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self button:@"复制" selector:@selector(copyOutput)], [self button:@"分享" selector:@selector(shareOutput)],
        [self button:@"保存" selector:@selector(saveOutput)]]];
    self.outputButtons.translatesAutoresizingMaskIntoConstraints = NO; self.outputButtons.spacing=10;
    self.outputButtons.distribution=UIStackViewDistributionFillEqually;
    self.outputButtons.hidden=self.configurationOnly;
    for (UIButton *b in self.outputButtons.arrangedSubviews) {
        b.backgroundColor=[UIColor colorWithWhite:0.18 alpha:1]; b.layer.cornerRadius=13;
    }
    UIButton *save = self.outputButtons.arrangedSubviews.lastObject; save.backgroundColor=MTFrameAccent(); [save setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [self.view addSubview:self.outputButtons];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [navigation.topAnchor constraintEqualToAnchor:safe.topAnchor], [navigation.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [navigation.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor], [navigation.heightAnchor constraintEqualToConstant:52],
        [cancel.leadingAnchor constraintEqualToAnchor:navigation.leadingAnchor constant:16], [cancel.centerYAnchor constraintEqualToAnchor:navigation.centerYAnchor],
        [cancel.widthAnchor constraintEqualToConstant:64], [cancel.heightAnchor constraintEqualToConstant:44],
        [self.applyButton.trailingAnchor constraintEqualToAnchor:navigation.trailingAnchor constant:-16],
        [self.applyButton.centerYAnchor constraintEqualToAnchor:navigation.centerYAnchor],
        [self.applyButton.widthAnchor constraintEqualToConstant:self.configurationOnly ? 90 : 64],
        [self.applyButton.heightAnchor constraintEqualToConstant:44],
        [title.centerXAnchor constraintEqualToAnchor:navigation.centerXAnchor], [title.centerYAnchor constraintEqualToAnchor:navigation.centerYAnchor],
        [self.outputButtons.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [self.outputButtons.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [self.outputButtons.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        [self.outputButtons.heightAnchor constraintEqualToConstant:self.configurationOnly ? 0 : 48],
        [self.table.topAnchor constraintEqualToAnchor:navigation.bottomAnchor], [self.table.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor], [self.table.bottomAnchor constraintEqualToAnchor:self.outputButtons.topAnchor constant:-8]
    ]];
    UIView *header = [UIView new];
    MTFrameCheckerView *checker = [MTFrameCheckerView new]; checker.tag=200; checker.layer.cornerRadius=16; checker.clipsToBounds=YES;
    [header addSubview:checker];
    self.preview = [UIImageView new]; self.preview.contentMode=UIViewContentModeScaleAspectFit;
    self.preview.accessibilityLabel=@"套壳截图预览"; self.preview.isAccessibilityElement=YES; [checker addSubview:self.preview];
    self.detail = [UILabel new]; self.detail.numberOfLines=0; self.detail.textAlignment=NSTextAlignmentCenter;
    self.detail.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; self.detail.textColor=UIColor.secondaryLabelColor;
    [header addSubview:self.detail];
    self.spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped=YES; [checker addSubview:self.spinner];
    self.table.tableHeaderView=header;
    [self schedulePreview];
}
- (UIButton *)button:(NSString *)title selector:(SEL)selector {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal]; b.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    b.accessibilityLabel=title; [b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside]; return b;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header=self.table.tableHeaderView;
    CGFloat width=self.table.bounds.size.width;
    CGFloat previewHeight=MAX(180,MIN(380,self.view.bounds.size.height*0.40));
    CGFloat detailHeight=MAX(44,[self.detail sizeThatFits:CGSizeMake(MAX(1,width-40),CGFLOAT_MAX)].height+12);
    CGFloat height=previewHeight+detailHeight+16;
    if (header.frame.size.width!=width || header.frame.size.height!=height) {
        header.frame=CGRectMake(0,0,width,height); self.table.tableHeaderView=header;
    }
    UIView *checker=[header viewWithTag:200]; checker.frame=CGRectMake(20,8,MAX(1,width-40),previewHeight);
    self.preview.frame=checker.bounds; self.spinner.center=CGPointMake(checker.bounds.size.width/2,previewHeight/2);
    self.detail.frame=CGRectMake(20,previewHeight+12,MAX(1,width-40),detailHeight);
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 9; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.configurationOnly
        ? @"此处仅配置素材。保存配置后，触发「套壳截图」即自动合成并输出，无需再编辑。相册素材选图后定位屏幕四角；文件导入选择 PNG 和配置两个文件。"
        : @"截图等比完整显示。可从相册选图并定位屏幕四角，或从文件导入 PNG 和配置。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor=[UIColor colorWithWhite:0.14 alpha:1]; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    NSArray *labels=@[@"机壳",@"机身颜色",@"背景",@"留白",@"阴影",@"自动横屏",@"随机素材",@"从相册导入素材",@"从文件导入素材"];
    UILabel *label=[UILabel new]; label.text=labels[path.row]; label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory=YES; label.numberOfLines=0;
    label.translatesAutoresizingMaskIntoConstraints=NO; [cell.contentView addSubview:label];
    UIView *control=nil;
    if (path.row==0) {
        UIScrollView *scroll=[UIScrollView new]; scroll.showsHorizontalScrollIndicator=YES;
        UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisHorizontal; stack.spacing=8;
        NSArray *names=[@[@"原图"] arrayByAddingObjectsFromArray:[self.templates valueForKey:@"name"]];
        for (NSUInteger i=0;i<names.count;i++) {
            if (self.configurationOnly && i==0) continue;
            UIButton *b=[self button:names[i] selector:@selector(templateTapped:)]; b.tag=i;
            UIButtonConfiguration *configuration=[UIButtonConfiguration plainButtonConfiguration];
            configuration.contentInsets=NSDirectionalEdgeInsetsMake(8,12,8,12);
            b.configuration=configuration; b.layer.cornerRadius=10;
            BOOL selected=i==0 ? self.original : (!self.original && [self.templates[i-1].identifier isEqualToString:self.style.templateIdentifier]);
            b.backgroundColor=selected ? MTFrameAccent() : [UIColor colorWithWhite:0.22 alpha:1];
            [b setTitleColor:selected ? UIColor.blackColor : UIColor.whiteColor forState:UIControlStateNormal];
            b.accessibilityTraits=UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
            if (i>3) [b addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(deleteTemplate:)]];
            [stack addArrangedSubview:b];
        }
        stack.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
            [stack.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor]]];
        control=scroll; self.templateScroll=scroll;
    } else if (path.row==1 || path.row==2) {
        UISegmentedControl *segments=[[UISegmentedControl alloc] initWithItems:path.row==1 ? @[@"石墨",@"银白",@"原色",@"蓝"] : @[@"透明",@"雾白",@"深灰",@"浅紫"]];
        segments.selectedSegmentIndex=path.row==1 ? self.style.bodyColor : self.style.background;
        segments.selectedSegmentTintColor=MTFrameAccent();
        [segments setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.blackColor} forState:UIControlStateSelected];
        segments.tag=path.row; segments.accessibilityLabel=labels[path.row];
        [segments addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        segments.enabled=!(path.row==1 && [self frame].kind==3); control=segments;
    } else if (path.row==3) {
        UISlider *slider=[UISlider new]; slider.minimumValue=0; slider.maximumValue=0.25; slider.value=self.style.paddingFraction;
        slider.accessibilityLabel=@"留白比例"; slider.accessibilityValue=[NSString stringWithFormat:@"%.0f%%",slider.value*100];
        [slider addTarget:self action:@selector(paddingChanged:) forControlEvents:UIControlEventValueChanged]; control=slider;
    } else if (path.row<7) {
        UISwitch *toggle=[UISwitch new]; toggle.onTintColor=MTFrameAccent(); toggle.tag=path.row;
        toggle.on=path.row==4 ? self.style.shadow : (path.row==5 ? self.style.autoLandscape : self.style.randomize);
        toggle.accessibilityLabel=labels[path.row]; [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged]; control=toggle;
    } else {
        cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle=UITableViewCellSelectionStyleDefault;
    }
    BOOL stacked=path.row<=3;
    [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12]]];
    if (control) {
        control.translatesAutoresizingMaskIntoConstraints=NO; [cell.contentView addSubview:control];
        [NSLayoutConstraint activateConstraints:@[[control.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [control.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12]]];
        if (stacked) {
            [NSLayoutConstraint activateConstraints:@[[control.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:8],
                [control.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
                [control.heightAnchor constraintGreaterThanOrEqualToConstant:44],
                [label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16]]];
        } else {
            [NSLayoutConstraint activateConstraints:@[[control.topAnchor constraintGreaterThanOrEqualToAnchor:cell.contentView.topAnchor constant:12],
                [label.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-12],
                [label.bottomAnchor constraintLessThanOrEqualToAnchor:cell.contentView.bottomAnchor constant:-12]]];
        }
    } else {
        [NSLayoutConstraint activateConstraints:@[[label.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
            [label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:52]]];
    }
    cell.contentView.userInteractionEnabled=!self.importing;
    return cell;
}
- (void)templateTapped:(UIButton *)sender {
    self.original=sender.tag==0;
    if (!self.original) self.style.templateIdentifier=self.templates[sender.tag-1].identifier;
    [self.table reloadData]; [self schedulePreview];
}
- (void)segmentChanged:(UISegmentedControl *)sender {
    if (sender.tag==1) self.style.bodyColor=sender.selectedSegmentIndex; else self.style.background=sender.selectedSegmentIndex;
    [self schedulePreview];
}
- (void)paddingChanged:(UISlider *)sender {
    self.style.paddingFraction=sender.value; sender.accessibilityValue=[NSString stringWithFormat:@"%.0f%%",sender.value*100]; [self schedulePreview];
}
- (void)switchChanged:(UISwitch *)sender {
    if (sender.tag==4) self.style.shadow=sender.on;
    else if (sender.tag==5) self.style.autoLandscape=sender.on;
    else {
        self.style.randomize=sender.on;
        if (sender.on) { self.original=NO; [self randomizeTemplate]; [self.table reloadData]; }
    }
    [self schedulePreview];
}
- (void)schedulePreview {
    if (self.invalidated) return;
    self.generation++; self.pendingRender=YES; self.previewReady=NO;
    [self updateOutputState]; [self.spinner startAnimating];
    if (!self.rendering) [self renderNextPreview];
}
- (void)renderNextPreview {
    if (self.invalidated || !self.pendingRender || self.rendering) return;
    self.pendingRender=NO; self.rendering=YES;
    NSUInteger generation=self.generation;
    MTDeviceFrameConfiguration *style=[self.style copy]; MTDeviceFrameTemplate *frame=[self frame];
    BOOL original=self.original;
    UIImage *source=self.previewSource ?: self.source;
    __weak typeof(self) weakSelf=self;
    dispatch_async(self.renderQueue, ^{
        @autoreleasepool {
            CGFloat factor=MIN(1,1200.0/MAX(source.size.width*source.scale,source.size.height*source.scale));
            UIImage *small=source;
            if (factor<1) {
                UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat new]; format.scale=1; format.opaque=NO;
                CGSize size=CGSizeMake(ceil(source.size.width*source.scale*factor),ceil(source.size.height*source.scale*factor));
                small=[[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                    [source drawInRect:(CGRect){CGPointZero,size}];
                }];
            }
            UIImage *result=original ? small : [MTDeviceFrameRenderer renderImage:small configuration:style template:frame previewEdge:1200];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self=weakSelf;
                if (!self || self.invalidated) return;
                self.rendering=NO; self.previewSource=small; self.source=nil;
                if (generation==self.generation) {
                    self.preview.image=result; self.previewReady=result!=nil; [self.spinner stopAnimating];
                    CGSize canvas=frame.canvasSize; MTDeviceFrameQuad quad=frame.screenQuad;
                    if (style.autoLandscape && self.sourcePixels.width>self.sourcePixels.height && canvas.height>canvas.width) {
                        quad=MTDeviceFrameLandscapeQuad(quad,canvas); canvas=CGSizeMake(canvas.height,canvas.width);
                    }
                    CGSize output=original ? self.sourcePixels : MTDeviceFrameOutputSize(self.sourcePixels,canvas,MTDeviceFrameScreenSize(quad),style.paddingFraction,0);
                    if (CGSizeEqualToSize(output,CGSizeZero)) self.previewReady=NO;
                    self.detail.text=self.previewReady ? [NSString stringWithFormat:@"%@ · %.0f × %.0f px · %@",
                        original ? @"原图" : frame.name,output.width,output.height,
                        !original && style.background==0 ? @"透明 PNG" : @"完整显示"] : @"无法合成：请缩小原图或更换素材（输出上限 24MP / 8192px）";
                    [self updateOutputState]; [self.view setNeedsLayout];
                }
                [self renderNextPreview];
            });
        }
    });
}
- (void)updateOutputState {
    BOOL ready=self.previewReady && !self.importing && !self.invalidated;
    self.applyButton.enabled=ready;
    for (UIButton *b in self.outputButtons.arrangedSubviews) b.enabled=ready;
}
- (void)finish:(MTOutputAction)action {
    if (!self.previewReady || self.importing || self.invalidated || self.presentedViewController) return;
    MTDeviceFrameConfiguration *style=self.original ? nil : [self.style copy];
    if (style && self.configurationOnly) [style remember];
    void (^completion)(BOOL,MTDeviceFrameConfiguration *,MTOutputAction)=self.completion;
    [self invalidate];
    if (completion) completion(YES,style,action);
}
- (void)apply { [self finish:MTOutputActionPreviewOnly]; }
- (void)copyOutput { [self finish:MTOutputActionCopy]; }
- (void)shareOutput { [self finish:MTOutputActionShare]; }
- (void)saveOutput { [self finish:MTOutputActionSave]; }
- (void)cancel {
    void (^completion)(BOOL,MTDeviceFrameConfiguration *,MTOutputAction)=self.completion;
    [self invalidate]; if (completion) completion(NO,nil,MTOutputActionPreviewOnly);
}
- (void)invalidate {
    self.photoPicker.delegate=nil;self.photoPicker=nil;
    [self.photoLoadingProgress cancel];self.photoLoadingProgress=nil;
    [self.photoOperation cancel];self.photoOperation=nil;
    [self.photoMaterialController invalidate];self.photoMaterialController=nil;
    self.invalidated=YES; self.generation++; self.pendingRender=NO; self.completion=nil;
    self.source=nil; self.previewSource=nil; self.preview.image=nil;
    for (UITableViewCell *cell in self.table.visibleCells) {
        for (UIView *view in cell.contentView.subviews) {
            if (![view isKindOfClass:UIScrollView.class]) continue;
            for (UIView *stack in view.subviews) for (UIView *button in stack.subviews)
                for (UIGestureRecognizer *gesture in [button.gestureRecognizers copy]) [button removeGestureRecognizer:gesture];
        }
    }
    self.table.delegate=nil; self.table.dataSource=nil;
}
- (void)dealloc {
    _photoPicker.delegate=nil;[_photoLoadingProgress cancel];[_photoOperation cancel];[_photoMaterialController invalidate];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || self.navigationController.isBeingDismissed) [self invalidate];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.row<7 || self.importing || self.presentedViewController) return;
    if(path.row==7){[self presentPhotoPicker];return;}
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:NO];
    picker.allowsMultipleSelection=YES; picker.delegate=self; [self presentViewController:picker animated:YES completion:nil];
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
        self.importing=YES;[self updateOutputState];[self.table reloadData];[self.spinner startAnimating];
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
                    [self updateOutputState];[self.table reloadData];
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
            __strong typeof(weakSelf) self=weakSelf;
            if(!self || self.invalidated || !self.photoMaterialController ||
                self.presentedViewController!=self.photoMaterialController.navigationController)return;
            self.photoMaterialController=nil;
            [self dismissViewControllerAnimated:YES completion:^{
                __strong typeof(weakSelf) self=weakSelf;if(!self || self.invalidated)return;
                if(frame){self.templates=[MTDeviceFrameTemplateStore templates];self.style.templateIdentifier=frame.identifier;self.original=NO;}
                [self.table reloadData];[self schedulePreview];
            }];
        }];
    self.photoMaterialController=controller;
    UINavigationController *navigation=[[UINavigationController alloc]initWithRootViewController:controller];
    navigation.modalPresentationStyle=UIModalPresentationFullScreen;navigation.modalInPresentation=YES;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)URLs {
    if (self.invalidated) return;
    self.importing=YES; [self updateOutputState]; [self.table reloadData];
    NSMutableArray *scoped=[NSMutableArray new];
    for (NSURL *url in URLs) if ([url startAccessingSecurityScopedResource]) [scoped addObject:url];
    __weak typeof(self) weakSelf=self;
    dispatch_async(self.renderQueue, ^{
        @autoreleasepool {
            NSError *error=nil; MTDeviceFrameTemplate *frame=[MTDeviceFrameTemplateStore importFiles:URLs error:&error];
            for (NSURL *url in scoped) [url stopAccessingSecurityScopedResource];
            NSArray *templates=[MTDeviceFrameTemplateStore templates];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self=weakSelf;
                if (!self || self.invalidated) return;
                self.importing=NO; self.templates=templates;
                if (frame) { self.style.templateIdentifier=frame.identifier; self.original=NO; }
                else [self showError:error.localizedDescription ?: @"素材导入失败"];
                [self.table reloadData]; [self schedulePreview];
            });
        }
    });
}
- (void)showError:(NSString *)message {
    if (self.invalidated || !self.view.window) return;
    if ([self.presentedViewController isKindOfClass:UIDocumentPickerViewController.class]) {
        __weak typeof(self) weakSelf=self;
        [self dismissViewControllerAnimated:YES completion:^{ [weakSelf showError:message]; }];
        return;
    }
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"套壳素材" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    if (!self.presentedViewController) [self presentViewController:alert animated:YES completion:nil];
}
- (void)deleteTemplate:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state!=UIGestureRecognizerStateBegan || self.importing || self.presentedViewController) return;
    NSInteger index=gesture.view.tag-1;
    if (index<0 || index>=(NSInteger)self.templates.count) return;
    MTDeviceFrameTemplate *frame=self.templates[index];
    if (frame.kind!=3) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"删除素材？" message:frame.name preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self=weakSelf;
        if (!self || self.invalidated) return;
        NSError *error=nil;
        if (![MTDeviceFrameTemplateStore removeTemplate:frame error:&error]) { [self showError:error.localizedDescription ?: @"删除失败"]; return; }
        self.templates=[MTDeviceFrameTemplateStore templates];
        if (![self frame]) self.style.templateIdentifier=@"island";
        [self.table reloadData]; [self schedulePreview];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
