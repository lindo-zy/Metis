//
//  MTTableViewCellContentProvider.h
//  Mt
//

#import <UIKit/UIKit.h>

#import "MTPreferenceKeys.h"

@class MTTableViewCellContent;
@class MTPasteboardItem;

NS_ASSUME_NONNULL_BEGIN

@interface MTTableViewCellContentProvider : NSObject

@property(nonatomic, assign) BOOL privacyMode;

- (MTTableViewCellContent *)cellContentForItem:(MTPasteboardItem *)item
                                  previewLineCount:(NSUInteger)previewLineCount
                                   itemDetailsMode:(MTItemDetailsMode)itemDetailsMode;
- (MTTableViewCellContent *)cellContentForItem:(MTPasteboardItem *)item
                                  previewLineCount:(NSUInteger)previewLineCount
                                   itemDetailsMode:(MTItemDetailsMode)itemDetailsMode
                                        searchText:(nullable NSString *)searchText;

- (void)loadThumbnailForItem:(MTPasteboardItem *)item
                  targetSize:(CGSize)targetSize
                  completion:(void (^)(UIImage *_Nullable image))completion;

@end

NS_ASSUME_NONNULL_END
