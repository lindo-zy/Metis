//
//  MTHistoryChangeNotifier.m
//  Mt
//

#import "MTHistoryChangeNotifier.h"
#import "MTNotificationKeys.h"
#import "MTPasteboardManager.h"

@implementation MTHistoryChangeNotifier

- (void)postReloadNotificationWithObject:(id)object {
    [self postChangeNotificationForHistoryKey:nil
                                   changeType:kMTPasteboardManagerHistoryChangeTypeReload
                               itemDictionary:nil
                                        limit:0
                                       object:object];
}

- (void)postChangeNotificationForHistoryKey:(NSString *)historyKey
                                 changeType:(NSString *)changeType
                             itemDictionary:(NSDictionary<NSString *, id> *)itemDictionary
                                      limit:(NSUInteger)limit
                                     object:(id)object {
    NSDictionary<NSString *, id> *userInfo = [self userInfoWithChangeType:changeType
                                                               historyKey:historyKey
                                                           itemDictionary:itemDictionary
                                                                    limit:limit];
    dispatch_async(dispatch_get_main_queue(), ^{
      [[NSNotificationCenter defaultCenter] postNotificationName:kMTPasteboardManagerHistoryDidChangeNotification
                                                          object:object
                                                        userInfo:userInfo];
    });
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kMTNotificationKeyCoreReload, nil, nil, YES);
}

- (NSDictionary<NSString *, id> *)userInfoWithChangeType:(NSString *)changeType
                                              historyKey:(NSString *)historyKey
                                          itemDictionary:(NSDictionary<NSString *, id> *)itemDictionary
                                                   limit:(NSUInteger)limit {
    NSMutableDictionary<NSString *, id> *userInfo = [[NSMutableDictionary alloc] init];
    userInfo[kMTPasteboardManagerHistoryChangeTypeKey] =
        changeType ?: kMTPasteboardManagerHistoryChangeTypeReload;
    if ([historyKey length] > 0) {
        userInfo[kMTPasteboardManagerHistoryChangeHistoryKeyKey] = historyKey;
        userInfo[kMTPasteboardManagerHistoryChangeLimitKey] = @(limit);
    }
    if (itemDictionary) {
        userInfo[kMTPasteboardManagerHistoryChangeItemKey] = itemDictionary;
    }
    return userInfo;
}

@end
