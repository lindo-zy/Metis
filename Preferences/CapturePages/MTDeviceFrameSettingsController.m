#import <Preferences/PSListController.h>
#import "../../Modules/Capture/Sources/Editor/MTDeviceFrameViewController.h"

/// 预配置素材入口。示例图在本地绘制，不读取剪贴板、不抓取用户当前屏幕。
@interface MTDeviceFrameSettingsController : PSListController
@property (nonatomic, strong) MTDeviceFrameViewController *frameController;
@end

@implementation MTDeviceFrameSettingsController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"DeviceFrame" target:self];
    return _specifiers;
}
- (UIImage *)exampleImage {
    CGSize size = CGSizeMake(393,852);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
    format.scale = 1; format.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [[UIColor colorWithWhite:0.96 alpha:1] setFill]; UIRectFill((CGRect){CGPointZero,size});
            [@"9:41" drawAtPoint:CGPointMake(28,24) withAttributes:@{
                NSFontAttributeName:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.blackColor}];
            [@"Metis" drawAtPoint:CGPointMake(28,110) withAttributes:@{
                NSFontAttributeName:[UIFont systemFontOfSize:38 weight:UIFontWeightBold],NSForegroundColorAttributeName:UIColor.blackColor}];
            [@"套壳素材预览" drawAtPoint:CGPointMake(28,164) withAttributes:@{
                NSFontAttributeName:[UIFont systemFontOfSize:18],NSForegroundColorAttributeName:UIColor.darkGrayColor}];
            NSArray *rows = @[@"预先选择机壳与背景",@"保存配置",@"触发套壳截图",@"自动合成并输出"];
            for (NSUInteger i=0;i<rows.count;i++) {
                CGRect row = CGRectMake(24,230+i*78,345,64);
                [UIColor.whiteColor setFill]; [[UIBezierPath bezierPathWithRoundedRect:row cornerRadius:14] fill];
                [rows[i] drawAtPoint:CGPointMake(42,row.origin.y+22) withAttributes:@{
                    NSFontAttributeName:[UIFont systemFontOfSize:17],NSForegroundColorAttributeName:UIColor.blackColor}];
            }
            [@"截图后无需再次编辑或确认" drawInRect:CGRectMake(28,600,337,60) withAttributes:@{
                NSFontAttributeName:[UIFont systemFontOfSize:18 weight:UIFontWeightMedium],NSForegroundColorAttributeName:UIColor.darkGrayColor}];
        }];
}
- (void)configureFrame {
    if (!self.view.window || self.presentedViewController || self.frameController) return;
    __weak typeof(self) weakSelf = self;
    MTDeviceFrameViewController *controller = [[MTDeviceFrameViewController alloc] initWithImage:[self exampleImage]
        configuration:[MTDeviceFrameConfiguration rememberedConfiguration]
        completion:^(BOOL completed, MTDeviceFrameConfiguration *configuration, MTOutputAction action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !self.frameController || self.presentedViewController != self.frameController) return;
            self.frameController = nil;
            [self dismissViewControllerAnimated:YES completion:nil];
        }];
    controller.configurationOnly = YES;
    self.frameController = controller;
    [self presentViewController:controller animated:YES completion:nil];
}
- (void)dealloc { [_frameController invalidate]; }
@end
