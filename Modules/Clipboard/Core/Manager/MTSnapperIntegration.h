//
//  MTSnapperIntegration.h
//  Mt
//

#import <Foundation/Foundation.h>

@class MTPasteboardItem;

NS_ASSUME_NONNULL_BEGIN

/// Optional bridge to Snapper 3. It never links against Snapper: all compatibility checks
/// happen at runtime, so Mt continues to work unchanged when Snapper is absent.
@interface MTSnapperIntegration : NSObject

+ (BOOL)isAvailable;
+ (BOOL)floatPasteboardItem:(MTPasteboardItem *)item;

@end

NS_ASSUME_NONNULL_END
