//
//  MTHistoryMigrator.h
//  Mt
//

#import <Foundation/Foundation.h>

@class MTHistoryStore;

NS_ASSUME_NONNULL_BEGIN

@interface MTHistoryMigrationSource : NSObject

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *historyPath;
@property(nonatomic, copy, readonly) NSString *imagesPath;

+ (instancetype)sourceWithIdentifier:(NSString *)identifier
                         historyPath:(NSString *)historyPath
                          imagesPath:(NSString *)imagesPath;
- (instancetype)initWithIdentifier:(NSString *)identifier
                       historyPath:(NSString *)historyPath
                        imagesPath:(NSString *)imagesPath NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface MTHistoryMigrator : NSObject

+ (NSArray<MTHistoryMigrationSource *> *)defaultMigrationSources;

- (instancetype)initWithHistoryStore:(MTHistoryStore *)historyStore
                    migrationSources:(NSArray<MTHistoryMigrationSource *> *)migrationSources
    NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithHistoryStore:(MTHistoryStore *)historyStore legacyHistoryPath:(NSString *)legacyHistoryPath;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)migrateIfNeededWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
