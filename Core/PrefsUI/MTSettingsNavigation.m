#import "MTSettingsNavigation.h"
#import <Preferences/PSViewController.h>

void MTSettingsPushController(UIViewController *source, UIViewController *controller,
                              PSSpecifier *specifier, BOOL animated) {
    UINavigationController *navigation = source.navigationController;
    if (!navigation || !controller) return;

    if ([controller isKindOfClass:PSViewController.class]) {
        PSViewController *context = nil;
        // 首页作为 PS 容器的 child 嵌入；其他 UIKit 页面从导航栈继承上下文。
        for (UIViewController *ancestor = source; ancestor; ancestor = ancestor.parentViewController) {
            if ([ancestor isKindOfClass:PSViewController.class]) {
                context = (PSViewController *)ancestor;
                break;
            }
        }
        if (!context) {
            for (UIViewController *candidate in navigation.viewControllers.reverseObjectEnumerator) {
                if ([candidate isKindOfClass:PSViewController.class]) {
                    context = (PSViewController *)candidate;
                    break;
                }
            }
        }
        PSViewController *preferencesController = (PSViewController *)controller;
        // Preferences 的实际 root 是 PSRootController（导航控制器）；Theos
        // 头文件将此属性声明为 PSViewController，沿用已有 root，缺失时用宿主导航栈。
        preferencesController.rootController = context.rootController ?: (id)navigation;
        preferencesController.parentController = context;
        if (specifier) preferencesController.specifier = specifier;
    }
    [navigation pushViewController:controller animated:animated];
}
