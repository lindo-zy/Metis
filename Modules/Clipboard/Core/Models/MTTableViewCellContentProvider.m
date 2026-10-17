//
//  MTTableViewCellContentProvider.m
//  Mt
//

#import "MTTableViewCellContentProvider.h"
#import "MTApplicationMetadataProvider.h"
#import "MTPasteboardItem.h"
#import "MTPasteboardManager.h"
#import "MTTableViewCellContent.h"
#import "MTTag.h"
#import "MTTagCatalog.h"

#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTTableViewCellContentProvider ()
@property(nonatomic, strong) MTApplicationMetadataProvider *metadataProvider;
@property(nonatomic, strong) NSRelativeDateTimeFormatter *relativeDateTimeFormatter;
@property(nonatomic, strong) NSByteCountFormatter *byteCountFormatter;
@property(nonatomic, strong) NSCache<NSString *, NSNumber *> *characterCountCache;
@end

NS_ASSUME_NONNULL_END

@implementation MTTableViewCellContentProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        _metadataProvider = [[MTApplicationMetadataProvider alloc] init];
        _relativeDateTimeFormatter = [[NSRelativeDateTimeFormatter alloc] init];
        [_relativeDateTimeFormatter setDateTimeStyle:NSRelativeDateTimeFormatterStyleNumeric];
        [_relativeDateTimeFormatter setUnitsStyle:NSRelativeDateTimeFormatterUnitsStyleFull];
        NSString *localizationIdentifier =
            [[[MTPasteboardManager localizationBundle] preferredLocalizations] firstObject];
        if ([localizationIdentifier length] > 0) {
            [_relativeDateTimeFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:localizationIdentifier]];
        }
        _byteCountFormatter = [[NSByteCountFormatter alloc] init];
        [_byteCountFormatter setCountStyle:NSByteCountFormatterCountStyleFile];
        _characterCountCache = [[NSCache alloc] init];
        [_characterCountCache setCountLimit:256];
    }
    return self;
}

- (NSString *)relativeTimeTextForDate:(NSDate *)date {
    NSDate *now = [NSDate date];
    NSTimeInterval age = [now timeIntervalSinceDate:date];
    if (age < 60.0) {
        return [[MTPasteboardManager localizationBundle] localizedStringForKey:@"Just Now"
                                                                             value:nil
                                                                             table:@"Tweak"];
    }
    return [[self relativeDateTimeFormatter] localizedStringForDate:date relativeToDate:now];
}

- (NSUInteger)visibleCharacterCountForText:(NSString *)text {
    NSNumber *cachedCount = [[self characterCountCache] objectForKey:text];
    if (cachedCount) {
        return [cachedCount unsignedIntegerValue];
    }

    __block NSUInteger characterCount = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, [text length])
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(__unused NSString *substring, __unused NSRange substringRange,
                                       __unused NSRange enclosingRange, __unused BOOL *stop) {
                            characterCount++;
                          }];
    [[self characterCountCache] setObject:@(characterCount) forKey:text];
    return characterCount;
}

- (UIColor *)searchHighlightBackgroundColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
      if ([traitCollection userInterfaceStyle] == UIUserInterfaceStyleDark) {
          return [[UIColor systemYellowColor] colorWithAlphaComponent:0.42];
      }

      return [UIColor colorWithRed:1.0 green:0.82 blue:0.24 alpha:0.55];
    }];
}

- (nullable NSAttributedString *)attributedTextForText:(NSString *)text searchText:(nullable NSString *)searchText {
    NSString *trimmedSearchText =
        [searchText ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text length] == 0 || [trimmedSearchText length] == 0) {
        return nil;
    }

    NSRange matchRange = [text rangeOfString:trimmedSearchText
                                     options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch];
    if (matchRange.location == NSNotFound || matchRange.length == 0) {
        return nil;
    }

    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:text];
    [attributedText addAttribute:NSBackgroundColorAttributeName
                           value:[self searchHighlightBackgroundColor]
                           range:matchRange];
    return attributedText;
}

- (NSString *)privacyMaskedText:(NSString *)text {
    if (![self privacyMode] || [text length] == 0) {
        return text;
    }

    NSMutableArray<NSValue *> *rangesToMask = [[NSMutableArray alloc] init];
    NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *textBytes = [textData bytes];
    NSUInteger textByteLength = [textData length];
    uint32_t textHash = 2166136261u;
    for (NSUInteger byteIndex = 0; byteIndex < textByteLength; byteIndex++) {
        textHash ^= textBytes[byteIndex];
        textHash *= 16777619u;
    }
    __block NSUInteger composedCharacterIndex = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, [text length])
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *substring, NSRange substringRange, __unused NSRange enclosingRange,
                                       __unused BOOL *stop) {
                            BOOL isWhitespace = [substring rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                                                        .location != NSNotFound;
                            if (!isWhitespace) {
                                uint32_t hash = textHash;
                                hash ^= (uint32_t)composedCharacterIndex;
                                hash *= 16777619u;
                                if ((hash % 5u) == 0u) {
                                    [rangesToMask addObject:[NSValue valueWithRange:substringRange]];
                                }
                            }
                            composedCharacterIndex++;
                          }];

    NSMutableString *maskedText = [text mutableCopy];
    for (NSValue *rangeValue in [rangesToMask reverseObjectEnumerator]) {
        [maskedText replaceCharactersInRange:[rangeValue rangeValue] withString:@"*"];
    }
    return maskedText;
}

