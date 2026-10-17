//
//  MTHistoryRepository.m
//  Mt
//

#import "MTHistoryRepository.h"
#import "MTHistoryMigrator.h"
#import "MTHistoryStore.h"

#import <HBLog.h>

static void *mtHistoryQueueSpecificKey = &mtHistoryQueueSpecificKey;
static NSInteger const kMTClipboardCoreHistoryStoreBusyTimeoutMilliseconds = 250;

@implementation MTHistoryRepository {
    NSString *_databasePath;
    NSString *_imagesPath;
    MTHistoryLimitProvider _limitProvider;

    dispatch_queue_t _historyQueue;
    BOOL _didPrepareHistoryStore;
    NSError *_prepareHistoryStoreError;
    MTHistoryStore *_historyStore;
}

#pragma mark - Paths

+ (NSString *)defaultDatabasePath {
    return [MTHistoryStore defaultDatabasePath];
}

#pragma mark - Lifecycle

- (instancetype)initWithDatabasePath:(NSString *)databasePath
                          imagesPath:(NSString *)imagesPath
                       limitProvider:(MTHistoryLimitProvider)limitProvider {
    self = [super init];
    if (self) {
        _databasePath = [databasePath copy];
        _imagesPath = [imagesPath copy];
        _limitProvider = [limitProvider copy];
        _historyQueue = dispatch_queue_create("com.lindo.kayoko.queue.history", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_historyQueue, mtHistoryQueueSpecificKey, mtHistoryQueueSpecificKey, NULL);
    }
    return self;
}

#pragma mark - Preparation

- (void)prepareStore {
    [self performAsync:^{
      NSError *error = nil;
      if (![self ensureStorePreparedOnQueueWithError:&error]) {
          HBLogDebug(@"Mt: Failed to prepare v4 history store: %@", error);
      }
    }];
}

- (void)ensureStorePrepared {
    NSError *error = nil;
    if (![self ensureStorePreparedWithError:&error]) {
        HBLogDebug(@"Mt: Failed to prepare v4 history store: %@", error);
    }
}

- (BOOL)ensureStorePreparedWithError:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    [self performSync:^{
      success = [self ensureStorePreparedOnQueueWithError:&blockError];
    }];
    if (error) {
        *error = blockError;
    }
    return success;
}

- (void)closeStore {
    [self performSync:^{
      [_historyStore closeDatabase];
      _historyStore = nil;
      _didPrepareHistoryStore = NO;
      _prepareHistoryStoreError = nil;
    }];
}

#pragma mark - Maintenance

- (void)checkpointWriteAheadLog {
    [self performAsync:^{
      NSError *error = nil;
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&error];
      BOOL success = historyStore && [historyStore checkpointWriteAheadLogWithError:&error];
      if (!success) {
          HBLogDebug(@"Mt: Failed to checkpoint history database: %@", error);
      }
    }];
}

#pragma mark - Search Index

- (BOOL)upgradeSearchIndexWithError:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    [self performSync:^{
      MTHistoryStore *historyStore = [self historyStoreOnQueue];
      success = [historyStore upgradeSearchIndexWithError:&blockError];
      if (success) {
          _didPrepareHistoryStore = YES;
          _prepareHistoryStoreError = nil;
      } else {
          _didPrepareHistoryStore = NO;
          _prepareHistoryStoreError = blockError;
      }
    }];
    if (error) {
        *error = blockError;
    }
    return success;
}

#pragma mark - History Writes

- (BOOL)addItemDictionary:(NSDictionary<NSString *, id> *)dictionary
             toHistoryKey:(NSString *)historyKey
                    error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    [self performSync:^{
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&blockError];
      success = historyStore && [historyStore addItemDictionary:dictionary
                                                   toHistoryKey:historyKey
                                                          limit:[self limitForHistoryKey:historyKey]
                                                          error:&blockError];
    }];
    if (error) {
        *error = blockError;
    }
    return success;
}

