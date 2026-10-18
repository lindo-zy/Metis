#import <Preferences/PSSpecifier.h>
#import "MTSettingsModels.h"

NS_ASSUME_NONNULL_BEGIN

/// 按模型分组顺序生成真实 specifiers，供标准路径查询、路由与自定义 cell 共用。
FOUNDATION_EXPORT NSMutableArray<PSSpecifier *> *MTSettingsBuildSpecifiers(
    MTSettingsPageModel * _Nullable model, id target, BOOL exposeIdentifiers,
    Class _Nullable (^resolveDetail)(MTSettingsRow *row));

NS_ASSUME_NONNULL_END
