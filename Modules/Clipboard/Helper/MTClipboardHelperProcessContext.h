//
//  MTClipboardHelperProcessContext.h
//  Mt
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, MTClipboardHelperProcessKind) {
    MTClipboardHelperProcessKindUnsupported = 0,
    MTClipboardHelperProcessKindApplication,
    MTClipboardHelperProcessKindSpringBoard,
    MTClipboardHelperProcessKindKeyboardExtension,
};

NS_ASSUME_NONNULL_BEGIN

@interface MTClipboardHelperProcessContext : NSObject

@property(nonatomic, assign, readonly) MTClipboardHelperProcessKind kind;

+ (instancetype)currentContext;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
