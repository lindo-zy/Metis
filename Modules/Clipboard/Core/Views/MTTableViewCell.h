//
//  MTTableViewCell.h
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import <UIKit/UIKit.h>

@class MTTableViewCellContent;

NS_ASSUME_NONNULL_BEGIN

@interface MTTableViewCell : UITableViewCell

@property(nonatomic, strong) UIImageView *iconImageView;
@property(nonatomic, strong) UILabel *headerLabel;
@property(nonatomic, strong, nullable) UILabel *contentLabel;
@property(nonatomic, strong, nullable) UILabel *detailLabel;
@property(nonatomic, strong, nullable) UIImageView *contentImageView;

- (instancetype)initWithStyle:(UITableViewCellStyle)style
                      content:(MTTableViewCellContent *)content
              reuseIdentifier:(NSString *)reuseIdentifier;
- (instancetype)initWithGalleryContent:(MTTableViewCellContent *)content
                         reuseIdentifier:(NSString *)reuseIdentifier;
+ (NSString *)reuseIdentifierForContent:(MTTableViewCellContent *)content;
+ (NSString *)galleryReuseIdentifierForContent:(MTTableViewCellContent *)content;
+ (CGSize)contentImageViewSizeForPreviewLineCount:(NSUInteger)previewLineCount;
+ (CGSize)contentImageThumbnailSize;
+ (CGSize)galleryContentImageThumbnailSize;
- (void)applyDetailContent:(MTTableViewCellContent *)content;
- (void)applyContent:(MTTableViewCellContent *)content;
- (void)setContentImage:(nullable UIImage *)image forImageName:(NSString *)imageName;

@end

NS_ASSUME_NONNULL_END
