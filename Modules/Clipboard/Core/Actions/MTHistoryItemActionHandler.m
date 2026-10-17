//
//  MTHistoryItemActionHandler.m
//  Mt
//

#import "MTHistoryItemActionHandler.h"

#import "MTPasteboardItem.h"
#import "MTPasteboardManager.h"

@implementation MTHistoryItemActionHandler

- (void)activateItem:(MTPasteboardItem *)item
          historyKey:(NSString *)historyKey
          completion:(void (^)(BOOL success))completion {
    if (!item || [historyKey length] == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    [[MTPasteboardManager sharedInstance] writePasteboardItem:item
                                                sourceHistoryItem:item
                                               fromHistoryWithKey:historyKey
                                             allowsAutomaticPaste:YES];
    if (completion) {
        completion(YES);
    }
}

- (void)copyItem:(MTPasteboardItem *)item completion:(void (^)(BOOL success))completion {
    if (!item) {
        if (completion) {
            completion(NO);
        }
        return;
    }
    [[MTPasteboardManager sharedInstance] copyPasteboardItemToPasteboard:item completion:completion];
}

- (void)saveImageForItem:(MTPasteboardItem *)item completion:(void (^)(BOOL success))completion {
    UIImage *image = item ? [[MTPasteboardManager sharedInstance] getImageForItem:item] : nil;
    if (image) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
    }
    if (completion) {
        completion(image != nil);
    }
}

- (void)openLinkForItem:(MTPasteboardItem *)item completion:(void (^)(BOOL success))completion {
    NSURL *URL = [NSURL URLWithString:[item content] ?: @""];
    if (!URL) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    [[UIApplication sharedApplication] openURL:URL
                                       options:@{}
                             completionHandler:^(BOOL success) {
                               if (completion) {
                                   completion(success);
                               }
                             }];
}

- (void)deleteItem:(MTPasteboardItem *)item
        historyKey:(NSString *)historyKey
        completion:(void (^)(BOOL success))completion {
    if (!item || [historyKey length] == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    [[MTPasteboardManager sharedInstance] removePasteboardItem:item
                                                fromHistoryWithKey:historyKey
                                                 shouldRemoveImage:YES
                                                        completion:completion];
}

- (void)moveItem:(MTPasteboardItem *)item
         sourceHistoryKey:(NSString *)sourceHistoryKey
    destinationHistoryKey:(NSString *)destinationHistoryKey
               completion:(void (^)(BOOL success))completion {
    if (!item || [sourceHistoryKey length] == 0 || [destinationHistoryKey length] == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    [[MTPasteboardManager sharedInstance] movePasteboardItem:item
                                              fromHistoryWithKey:sourceHistoryKey
                                                toHistoryWithKey:destinationHistoryKey
                                                      completion:completion];
}

@end
