//
//  MTPasteboardItem.h
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const kMTContinuityBundleIdentifier;

static NSString *const kMTItemKeyBundleIdentifier = @"bundle_identifier";
static NSString *const kMTItemKeyContent = @"content";
static NSString *const kMTItemKeyImageName = @"image_name";
static NSString *const kMTItemKeyHasLink = @"has_link";
// 旧版「自定义标签」功能的遗留键：标签功能已移除，此键仅用于历史数据库
// 行的兼容读写（不再产生新值，UI 不再消费）。
static NSString *const kMTItemKeyTagUUID = @"tag_uuid";
static NSString *const kMTItemKeyNote = @"note";
static NSString *const kMTItemKeyCapturedAt = @"captured_at";
static NSString *const kMTItemKeyImagePixelWidth = @"image_width";
static NSString *const kMTItemKeyImagePixelHeight = @"image_height";
static NSString *const kMTItemKeyRichTextUTI = @"rich_text_uti";
static NSString *const kMTItemKeyRichTextName = @"rich_text_name";
static NSString *const kMTItemKeyImageByteCount = @"image_byte_count";

@interface MTPasteboardItem : NSObject

@property(nonatomic, copy) NSString *bundleIdentifier;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic, copy) NSString *content;
@property(nonatomic, copy) NSString *imageName;
@property(nonatomic, copy, nullable) NSString *note;
@property(nonatomic, copy) NSDate *capturedAt;
@property(nonatomic, assign) NSUInteger imagePixelWidth;
@property(nonatomic, assign) NSUInteger imagePixelHeight;
@property(nonatomic, copy, nullable) NSString *richTextUTI;
@property(nonatomic, copy) NSString *richTextName;
@property(nonatomic, assign) unsigned long long imageByteCount;
@property(nonatomic, assign) BOOL hasLink;

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                              andContent:(NSString *)content
                          withImageNamed:(nullable NSString *)imageName;

+ (nullable MTPasteboardItem *)itemFromDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
