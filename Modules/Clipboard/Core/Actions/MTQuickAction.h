//
//  MTQuickAction.h
//  Mt
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MTQuickActionKind) {
    MTQuickActionKindText,
    MTQuickActionKindImage,
    MTQuickActionKindImageDoubleTap,
};

@interface MTQuickAction : NSObject

// Resolves ordered UUID references from the global action library.
+ (NSArray<NSDictionary<NSString *, id> *> *)actionsForKind:(MTQuickActionKind)kind;
+ (void)openAction:(NSDictionary<NSString *, id> *)action
             input:(nullable NSString *)input
 completionHandler:(nullable void (^)(BOOL success))completionHandler;

@end

NS_ASSUME_NONNULL_END
