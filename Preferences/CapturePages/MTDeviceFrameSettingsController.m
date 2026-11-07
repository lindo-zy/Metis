#import <Preferences/PSViewController.h>
#import "../../Modules/Capture/Sources/Editor/MTDeviceFrameViewController.h"
#import "../../Modules/Capture/Sources/Editor/MTDeviceFrameRenderer.h"

/// 保留 Preferences 的路由契约，内容直接嵌入编辑器，不再展示入口列表或二次模态。
@interface MTDeviceFrameSettingsController : PSViewController
@property (nonatomic, strong) MTDeviceFrameViewController *frameController;
@end

@implementation MTDeviceFrameSettingsController
- (NSArray *)specifiers { return @[]; }
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"套壳设置";self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    UIView *content=[UIView new];content.backgroundColor=[UIColor colorWithWhite:0.06 alpha:1];self.view=content;
    MTDeviceFrameViewController *controller=[[MTDeviceFrameViewController alloc]initWithImage:[MTDeviceFrameViewController exampleImage]
        configuration:[MTDeviceFrameConfiguration rememberedConfiguration]
        completion:^(BOOL completed,MTDeviceFrameConfiguration *configuration,MTOutputAction action){}];
    controller.configurationOnly=YES;self.frameController=controller;
    [self addChildViewController:controller];controller.view.translatesAutoresizingMaskIntoConstraints=NO;[content addSubview:controller.view];
    [NSLayoutConstraint activateConstraints:@[[controller.view.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [controller.view.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [controller.view.topAnchor constraintEqualToAnchor:content.topAnchor],
        [controller.view.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]]];
    [controller didMoveToParentViewController:self];self.navigationItem.rightBarButtonItem=controller.navigationItem.rightBarButtonItem;
    UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];[appearance configureWithOpaqueBackground];
    appearance.backgroundColor=content.backgroundColor;appearance.titleTextAttributes=@{NSForegroundColorAttributeName:UIColor.whiteColor};
    self.navigationItem.standardAppearance=appearance;self.navigationItem.scrollEdgeAppearance=appearance;
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];if(self.isMovingFromParentViewController || self.navigationController.isBeingDismissed)[self.frameController invalidate];
}
- (void)dealloc {[_frameController invalidate];}
@end
