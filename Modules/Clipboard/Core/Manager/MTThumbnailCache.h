//
//  MTThumbnailCache.h
//  Mt
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MTThumbnailCompletion)(UIImage *_Nullable image);

@interface MTThumbnailCache : NSObject

@property(class, nonatomic, copy, readonly) NSString *defaultCacheDirectoryPath;

- (instancetype)init;
- (instancetype)initWithCacheDirectoryPath:(NSString *)cacheDirectoryPath NS_DESIGNATED_INITIALIZER;

- (void)thumbnailForImageName:(NSString *)imageName
                    imagePath:(NSString *)imagePath
                   targetSize:(CGSize)targetSize
                        scale:(CGFloat)scale
                   completion:(MTThumbnailCompletion)completion;
- (void)removeAllMemoryCachedThumbnails;
- (void)performWhenIdle:(dispatch_block_t)completion;

@end

NS_ASSUME_NONNULL_END
