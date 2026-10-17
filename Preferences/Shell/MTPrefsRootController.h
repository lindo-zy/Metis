// MTPrefsRootController —— Metis 唯一设置入口首页（docs/development/02 §1）。
// 首页固定：启用 Metis 总开关 + 五个配置分类（全局/键盘/剪切板/截图/其他）
// 直达实际配置页；没有模块开关、启用状态与计数（v3 P03）。
#import <Preferences/Preferences.h>

/// 分类页元信息。分类只是页面组织，不制造依赖开关（P02/P03）。
@interface MTPrefsCategoryInfo : NSObject
@property (nonatomic, copy) NSString *categoryID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *iconName;              // SF Symbol 名
@property (nonatomic, copy, nullable) NSString *subBundle;   // 详细页所在子包（nil = Shell 内控制器）
@property (nonatomic, copy, nullable) NSString *subController;
+ (NSArray<MTPrefsCategoryInfo *> *)allCategories;
@end

@interface MTPrefsRootController : PSListController
- (NSNumber *)globalEnabledForSpecifier:(PSSpecifier *)specifier;
- (void)setGlobalEnabled:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier;
@end
