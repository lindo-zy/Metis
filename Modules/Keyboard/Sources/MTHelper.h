#ifndef MTHelper_h
#define MTHelper_h

#import <UIKit/UIKit.h>

// 图标着色策略：同一个 SF Symbol 在设置列表、键盘按钮、面板预览里由不同
// 宿主染色，策略必须由调用点显式声明，不能依赖图片自身的渲染模式。
typedef NS_ENUM(NSInteger, MTIconTintPolicy) {
    // 单色模板，颜色交给宿主的 tintColor（键盘按钮、悬浮架）。
    MTIconTintPolicyInherit = 0,
    // 单色并固定染成 systemBlue（设置内列表）。
    MTIconTintPolicySystemBlue,
    // 保留 SF Symbol 自带的多色配色；单色符号仍为模板。
    MTIconTintPolicyPreserveMulticolor,
};

@interface MTHelper : NSObject
+(UIImage *)imageForTypeXWithPlaceholder:(BOOL)placeholder;
+(UIImage *)imageForName:(NSString *)imageName policy:(MTIconTintPolicy)policy completion:(void (^)(BOOL isThirteen, BOOL isCustomImagePath))handler;
+(UIImage *)imageFromArray:(NSArray *)array atIndex:(NSUInteger)index policy:(MTIconTintPolicy)policy completion:(void (^)(BOOL isThirteen, BOOL isCustomImagePath))handler;
+(NSString *)labelFromArray:(NSArray *)array atIndex:(NSUInteger)index;
+(NSString *)actionNameFromArray:(NSArray *)array atIndex:(NSUInteger)index;
+(void)showSearchCountEasterAlertFor:(id)object searchController:(UISearchController *)searchController count:(NSUInteger)count delay:(double)delay;
+(NSString *)localizedStringForActionNamed:(NSString *)actionName shortName:(BOOL)shortName bundle:(NSBundle *)tweakBundle;
+(NSString *)customNameForShortcutItem:(NSDictionary *)item;
+(NSString *)customIconForShortcutItem:(NSDictionary *)item;
+(NSString *)appIconBundleIDForShortcutItem:(NSDictionary *)item;
+(UIImage *)appIconImageForBundleID:(NSString *)bundleID;
+(NSString *)defaultIconForActionType:(NSString *)type;
+(UIImage *)imageForCustomActionEntry:(NSDictionary *)entry;
// 仅解析 SF Symbol 配置（轻量，可主线程调用）；App 图标查询含磁盘与私有 API，
// 调用方必须走异步管线。
+(UIImage *)symbolImageForIconConfig:(NSString *)icon;
+(UIImage *)imageForIconConfig:(NSString *)icon defaultSymbolName:(NSString *)defaultName;
+(UIImage *)imageForIconConfig:(NSString *)icon defaultSymbolName:(NSString *)defaultName policy:(MTIconTintPolicy)policy;
+(NSString *)resolvedIconNameForShortcutItem:(NSDictionary *)item defaultName:(NSString *)defaultName;
@end

#endif
