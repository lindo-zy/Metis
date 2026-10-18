// MTSettingsTableController —— 设计稿风格设置页基类（inset grouped 卡片 + 大标题）。
// 模型驱动：子类提供 MTSettingsPageModel 并覆写 settingsRowSelected/settingsRowToggle；
// 路由默认实现只覆盖「压栈到模型描述的控制器」，Shell 子包加载在 Shell 基类补齐。
#import <Preferences/PSListController.h>
#import "MTSettingsModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTSettingsTableController : PSListController

/// 当前渲染的页面模型；赋值后调用 render 强制刷新。
@property (nonatomic, strong, nullable) MTSettingsPageModel *model;
/// 搜索态替换渲染的临时模型（nil = 正常渲染 model）。
@property (nonatomic, strong, nullable) MTSettingsPageModel *overlayModel;
/// 进入页面后按 identifier 滚动定位并闪烁强调（搜索直达用，一次性消费）。
@property (nonatomic, copy, nullable) NSString *pendingFocusIdentifier;

/// 应用当前模型（含 intro/footer 附件视图）并刷新表格。
- (void)render;
/// 页面级 footer 文本（子类在 model.footerText 之外补充时覆写）。
- (void)applyFooterText;
/// 行点按入口（子类覆写；默认实现执行路由）。
- (void)settingsRowSelected:(MTSettingsRow *)row;
/// 路由执行：ShellClass → NSClassFromString；Subbundle → 由子类/宿主实现。
- (void)performRouteForRow:(MTSettingsRow *)row;
/// 与 Preferences 的 detail 路由共用目标解析；Shell 子类补齐子包加载。
- (nullable Class)controllerClassForSettingsRow:(MTSettingsRow *)row;
/// 按 identifier 滚动到行并做一次透明度脉冲强调；找不到时静默返回。
- (void)flashRowWithIdentifier:(NSString *)identifier;
/// 大标题下方的灰色副标题文本（introSubtitle 已由 render 应用）。
@property (nonatomic, readonly, nullable) NSString *introSubtitleText;

/// 表格顶部的自定义附件头（品牌头/搜索框）。返回 nil 时按 introSubtitle 生成简单副标题头。
- (nullable UIView *)makeTableHeaderView;

@end

NS_ASSUME_NONNULL_END
