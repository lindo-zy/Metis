//
//  MTHistoryItemActionHandler.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTPasteboardItem;

NS_ASSUME_NONNULL_BEGIN

@interface MTHistoryItemActionHandler : NSObject

- (void)activateItem:(MTPasteboardItem *)item
          historyKey:(NSString *)historyKey
          completion:(nullable void (^)(BOOL success))completion;
- (void)copyItem:(MTPasteboardItem *)item completion:(nullable void (^)(BOOL success))completion;
- (void)saveImageForItem:(MTPasteboardItem *)item completion:(nullable void (^)(BOOL success))completion;
- (void)openLinkForItem:(MTPasteboardItem *)item completion:(nullable void (^)(BOOL success))completion;
- (void)deleteItem:(MTPasteboardItem *)item
        historyKey:(NSString *)historyKey
        completion:(nullable void (^)(BOOL success))completion;
- (void)moveItem:(MTPasteboardItem *)item
         sourceHistoryKey:(NSString *)sourceHistoryKey
    destinationHistoryKey:(NSString *)destinationHistoryKey
               completion:(nullable void (^)(BOOL success))completion;

@end

NS_ASSUME_NONNULL_END