- (void)addItemDictionaries:(NSArray<NSDictionary<NSString *, id> *> *)dictionaries
               toHistoryKey:(NSString *)historyKey
                 completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> *savedDictionaries))completion {
    [self performAsync:^{
      NSMutableArray<NSDictionary<NSString *, id> *> *savedDictionaries =
          [[NSMutableArray alloc] initWithCapacity:[dictionaries count]];
      for (NSDictionary<NSString *, id> *dictionary in dictionaries) {
          NSError *error = nil;
          MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&error];
          BOOL success = historyStore && [historyStore addItemDictionary:dictionary
                                                            toHistoryKey:historyKey
                                                                   limit:[self limitForHistoryKey:historyKey]
                                                                   error:&error];
          if (!success) {
              HBLogDebug(@"Mt: Failed to add history item: %@", error);
              continue;
          }
          NSError *latestError = nil;
          NSDictionary<NSString *, id> *savedDictionary =
              [historyStore latestItemForHistoryKey:historyKey error:&latestError] ?: dictionary;
          if (latestError) {
              HBLogDebug(@"Mt: Failed to load saved history item: %@", latestError);
          }
          [savedDictionaries addObject:savedDictionary];
      }

      if (!completion) {
          return;
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(savedDictionaries);
      });
    }];
}

- (BOOL)moveItemDictionaryToTop:(NSDictionary<NSString *, id> *)dictionary
                   inHistoryKey:(NSString *)historyKey
                          error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    [self performSync:^{
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&blockError];
      success = historyStore && [historyStore moveItemDictionaryToTop:dictionary
                                                         inHistoryKey:historyKey
                                                                limit:[self limitForHistoryKey:historyKey]
                                                                error:&blockError];
    }];
    if (error) {
        *error = blockError;
    }
    return success;
}

- (BOOL)removeItemDictionary:(NSDictionary<NSString *, id> *)dictionary
              fromHistoryKey:(NSString *)historyKey
           shouldRemoveImage:(BOOL)shouldRemoveImage
                       error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    [self performSync:^{
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&blockError];
      success = historyStore && [historyStore removeItemDictionary:dictionary
                                                    fromHistoryKey:historyKey
                                                 shouldRemoveImage:shouldRemoveImage
                                                             error:&blockError];
    }];
    if (error) {
        *error = blockError;
    }
    return success;
}

- (void)removeItemDictionary:(NSDictionary<NSString *, id> *)dictionary
              fromHistoryKey:(NSString *)historyKey
           shouldRemoveImage:(BOOL)shouldRemoveImage
                  completion:(void (^)(BOOL success))completion {
    [self performAsync:^{
      NSError *error = nil;
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&error];
      BOOL success = historyStore && [historyStore removeItemDictionary:dictionary
                                                         fromHistoryKey:historyKey
                                                      shouldRemoveImage:shouldRemoveImage
                                                                  error:&error];
      if (!success) {
          HBLogDebug(@"Mt: Failed to remove history item: %@", error);
      }
      [self dispatchCompletion:completion success:success];
    }];
}

- (void)moveItemDictionary:(NSDictionary<NSString *, id> *)dictionary
            fromHistoryKey:(NSString *)sourceHistoryKey
              toHistoryKey:(NSString *)destinationHistoryKey
                completion:(void (^)(BOOL success))completion {
    [self performAsync:^{
      NSError *error = nil;
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&error];
      BOOL success = historyStore && [historyStore moveItemDictionary:dictionary
                                                       fromHistoryKey:sourceHistoryKey
                                                         toHistoryKey:destinationHistoryKey
                                                     destinationLimit:[self limitForHistoryKey:destinationHistoryKey]
                                                                error:&error];
      if (!success) {
          HBLogDebug(@"Mt: Failed to move history item: %@", error);
      }
      [self dispatchCompletion:completion success:success];
    }];
}

#pragma mark - Note and Tag Persistence

- (void)setNote:(NSString *)note
         tagUUID:(NSString *)tagUUID
forItemDictionary:(NSDictionary<NSString *, id> *)dictionary
     inHistoryKey:(NSString *)historyKey
       completion:(void (^)(BOOL success))completion {
    [self performAsync:^{
      NSError *error = nil;
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&error];
      BOOL success = historyStore && [historyStore setNote:note
                                                   tagUUID:tagUUID
                                          forItemDictionary:dictionary
                                               inHistoryKey:historyKey
                                                      error:&error];
      if (!success) {
          HBLogDebug(@"Mt: Failed to set history item note and tag: %@", error);
      }
      [self dispatchCompletion:completion success:success];
    }];
}

