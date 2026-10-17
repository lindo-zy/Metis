// MTSharedResourceValidator.h —— 共享资源文档的结构验证（03 §4）。
// 只做类型、引用、嵌套和版本检查；不执行业务副作用、不做迁移。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const MTSharedResourceValidationErrorDomain;

typedef NS_ENUM(NSInteger, MTSharedResourceValidationCode) {
    MTSharedResourceValidationOK = 0,
    MTSharedResourceValidationNotDictionary,
    MTSharedResourceValidationFormat,
    MTSharedResourceValidationSchemaFuture,   // 更高版本：只读不可执行，不降级写
    MTSharedResourceValidationShape,
    MTSharedResourceValidationDuplicateID,
    MTSharedResourceValidationInvalidID,
    MTSharedResourceValidationActionEntry,
    MTSharedResourceValidationPanelShape,
    MTSharedResourceValidationTargetUnresolved,
    MTSharedResourceValidationCycle,
    MTSharedResourceValidationNestingTooDeep, // 面板嵌套 > 8 层
    MTSharedResourceValidationBindingShape,
    MTSharedResourceValidationLimit,
};

@interface MTSharedResourceValidator : NSObject

/// 验证一份完整文档（含 format/schemaVersion/revision 与四类数组）。
/// 返回 nil 表示通过；否则返回首个致命问题的 NSError。
+ (nullable NSError *)validateDocument:(NSDictionary *)document;

/// 仅验证 payload 形状（actions/panels/bindings/groups），提交前内部使用。
+ (nullable NSError *)validatePayloadOfDocument:(NSDictionary *)document;

@end

NS_ASSUME_NONNULL_END
