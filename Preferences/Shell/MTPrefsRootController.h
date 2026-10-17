// MTPrefsRootController —— Metis 唯一设置入口首页（02-settings-ux §2 线框）。
#import <Preferences/Preferences.h>

@interface MTPrefsRootController : PSListController
- (NSString *)mtStatusLineText:(PSSpecifier *)specifier;
@end

/// 模块页元信息（标题/副标题/详细设置子包）。详细设置子包缺失时模块页
/// 显示“此版本尚未提供”并禁止进入（02-settings-ux §3）。
@interface MTPrefsModuleInfo : NSObject
@property (nonatomic, copy) NSString *moduleID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *subBundle;      // MetisCapturePrefs 等
@property (nonatomic, copy) NSString *subController;  // 子包根控制器类名
+ (NSArray<MTPrefsModuleInfo *> *)allModules;
- (BOOL)subBundleAvailable;
@end
