// MTPrefsSubbundleLoader —— 设置子包控制器的统一加载入口。
// 详情页类分布在 MetisKeyboardPrefs / MetisClipboardPrefs / MetisCapturePrefs
// 三个子包里；Shell 经此加载复用，不复制控制器实现（04 §1）。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTPrefsSubbundleLoader : NSObject

/// 加载子包并返回目标控制器类；失败时返回 nil 并填充 error。
/// bundle 缺失 / 加载失败 / 类不存在分别给出可区分的错误码。
+ (nullable Class)loadControllerClassFromBundle:(NSString *)bundleName
                                     classNamed:(NSString *)controllerName
                                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
