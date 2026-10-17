//
//  MTTagStore.h
//  Mt
//

#import <Foundation/Foundation.h>

@class MTTag;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kMTTagStoreErrorDomain;

@interface MTTagStore : NSObject

@property(nonatomic, copy, readonly) NSString *tagsPath;
@property(nonatomic, strong, readonly) NSBundle *localizationBundle;

+ (NSString *)defaultTagsPath;

- (instancetype)initWithTagsPath:(NSString *)tagsPath
              localizationBundle:(NSBundle *)localizationBundle NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (nullable NSMutableArray<MTTag *> *)loadTagsWithError:(NSError **)error;
- (nullable NSMutableArray<MTTag *> *)readTagsWithError:(NSError **)error;
- (BOOL)ensureDefaultTagsFileExistsWithError:(NSError **)error;
- (BOOL)saveTags:(NSArray<MTTag *> *)tags error:(NSError **)error;
- (BOOL)restoreDefaultTagsWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
