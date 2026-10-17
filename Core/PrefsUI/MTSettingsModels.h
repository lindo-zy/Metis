// MTSettingsModels —— 设置页卡片行/分区/页面模型（docs/development/02 §8）。
// Foundation-only：宿主测试在 macOS 上直接编译本文件；UIKit 渲染
// （MTSettingsTableController 一侧）经本模型对接，不参与宿主编译。
// 行/分区/文案结构以设计稿 assets/metis-settings-v3.png 为权威，
// 各页面模型（Shell/KeyboardPages）从这里拼装。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 行类型：link=可点按导航；toggle=开关行；info=不可交互说明行。
typedef NS_ENUM(NSInteger, MTSettingsRowKind) {
    MTSettingsRowKindLink = 0,
    MTSettingsRowKindToggle,
    MTSettingsRowKindInfo,
};

/// 路由描述：link 行被点按后由视图层解析目标控制器。
typedef NS_ENUM(NSInteger, MTSettingsRouteKind) {
    MTSettingsRouteNone = 0,    ///< 不导航（info 行，或由宿主自行处理）
    MTSettingsRouteShellClass,  ///< className 在当前设置壳 bundle 内（NSClassFromString）
    MTSettingsRouteSubbundle,   ///< subBundle 包内的 className（MTPrefsSubbundleLoader 同语义）
    MTSettingsRouteInPage,      ///< 留在当前页：视图层按 identifier 定位强调（搜索命中首页项）
};

@interface MTSettingsRow : NSObject
/// 稳定 ID：搜索定位与 flash 强调（02 §3 以稳定 ID 映射，不按下标）。
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, copy, nullable) NSString *iconName;   ///< SF Symbol 名；nil = 无图标瓦片
@property (nonatomic, copy, nullable) NSString *colorName;  ///< 瓦片色 token（MTSettingsStyle 解析）
@property (nonatomic, assign) MTSettingsRowKind kind;
@property (nonatomic, assign) MTSettingsRouteKind routeKind;
@property (nonatomic, copy, nullable) NSString *subBundle;
@property (nonatomic, copy, nullable) NSString *className;  ///< 目标控制器类名（字符串，避免链接期依赖）
@property (nonatomic, strong, nullable) id userInfo;
/// toggle 行状态变化回调（视图层挂接；模型构建时为 nil）。
@property (nonatomic, copy, nullable) void (^toggleHandler)(BOOL on);
+ (instancetype)linkRowWithIdentifier:(NSString *)identifier title:(NSString *)title;
@end

@interface MTSettingsSection : NSObject
@property (nonatomic, copy, nullable) NSString *headerTitle;
@property (nonatomic, copy, nullable) NSString *footerText;
@property (nonatomic, copy) NSArray<MTSettingsRow *> *rows;
+ (instancetype)sectionWithRows:(NSArray<MTSettingsRow *> *)rows;
@end

@interface MTSettingsPageModel : NSObject
/// 大标题下的灰色副标题（如「新建动作 · 选择动作类型」）。
@property (nonatomic, copy, nullable) NSString *introSubtitle;
/// 页面级页脚（设计稿底部说明文字）。
@property (nonatomic, copy, nullable) NSString *footerText;
@property (nonatomic, copy) NSArray<MTSettingsSection *> *sections;
/// 深度优先查找行；找不到返回 nil。
- (nullable MTSettingsRow *)rowWithIdentifier:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
