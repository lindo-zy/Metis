// MTProcessContext.h —— 进程分类（03-architecture §1、06 MT-003）。
// constructor 只允许用它做分类后再决定动作；分类本身不触碰需要启动完成的
// 私有 singleton。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MTProcessKind) {
    MTProcessKindUnsupported = 0,
    MTProcessKindSpringBoard,
    MTProcessKindUIKitApplication,
    MTProcessKindKeyboardExtension,
    MTProcessKindPasteServices,
};

@interface MTProcessContext : NSObject

@property (nonatomic, assign, readonly) MTProcessKind kind;
@property (nonatomic, copy, readonly, nullable) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly, nullable) NSString *processName;

+ (instancetype)currentContext;

- (BOOL)isSpringBoard;
- (BOOL)isPasteTipProcess;   // druid / pasted
- (BOOL)isUIKitHost;         // 普通 UIKit App 或键盘扩展

@end

NS_ASSUME_NONNULL_END
