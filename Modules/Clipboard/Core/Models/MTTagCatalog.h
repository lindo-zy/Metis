//
//  MTTagCatalog.h
//  Mt
//

#import <Foundation/Foundation.h>

@class MTTag;

NS_ASSUME_NONNULL_BEGIN

@interface MTTagCatalog : NSObject

+ (instancetype)sharedCatalog;
- (NSArray<MTTag *> *)reloadTags;
- (NSArray<MTTag *> *)reloadTagsForcingDiskRead:(BOOL)forceDiskRead;
- (NSArray<MTTag *> *)tags;
- (nullable MTTag *)tagForUUID:(nullable NSString *)uuid;

@end

NS_ASSUME_NONNULL_END
