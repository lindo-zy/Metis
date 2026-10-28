#import "MTPSubActionPickerController.h"

@implementation MTPSubActionPickerController

- (void)viewDidLoad {
    self.selectionManagedExternally = YES;
    // 任意动作都能成为子动作候选：自定义动作可在此就地创建，无需先绕道
    // 自定义动作管理页；内置动作目录由 fullOrder 原样提供。保存后的回传
    // （批量勾选 / 单选延迟 completion+pop）由基类 customActionWasCreated:
    // 与 viewDidAppear 统一承担。
    self.allowsCreatingCustomActions = YES;
    [super viewDidLoad];
}

@end
