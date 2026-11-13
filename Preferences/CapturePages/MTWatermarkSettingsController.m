#import <Preferences/PSViewController.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "../../Modules/Capture/Sources/Watermark/MTWatermarkRenderer.h"
#import "../../Modules/Capture/Sources/Editor/MTDeviceFrameViewController.h"
#import "../../Modules/Capture/Sources/Editor/MTDeviceFrameRenderer.h"
#import "../../Modules/Capture/Sources/Editor/MTDeviceFrameTemplateStore.h"

@interface MTWatermarkSettingsController : PSViewController <PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) MTWatermarkConfiguration *style;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UIImageView *mark;
@property (nonatomic, strong) UIStackView *materialsStack;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISegmentedControl *previewMode;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) NSMutableArray<UISlider *> *sliders;
@property (nonatomic, strong) NSMutableArray<UILabel *> *values;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSUInteger materialGeneration;
@property (nonatomic) BOOL importing;
@property (nonatomic) CGPoint dragOrigin;
@property (nonatomic, strong) dispatch_queue_t renderQueue;
@end

@implementation MTWatermarkSettingsController
- (NSArray *)specifiers { return @[]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"水印设置";
    self.style = [MTWatermarkConfiguration rememberedConfiguration];
    self.renderQueue = dispatch_queue_create("com.lindo.metis.watermark.settings", DISPATCH_QUEUE_SERIAL);
    self.sliders = [NSMutableArray new]; self.values = [NSMutableArray new];
    self.view = [UIView new]; self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    UIStackView *stack = [UIStackView new]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO; [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]]];
    self.enabledSwitch = [UISwitch new]; self.enabledSwitch.on = self.style.enabled;
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:[self rowWithTitle:@"启用截图水印" control:self.enabledSwitch]];
    UISegmentedControl *scope = [[UISegmentedControl alloc] initWithItems:@[@"所有截图", @"普通截图", @"套壳截图"]];
    scope.selectedSegmentIndex = self.style.scope;
    [scope addTarget:self action:@selector(scopeChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:scope];
    self.previewMode = [[UISegmentedControl alloc] initWithItems:@[@"普通预览", @"套壳预览"]];
    self.previewMode.selectedSegmentIndex = 0;
    [self.previewMode addTarget:self action:@selector(refreshPreview) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.previewMode];
    self.preview = [UIImageView new]; self.preview.contentMode = UIViewContentModeScaleAspectFit;
    self.preview.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.preview.layer.cornerRadius = 12; self.preview.clipsToBounds = YES;
    self.preview.userInteractionEnabled = YES;
    [self.preview.heightAnchor constraintEqualToConstant:280].active = YES;
    [stack addArrangedSubview:self.preview];
    self.mark = [UIImageView new]; self.mark.contentMode = UIViewContentModeScaleAspectFit;
    self.mark.isAccessibilityElement = YES; self.mark.accessibilityLabel = @"水印位置预览";
    [self.preview addSubview:self.mark];
    [self.preview addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    self.status = [UILabel new]; self.status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.status.textColor = UIColor.secondaryLabelColor; self.status.numberOfLines = 0;
    [stack addArrangedSubview:self.status];
    UIScrollView *materials = [UIScrollView new]; materials.showsHorizontalScrollIndicator = NO;
    [materials.heightAnchor constraintEqualToConstant:76].active = YES;
    self.materialsStack = [UIStackView new]; self.materialsStack.spacing = 10;
    self.materialsStack.translatesAutoresizingMaskIntoConstraints = NO; [materials addSubview:self.materialsStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.materialsStack.leadingAnchor constraintEqualToAnchor:materials.contentLayoutGuide.leadingAnchor],
        [self.materialsStack.trailingAnchor constraintEqualToAnchor:materials.contentLayoutGuide.trailingAnchor],
        [self.materialsStack.topAnchor constraintEqualToAnchor:materials.contentLayoutGuide.topAnchor],
        [self.materialsStack.bottomAnchor constraintEqualToAnchor:materials.contentLayoutGuide.bottomAnchor],
        [self.materialsStack.heightAnchor constraintEqualToAnchor:materials.frameLayoutGuide.heightAnchor]]];
    [stack addArrangedSubview:materials];
    UIStackView *imports = [UIStackView new]; imports.distribution = UIStackViewDistributionFillEqually; imports.spacing = 10;
    [imports addArrangedSubview:[self button:@"从相册导入" action:@selector(importPhoto)]];
    [imports addArrangedSubview:[self button:@"从文件导入" action:@selector(importFile)]];
    self.deleteButton = [self button:@"删除素材" action:@selector(deleteMaterial)];
    [imports addArrangedSubview:self.deleteButton]; [stack addArrangedSubview:imports];
    NSArray *titles = @[@"横向位置", @"纵向位置", @"水印大小", @"不透明度"];
    for (NSInteger index = 0; index < 4; index++) {
        UILabel *value = [UILabel new]; value.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
        [self.values addObject:value]; [stack addArrangedSubview:[self rowWithTitle:titles[index] control:value]];
        UISlider *slider = [UISlider new]; slider.minimumValue = index < 2 ? 0 : 0.05; slider.maximumValue = 1;
        slider.tag = index; slider.accessibilityLabel = titles[index];
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [self.sliders addObject:slider]; [stack addArrangedSubview:slider];
    }
    UIStackView *positions = [UIStackView new]; positions.axis = UILayoutConstraintAxisVertical; positions.spacing = 6;
    NSArray *names = @[@"左上", @"上中", @"右上", @"左中", @"居中", @"右中", @"左下", @"下中", @"右下"];
    for (NSInteger row = 0; row < 3; row++) {
        UIStackView *buttons = [UIStackView new]; buttons.distribution = UIStackViewDistributionFillEqually;
        for (NSInteger column = 0; column < 3; column++) {
            UIButton *button = [self button:names[row * 3 + column] action:@selector(positionTapped:)];
            button.tag = row * 3 + column; [buttons addArrangedSubview:button];
        }
        [positions addArrangedSubview:buttons];
    }
    [stack addArrangedSubview:positions];
    UILabel *help = [UILabel new]; help.numberOfLines = 0; help.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    help.textColor = UIColor.secondaryLabelColor;
    help.text = @"拖动预览或调节位置滑杆可定位水印。大小按成图短边计算。套壳时叠加到完整成图，可覆盖机壳与背景。支持透明 PNG，素材最长边保存为 2048 像素。长截图不添加水印。点击右上角保存后生效。";
    [stack addArrangedSubview:help];
    [self refreshControls]; [self reloadMaterials]; [self refreshPreview];
}
- (UIView *)rowWithTitle:(NSString *)title control:(UIView *)control {
    UILabel *label = [UILabel new]; label.text = title; label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, control]];
    row.alignment = UIStackViewAlignmentCenter; row.spacing = 12;
    [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return row;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self layoutMark]; }
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
    self.mark.hidden = CGRectIsEmpty(imageRect) || ![self.style appliesToFramedImage:self.previewMode.selectedSegmentIndex == 1];
}
- (void)refreshControls {
    double values[] = {self.style.x, self.style.y, self.style.size, self.style.opacity};
    for (NSInteger index = 0; index < 4; index++) {
        self.sliders[index].value = values[index];
        self.values[index].text = [NSString stringWithFormat:@"%.0f%%", values[index] * 100];
    }
    self.navigationItem.rightBarButtonItem.title = @"保存";
    self.deleteButton.enabled = self.style.materialIdentifier.length > 0 && !self.importing;
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
    self.mark.image = nil;
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
            self.status.text = !base ? @"请先在套壳设置中保存可用素材" : (!mark ? @"请导入并选择水印素材" : @"拖动预览可调整水印位置");
            [self layoutMark];
        });
    }});
}
- (void)reloadMaterials {
    NSUInteger generation = ++self.materialGeneration;
    for (UIView *view in self.materialsStack.arrangedSubviews) { [self.materialsStack removeArrangedSubview:view]; [view removeFromSuperview]; }
    NSArray *identifiers = MTWatermarkRenderer.materials;
    for (NSString *identifier in identifiers) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.accessibilityIdentifier = identifier; button.accessibilityLabel = @"水印素材";
        button.accessibilityValue = [identifier isEqualToString:self.style.materialIdentifier] ? @"已选中" : @"未选中";
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        button.layer.cornerRadius = 8; button.clipsToBounds = YES;
        button.layer.borderWidth = [identifier isEqualToString:self.style.materialIdentifier] ? 2 : 0;
        button.layer.borderColor = self.view.tintColor.CGColor;
        [button.widthAnchor constraintEqualToConstant:76].active = YES;
        [button addTarget:self action:@selector(selectMaterial:) forControlEvents:UIControlEventTouchUpInside];
        [self.materialsStack addArrangedSubview:button];
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
                if (weakSelf.materialGeneration == generation) [button setImage:thumbnail forState:UIControlStateNormal];
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
- (void)deleteMaterial {
    if (self.importing || !self.style.materialIdentifier.length) return;
    NSString *identifier = self.style.materialIdentifier;
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
        self.style.materialIdentifier = @""; self.style.enabled = NO; self.enabledSwitch.on = NO;
        [self refreshControls]; [self reloadMaterials]; [self refreshPreview];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
