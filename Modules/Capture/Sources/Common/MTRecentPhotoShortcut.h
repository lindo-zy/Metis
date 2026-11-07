#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// 通过照片 App 的「最近一张照片」快捷方式直达最近资产。快捷项来自
/// SpringBoard 的应用快捷方式目录（与主屏长按菜单同源，AppIntents 快捷方式
/// 由系统合并进该目录），执行走 SBIconView 的快捷方式激活通道。
/// 返回 YES 表示已派发激活；NO 表示目录解析不到该快捷项或私有通道不可用，
/// 调用方应回落 URL 打开链。只能在 SpringBoard 主线程调用。
BOOL MTLaunchPhotosMostRecentShortcut(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