- (MTTableViewCellContent *)cellContentForItem:(MTPasteboardItem *)item
                                  previewLineCount:(NSUInteger)previewLineCount
                                   itemDetailsMode:(MTItemDetailsMode)itemDetailsMode {
    return [self cellContentForItem:item
                   previewLineCount:previewLineCount
                    itemDetailsMode:itemDetailsMode
                         searchText:nil];
}

- (MTTableViewCellContent *)cellContentForItem:(MTPasteboardItem *)item
                                  previewLineCount:(NSUInteger)previewLineCount
                                   itemDetailsMode:(MTItemDetailsMode)itemDetailsMode
                                        searchText:(nullable NSString *)searchText {
    MTTableViewCellContent *content = [[MTTableViewCellContent alloc] init];
    NSString *bundleIdentifier = [item bundleIdentifier];
    BOOL isImage = [[item imageName] length] > 0;
    NSString *contentText =
        isImage ? @"" : [([item content] ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *displayContentText = [self privacyMaskedText:contentText];
    NSString *sourceDisplayName = [[self metadataProvider] displayNameForBundleIdentifier:bundleIdentifier];
    NSString *displayName = [[item note] length] > 0 ? [item note] : sourceDisplayName;
    [content setIcon:[[self metadataProvider] iconForBundleIdentifier:bundleIdentifier]];
    [content setDisplayName:displayName];
    [content setAttributedDisplayName:[[item note] length] > 0 ? [self attributedTextForText:displayName
                                                                                  searchText:searchText]
                                                               : nil];
    MTTag *tag = [[MTTagCatalog sharedCatalog] tagForUUID:[item tagUUID]];
    [content setTagHexColor:[tag hexColor]];
    [content setContentText:displayContentText];
    [content setAttributedContentText:[self privacyMode] ? nil
                                                         : [self attributedTextForText:contentText searchText:searchText]];
    BOOL showsDetail =
        isImage ? itemDetailsMode != kMTItemDetailsModeOff : itemDetailsMode == kMTItemDetailsModeAll;
    [content setShowsDetail:showsDetail];
    if (showsDetail) {
        NSMutableArray<NSString *> *detailComponents = [[NSMutableArray alloc] initWithCapacity:3];
        if ([item capturedAt]) {
            [detailComponents addObject:[self relativeTimeTextForDate:[item capturedAt]]];
        }
        if (isImage) {
            if ([item imagePixelWidth] > 0 && [item imagePixelHeight] > 0) {
                [detailComponents
                    addObject:[NSString stringWithFormat:@"%lu×%lu", (unsigned long)[item imagePixelWidth],
                                                         (unsigned long)[item imagePixelHeight]]];
            }
            if ([item imageByteCount] > 0) {
                [detailComponents
                    addObject:[self.byteCountFormatter stringFromByteCount:(long long)[item imageByteCount]]];
            }
        } else {
            NSUInteger characterCount = [self visibleCharacterCountForText:[item content] ?: @""];
            NSString *formatKey = characterCount == 1 ? @"%lu character" : @"%lu characters";
            NSString *format = [[MTPasteboardManager localizationBundle] localizedStringForKey:formatKey
                                                                                             value:nil
                                                                                             table:@"Tweak"];
            [detailComponents addObject:[NSString stringWithFormat:format, (unsigned long)characterCount]];
        }
        NSMutableAttributedString *attributedDetailText = [[NSMutableAttributedString alloc] init];
        for (NSUInteger index = 0; index < [detailComponents count]; index++) {
            if (index > 0) {
                [attributedDetailText
                    appendAttributedString:[[NSAttributedString alloc]
                                               initWithString:@" / "
                                                   attributes:@{
                                                       NSForegroundColorAttributeName : [UIColor tertiaryLabelColor]
                                                   }]];
            }
            [attributedDetailText
                appendAttributedString:[[NSAttributedString alloc]
                                           initWithString:detailComponents[index]
                                               attributes:@{
                                                   NSForegroundColorAttributeName : [UIColor secondaryLabelColor]
                                               }]];
        }
        [content setAttributedDetailText:attributedDetailText];
    }
    [content setThumbnailImageName:[item imageName]];
    [content setPreviewLineCount:previewLineCount];
    return content;
}

- (void)loadThumbnailForItem:(MTPasteboardItem *)item
                  targetSize:(CGSize)targetSize
                  completion:(void (^)(UIImage *_Nullable image))completion {
    [[MTPasteboardManager sharedInstance] getThumbnailForItem:item targetSize:targetSize completion:completion];
}

@end
