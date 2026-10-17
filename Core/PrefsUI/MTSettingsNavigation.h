#import <UIKit/UIKit.h>

@class PSSpecifier;

NS_ASSUME_NONNULL_BEGIN

/// UIKit 设置页进入 Preferences 页面时，先恢复框架导航上下文再压栈。
/// specifier 保留调用方携带的页面参数；普通 UIKit 目标无需 Preferences 配置。
FOUNDATION_EXPORT void MTSettingsPushController(UIViewController *source,
                                               UIViewController *controller,
                                               PSSpecifier * _Nullable specifier,
                                               BOOL animated);

NS_ASSUME_NONNULL_END
