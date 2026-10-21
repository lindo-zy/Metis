// MTSharedResourceIDs.h —— 共享资源层的常量与稳定 ID 工具
// （docs/development/03 §4 持久化模型 v1 的代码侧契约）。
// 动作与面板一次定义、多入口引用：ID 是资源唯一且不可变的标识。
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 权威文档 format 固定值。
FOUNDATION_EXPORT NSString *const MTSharedResourceFormat;
/// 当前 schema 版本。未知更高版本只读不可执行，不自动覆盖降级。
FOUNDATION_EXPORT NSNumber *const MTSharedResourceCurrentSchemaVersion;
/// 每次成功提交递增的 revision 起始值（合法空库也从 1 开始）。
FOUNDATION_EXPORT NSString *const MTSharedResourceChangedNotification;

/// 资源来源（binding.source）。
FOUNDATION_EXPORT NSString *const MTSharedResourceSourceKeyboard;
FOUNDATION_EXPORT NSString *const MTSharedResourceSourceGesture;
FOUNDATION_EXPORT NSString *const MTSharedResourceSourceClipboard;
FOUNDATION_EXPORT NSString *const MTSharedResourceSourceCapture;
FOUNDATION_EXPORT NSString *const MTSharedResourceSourceOther;

/// target kind：action / panel / builtin / none。
FOUNDATION_EXPORT NSString *const MTSharedTargetKindAction;
FOUNDATION_EXPORT NSString *const MTSharedTargetKindPanel;
FOUNDATION_EXPORT NSString *const MTSharedTargetKindBuiltin;
FOUNDATION_EXPORT NSString *const MTSharedTargetKindNone;

/// 动作七类型 + 存量兼容类型（旧 url / 无 type 记录保留原语义，不新增菜单）。
static inline NSArray<NSString *> *MTSharedResourceAllowedActionTypes(void) {
    return @[@"urlscheme", @"text", @"openapp", @"shortcut", @"system", @"ai", @"javascript", @"url"];
}

/// 迁移兼容标记：剪切板旧实现的 $$$ 与 @@@ 都按编码输入替换（05 §4）。
FOUNDATION_EXPORT NSString *const MTSharedCompatibilityPlaceholderDialectClipboardV1;

/// 由稳定 legacyKey 确定性派生 UUID（同输入同输出，重跑迁移幂等，
/// 不依赖持久映射表也能得到同一 ID；RFC 4122 version 5 形态）。
/// legacyKey 建议形如「来源域/文件 + 资源类型 + 旧稳定 selector/id」。
NSString *MTSharedDeterministicUUID(NSString *legacyKey);

/// UUID 字符串形状校验（宽松：大写/小写均可）。
BOOL MTSharedIsValidUUIDString(NSString *string);

NS_ASSUME_NONNULL_END
