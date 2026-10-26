#import <UIKit/UIKit.h>
// 自定义动作的沙盒调试台；只接收草稿，不保存动作。网络请求真实执行，文本与跳转仅预览。
@interface MTPJavaScriptTestController : UIViewController
@property (nonatomic, copy) NSString *source;
@end
