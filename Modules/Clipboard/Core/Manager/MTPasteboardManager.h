//
//  MTPasteboardManager.h
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import <UIKit/UIKit.h>

@class MTPasteboardItem;
@class MTSearchCriteria;

NS_ASSUME_NONNULL_BEGIN

typedef void (^MTPasteboardItemsCompletion)(NSMutableArray<NSDictionary<NSString *, id> *> *items,
                                                NSError *_Nullable error);
typedef void (^MTPasteboardAppBundleIdentifiersCompletion)(NSArray<NSString *> *bundleIdentifiers,
                                                               NSError *_Nullable error);

static NSString *const kMTHistoryKeyHistory = @"history";
static NSString *const kMTHistoryKeyFavorites = @"favorites";
static NSString *const kMTPasteboardManagerHistoryDidChangeNotification = @"com.lindo.metis.clipboard.history.did-change";
static NSString *const kMTPasteboardManagerHistoryChangeTypeKey = @"change_type";
static NSString *const kMTPasteboardManagerHistoryChangeHistoryKeyKey = @"history_key";
static NSString *const kMTPasteboardManagerHistoryChangeItemKey = @"item";
static NSString *const kMTPasteboardManagerHistoryChangeLimitKey = @"limit";
static NSString *const kMTPasteboardManagerHistoryChangeTypeReload = @"reload";
static NSString *const kMTPasteboardManagerHistoryChangeTypeUpsertTop = @"upsert_top";
static NSString *const kMTPasteboardManagerHistoryChangeTypeRemove = @"remove";
static NSString *const kMTPasteboardManagerHistoryChangeTypeClear = @"clear";

@interface MTPasteboardManager : NSObject

@property(nonatomic, assign) NSUInteger maximumHistoryAmount;
@property(nonatomic, assign) BOOL saveText;
@property(nonatomic, assign) BOOL saveImages;
@property(nonatomic, assign) BOOL automaticallyPaste;
@property(nonatomic, assign) NSUInteger automaticPasteMode;
@property(nonatomic, assign) NSUInteger automaticPromotionMode;
@property(nonatomic, assign) BOOL ignoreRemoteReplication;
@property(nonatomic, copy) NSSet<NSString *> *applicationBlacklist;

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;
- (void)warmUpHistoryAccess;
- (void)enterMaintenanceModeUntilProcessExit;
- (void)resetThumbnailMemoryCache;

+ (NSString *)historyPath;
+ (NSString *)historyDatabasePath;
+ (NSString *)historyImagesPath;
+ (NSString *)historyRichTextPath;
+ (NSBundle *)localizationBundle;
+ (NSUInteger)normalizedMaximumHistoryAmountForValue:(NSUInteger)value;

- (void)checkpointHistoryDatabase;
- (void)pullPasteboardChanges;
- (void)pullPasteboardChangesWithCompletion:(nullable void (^)(BOOL didSaveAnyItem))completion;
- (BOOL)addPasteboardItem:(MTPasteboardItem *)item toHistoryWithKey:(NSString *)historyKey;
- (void)writePasteboardItem:(MTPasteboardItem *)pasteboardItem
          sourceHistoryItem:(MTPasteboardItem *)sourceHistoryItem
         fromHistoryWithKey:(NSString *)historyKey
       allowsAutomaticPaste:(BOOL)allowsAutomaticPaste;
// 复制历史条目到系统剪贴板。写剪贴板是到 pasted 的同步 IPC：禁止在主线程
// dispatch_sync 等待（pasted 忙/卡时会把 SB 主线程一起挂死），一律在
// 剪贴板串行队列异步执行，结果经 completion 回主线程。
- (void)copyPasteboardItemToPasteboard:(MTPasteboardItem *)item
                             completion:(nullable void (^)(BOOL didUpdatePasteboard))completion;
- (void)removePasteboardItem:(MTPasteboardItem *)item
          fromHistoryWithKey:(NSString *)historyKey
           shouldRemoveImage:(BOOL)shouldRemoveImage;
- (void)removePasteboardItem:(MTPasteboardItem *)item
          fromHistoryWithKey:(NSString *)historyKey
           shouldRemoveImage:(BOOL)shouldRemoveImage
                  completion:(nullable void (^)(BOOL success))completion;
- (void)movePasteboardItem:(MTPasteboardItem *)item
        fromHistoryWithKey:(NSString *)sourceHistoryKey
          toHistoryWithKey:(NSString *)destinationHistoryKey
                completion:(nullable void (^)(BOOL success))completion;
- (void)setNote:(nullable NSString *)note
         tagUUID:(nullable NSString *)tagUUID
forPasteboardItem:(MTPasteboardItem *)item
 inHistoryWithKey:(NSString *)historyKey
       completion:(nullable void (^)(BOOL success))completion;
- (void)replaceContent:(NSString *)content
     forPasteboardItem:(MTPasteboardItem *)item
      inHistoryWithKey:(NSString *)historyKey
            completion:(nullable void (^)(BOOL success))completion;
- (void)removeAllPasteboardItemsFromHistoryWithKey:(NSString *)historyKey
                                shouldRemoveImages:(BOOL)shouldRemoveImages
                                        completion:(nullable void (^)(BOOL success))completion;
- (void)removeAllPasteboardItemsFromHistoryWithKey:(NSString *)historyKey
                                shouldRemoveImages:(BOOL)shouldRemoveImages
                           postsChangeNotification:(BOOL)postsChangeNotification
                                        completion:(nullable void (^)(BOOL success))completion;
- (void)removeImagePasteboardItemsFromHistoryWithKey:(NSString *)historyKey
                             postsChangeNotification:(BOOL)postsChangeNotification
                                          completion:(nullable void (^)(BOOL success))completion;

- (NSMutableArray<NSDictionary<NSString *, id> *> *)getItemsFromHistoryWithKey:(NSString *)historyKey;
- (void)getItemsFromHistoryWithKey:(NSString *)historyKey
                        completion:(nullable MTPasteboardItemsCompletion)completion;
- (void)getItemsFromHistoryWithKey:(NSString *)historyKey
                    searchCriteria:(nullable MTSearchCriteria *)searchCriteria
                        completion:(nullable MTPasteboardItemsCompletion)completion;
- (void)availableSearchAppBundleIdentifiersWithCompletion:
    (nullable MTPasteboardAppBundleIdentifiersCompletion)completion;
- (void)availableSearchAppBundleIdentifiersForHistoryKey:(nullable NSString *)historyKey
                                              completion:(nullable MTPasteboardAppBundleIdentifiersCompletion)completion;
- (nullable MTPasteboardItem *)getLatestHistoryItem;
- (nullable UIImage *)getImageForItem:(MTPasteboardItem *)item;
- (void)getThumbnailForItem:(MTPasteboardItem *)item
                 targetSize:(CGSize)targetSize
                 completion:(void (^)(UIImage *_Nullable image))completion;

@end

NS_ASSUME_NONNULL_END