- (void)replaceContent:(NSString *)content
     forItemDictionary:(NSDictionary<NSString *, id> *)dictionary
          inHistoryKey:(NSString *)historyKey
            completion:(void (^)(BOOL success))completion {
    [self performAsync:^{
      NSError *error = nil;
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&error];
      BOOL success = historyStore && [historyStore replaceContent:content
                                               forItemDictionary:dictionary
                                                    inHistoryKey:historyKey
                                                           error:&error];
      if (!success) {
          HBLogDebug(@"Mt: Failed to replace history item content: %@", error);
      }
      [self dispatchCompletion:completion success:success];
    }];
}

#pragma mark - Bulk Removal

- (void)removeItemsFromHistoryKey:(NSString *)historyKey
               shouldRemoveImages:(BOOL)shouldRemoveImages
                       completion:(void (^)(BOOL success))completion {
    [self performAsync:^{
      NSError *error = nil;
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&error];
      BOOL success = historyStore && [historyStore removeItemsFromHistoryKey:historyKey
                                                          shouldRemoveImages:shouldRemoveImages
                                                                       error:&error];
      if (!success) {
          HBLogDebug(@"Mt: Failed to remove history items: %@", error);
      }
      [self dispatchCompletion:completion success:success];
    }];
}

- (void)removeImageItemsFromHistoryKey:(NSString *)historyKey
                            completion:(void (^)(BOOL success))completion {
    [self performAsync:^{
      NSError *error = nil;
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&error];
      BOOL success = historyStore && [historyStore removeImageItemsFromHistoryKey:historyKey error:&error];
      if (!success) {
          HBLogDebug(@"Mt: Failed to remove image history items: %@", error);
      }
      [self dispatchCompletion:completion success:success];
    }];
}

#pragma mark - History Reads

- (NSMutableArray<NSDictionary<NSString *, id> *> *)itemsForHistoryKey:(NSString *)historyKey error:(NSError **)error {
    __block NSMutableArray<NSDictionary<NSString *, id> *> *history = nil;
    __block NSError *blockError = nil;
    [self performSync:^{
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&blockError];
      history = historyStore ? [historyStore itemsForHistoryKey:historyKey error:&blockError] : nil;
    }];
    if (error) {
        *error = blockError;
    }
    return history ?: [[NSMutableArray alloc] init];
}

- (void)itemsForHistoryKey:(NSString *)historyKey completion:(MTHistoryItemsCompletion)completion {
    [self itemsForHistoryKey:historyKey searchCriteria:nil completion:completion];
}

- (NSMutableArray<NSDictionary<NSString *, id> *> *)itemsForHistoryKey:(NSString *)historyKey
                                                        searchCriteria:(MTSearchCriteria *)searchCriteria
                                                                 error:(NSError **)error {
    __block NSMutableArray<NSDictionary<NSString *, id> *> *history = nil;
    __block NSError *blockError = nil;
    [self performSync:^{
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&blockError];
      history = historyStore
                    ? [historyStore itemsForHistoryKey:historyKey searchCriteria:searchCriteria error:&blockError]
                    : nil;
    }];
    if (error) {
        *error = blockError;
    }
    return history ?: [[NSMutableArray alloc] init];
}

- (void)itemsForHistoryKey:(NSString *)historyKey
            searchCriteria:(MTSearchCriteria *)searchCriteria
                completion:(MTHistoryItemsCompletion)completion {
    [self performAsync:^{
      NSError *error = nil;
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&error];
      NSMutableArray<NSDictionary<NSString *, id> *> *history =
          historyStore ? [historyStore itemsForHistoryKey:historyKey searchCriteria:searchCriteria error:&error] : nil;
      if (error) {
          HBLogDebug(@"Mt: Failed to load history items: %@", error);
      }
      NSMutableArray<NSDictionary<NSString *, id> *> *items = history ?: [[NSMutableArray alloc] init];
      if (!completion) {
          return;
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(items, error);
      });
    }];
}

