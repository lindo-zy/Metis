//
//  KayokoHistoryChangeNotifier.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KayokoHistoryChangeNotifier : NSObject

- (void)postReloadNotificationWithObject:(nullable id)object;
- (void)postChangeNotificationForHistoryKey:(nullable NSString *)historyKey
                                 changeType:(nullable NSString *)changeType
                             itemDictionary:(nullable NSDictionary<NSString *, id> *)itemDictionary
                                      limit:(NSUInteger)limit
                                     object:(nullable id)object;

@end

NS_ASSUME_NONNULL_END
