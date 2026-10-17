#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 经 SpringBoard 私有能力进入系统「照片」App 的最近照片。
/// 优先激活照片 App 的应用快捷方式（App Shortcuts，MOST_RECENT_PHOTO，
/// 获取方式与 MetisKeyboard MTQuickActionProvider 同源）；快捷方式缺失时回退为
/// 直接拉起照片 App（停在图库页，即最近照片网格）。
@interface MTPhotoShortcut : NSObject

/// 主线程调用；返回是否已分发（不保证照片 App 已到前台）。
/// 非主线程时转主线程异步执行并返回 NO。
+ (BOOL)openMostRecentPhoto;

@end

NS_ASSUME_NONNULL_END