- (NSDictionary<NSString *, id> *)latestItemForHistoryKey:(NSString *)historyKey error:(NSError **)error {
    __block NSDictionary<NSString *, id> *dictionary = nil;
    __block NSError *blockError = nil;
    [self performSync:^{
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&blockError];
      dictionary = historyStore ? [historyStore latestItemForHistoryKey:historyKey error:&blockError] : nil;
    }];
    if (error) {
        *error = blockError;
    }
    return dictionary;
}

#pragma mark - Search Metadata

- (void)availableSearchAppBundleIdentifiersWithCompletion:(MTHistoryAppBundleIdentifiersCompletion)completion {
    [self availableSearchAppBundleIdentifiersForHistoryKey:nil completion:completion];
}

- (void)availableSearchAppBundleIdentifiersForHistoryKey:(NSString *)historyKey
                                              completion:(MTHistoryAppBundleIdentifiersCompletion)completion {
    [self performAsync:^{
      NSError *error = nil;
      MTHistoryStore *historyStore = [self preparedHistoryStoreOnQueueWithError:&error];
      NSArray<NSString *> *bundleIdentifiers =
          historyStore ? [historyStore availableSearchAppBundleIdentifiersForHistoryKey:historyKey error:&error] : @[];
      if (error) {
          HBLogDebug(@"Mt: Failed to load search app tokens: %@", error);
      }
      if (!completion) {
          return;
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(bundleIdentifiers ?: @[], error);
      });
    }];
}

#pragma mark - Queue

- (BOOL)isOnHistoryQueue {
    return dispatch_get_specific(mtHistoryQueueSpecificKey) == mtHistoryQueueSpecificKey;
}

- (void)performAsync:(dispatch_block_t)block {
    if (!block) {
        return;
    }

    if ([self isOnHistoryQueue]) {
        block();
        return;
    }

    dispatch_async(_historyQueue, block);
}

- (void)performSync:(dispatch_block_t)block {
    if (!block) {
        return;
    }

    if ([self isOnHistoryQueue]) {
        block();
        return;
    }

    dispatch_sync(_historyQueue, block);
}

- (void)dispatchCompletion:(void (^)(BOOL success))completion success:(BOOL)success {
    if (!completion) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      completion(success);
    });
}

#pragma mark - Store

- (MTHistoryStore *)historyStoreOnQueue {
    if (!_historyStore) {
        _historyStore =
            [[MTHistoryStore alloc] initWithDatabasePath:_databasePath
                                                  imagesPath:_imagesPath
                                                 lockingMode:MTHistoryStoreLockingModeExclusiveWhileOpen
                                     busyTimeoutMilliseconds:kMTClipboardCoreHistoryStoreBusyTimeoutMilliseconds];
    }
    return _historyStore;
}

- (MTHistoryStore *)preparedHistoryStoreOnQueueWithError:(NSError **)error {
    MTHistoryStore *historyStore = [self historyStoreOnQueue];
    if (![self ensureStorePreparedOnQueueWithError:error]) {
        return nil;
    }
    return historyStore;
}

- (BOOL)ensureStorePreparedOnQueueWithError:(NSError **)error {
    if (_didPrepareHistoryStore) {
        return YES;
    }

    MTHistoryStore *historyStore = [self historyStoreOnQueue];
    NSError *prepareError = nil;
    MTHistoryMigrator *migrator =
        [[MTHistoryMigrator alloc] initWithHistoryStore:historyStore
                                           migrationSources:[MTHistoryMigrator defaultMigrationSources]];
    if (![migrator migrateIfNeededWithError:&prepareError]) {
        _prepareHistoryStoreError = prepareError;
        _didPrepareHistoryStore = NO;
        if (error) {
            *error = prepareError;
        }
        return NO;
    }
    if (![historyStore validateSearchIndexWithError:&prepareError]) {
        _prepareHistoryStoreError = prepareError;
        _didPrepareHistoryStore = NO;
        if (error) {
            *error = prepareError;
        }
        return NO;
    }

    _prepareHistoryStoreError = nil;
    _didPrepareHistoryStore = YES;
    return YES;
}

- (NSUInteger)limitForHistoryKey:(NSString *)historyKey {
    if (_limitProvider) {
        return _limitProvider(historyKey);
    }
    return NSUIntegerMax;
}

@end
