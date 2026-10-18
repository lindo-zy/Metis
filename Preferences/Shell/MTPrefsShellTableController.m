#import "MTPrefsShellTableController.h"
#import "MTPrefsSubbundleLoader.h"
#import "MTLog.h"
#import "MTSettingsNavigation.h"

@implementation MTPrefsShellTableController

- (Class)controllerClassForSettingsRow:(MTSettingsRow *)row {
    if (row.routeKind == MTSettingsRouteSubbundle) {
        return [MTPrefsSubbundleLoader loadControllerClassFromBundle:row.subBundle
                                                         classNamed:row.className error:nil];
    }
    return [super controllerClassForSettingsRow:row];
}

- (void)performRouteForRow:(MTSettingsRow *)row {
    if (row.routeKind == MTSettingsRouteSubbundle) {
        Class controllerClass = [self controllerClassForSettingsRow:row];
        if (!controllerClass) {
            MTLogError(MTLogModulePrefs, @"state=shell-route-load-failed bundle=%@ class=%@ row=%@",
                       row.subBundle, row.className, row.identifier);
            [self presentUnavailableAlertWithTitle:row.title];
            return;
        }
        id controller = [[controllerClass alloc] init];
        MTSettingsPushController(self, controller, [self specifierForID:row.identifier], YES);
        return;
    }
    // ShellClass / InPage / None 交给基础层默认实现。
    [super performRouteForRow:row];
}

- (void)presentUnavailableAlertWithTitle:(NSString *)title {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:@"无法载入该分类的设置页面，请重新安装当前版本后重试。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
