//
//  MTPasteboardManager.m
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import "MTPasteboardManager.h"
#import "MTHistoryChangeNotifier.h"
#import "MTHistoryRepository.h"
#import "MTKeyboardHostResolver.h"
#import "MTKeyboardShortcutSender.h"
#import "MTNotificationKeys.h"
#import "MTPasteboardItem.h"
#import "MTPreferenceKeys.h"
#import "MTRichTextRepresentation.h"
#import "MTSearchCriteria.h"
#import "MTThumbnailCache.h"

#import <HBLog.h>
#import <ImageIO/ImageIO.h>
#import <math.h>
#import <roothide.h>

static NSTimeInterval const kMTPasteboardWriteConfirmationTimeout = 0.25;
static NSTimeInterval const kMTSimulatedAutomaticPasteDelay = 0.2;
static NSString *const kMTRemoteClipboardPasteboardType = @"com.apple.is-remote-clipboard";
static NSString *const kMTPasteboardManagerErrorDomain = @"com.lindo.kayoko.pasteboard-manager";

@interface SBApplication : NSObject
@property(nonatomic, copy, readonly) NSString *bundleIdentifier;
@end

@interface UIApplication (Private)
- (SBApplication *_Nullable)_accessibilityFrontMostApplication;
@end

NS_ASSUME_NONNULL_BEGIN

@interface MTPasteboardPendingWrite : NSObject

#pragma mark - State

@property(nonatomic, assign, readonly, getter=isActive) BOOL active;
@property(nonatomic, assign, readonly) BOOL shouldAutoPaste;
@property(nonatomic, assign, readonly) MTAutomaticPasteMode automaticPasteMode;
@property(nonatomic, assign, readonly) NSUInteger token;
@property(nonatomic, assign, readonly) NSUInteger previousChangeCount;

#pragma mark - Expiration

@property(nonatomic, copy, nullable) dispatch_block_t expirationBlock;

#pragma mark - Lifecycle

- (NSUInteger)beginAfterChangeCount:(NSUInteger)previousChangeCount
                    shouldAutoPaste:(BOOL)shouldAutoPaste
                 automaticPasteMode:(MTAutomaticPasteMode)automaticPasteMode;

#pragma mark - Expiration

- (void)scheduleExpirationOnQueue:(dispatch_queue_t)queue
                       afterDelay:(NSTimeInterval)delay
                          handler:(dispatch_block_t)handler;

#pragma mark - Matching

- (BOOL)matchesToken:(NSUInteger)token;
- (BOOL)hasAdvancedToChangeCount:(NSUInteger)changeCount;

#pragma mark - Cancellation

- (void)cancelExpirationBlock;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END

@implementation MTPasteboardPendingWrite

- (NSUInteger)beginAfterChangeCount:(NSUInteger)previousChangeCount
                    shouldAutoPaste:(BOOL)shouldAutoPaste
                 automaticPasteMode:(MTAutomaticPasteMode)automaticPasteMode {
    [self cancelExpirationBlock];
    _token++;
    _active = YES;
    _shouldAutoPaste = shouldAutoPaste;
    _automaticPasteMode = automaticPasteMode;
    _previousChangeCount = previousChangeCount;
    return _token;
}

- (void)scheduleExpirationOnQueue:(dispatch_queue_t)queue
                       afterDelay:(NSTimeInterval)delay
                          handler:(dispatch_block_t)handler {
    [self cancelExpirationBlock];
    dispatch_block_t expirationBlock = dispatch_block_create(0, handler);
    self.expirationBlock = expirationBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), queue, expirationBlock);
}

- (BOOL)matchesToken:(NSUInteger)token {
    return _active && token == _token;
}

- (BOOL)hasAdvancedToChangeCount:(NSUInteger)changeCount {
    return _active && changeCount != _previousChangeCount;
}

- (void)cancel {
    [self cancelExpirationBlock];
    _token++;
    _active = NO;
    _shouldAutoPaste = NO;
    _automaticPasteMode = kMTAutomaticPasteModeClassic;
    _previousChangeCount = 0;
}

- (void)cancelExpirationBlock {
    dispatch_block_t expirationBlock = self.expirationBlock;
    if (expirationBlock) {
        dispatch_block_cancel(expirationBlock);
        self.expirationBlock = nil;
    }
}

@end

@implementation MTPasteboardManager {
    UIPasteboard *_pasteboard;
    NSUInteger _lastChangeCount;
    NSFileManager *_fileManager;

    dispatch_queue_t _pasteboardQueue;
    MTThumbnailCache *_thumbnailCache;

    BOOL _isWritingPasteboardItem;
    MTPasteboardPendingWrite *_pendingPasteboardWrite;

    MTHistoryRepository *_historyRepository;
    MTHistoryChangeNotifier *_historyChangeNotifier;
    BOOL _maintenanceMode;
}

#pragma mark - Lifecycle

+ (instancetype)sharedInstance {
    static MTPasteboardManager *sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedInstance = [[MTPasteboardManager alloc] init];
    });
    return sharedInstance;
}

#pragma mark - Paths and Resources

+ (NSString *)historyPath {
    static NSString *mtHistoryPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      mtHistoryPath = jbroot(@"/var/mobile/Library/com.lindo.kayoko/history.json");
    });
    return mtHistoryPath;
}

+ (NSString *)historyImagesPath {
    static NSString *mtHistoryImagesPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      mtHistoryImagesPath = jbroot(@"/var/mobile/Library/com.lindo.kayoko/images/");
    });
    return mtHistoryImagesPath;
}

+ (NSString *)historyRichTextPath {
    static NSString *mtHistoryRichTextPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      mtHistoryRichTextPath =
          [[[self historyDatabasePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"rich-text"];
    });
    return mtHistoryRichTextPath;
}

+ (NSBundle *)localizationBundle {
    static NSBundle *mtLocalizationBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      mtLocalizationBundle =
          [NSBundle bundleWithPath:jbroot(@"/Library/PreferenceBundles/MetisClipboardPrefs.bundle")];
    });
    return mtLocalizationBundle;
}

+ (NSString *)historyDatabasePath {
    return [MTHistoryRepository defaultDatabasePath];
}

+ (NSUInteger)normalizedMaximumHistoryAmountForValue:(NSUInteger)value {
    if (value == 0) {
        return kMTPreferenceKeyMaximumHistoryAmountDefaultValue;
    }

    NSArray<NSNumber *> *stepValues = @[ @50, @100, @200, @300, @500, @1000, @2000, @3000, @4000, @5000 ];
    for (NSNumber *stepValue in stepValues) {
        NSUInteger candidate = [stepValue unsignedIntegerValue];
        if (value <= candidate) {
            return candidate;
        }
    }

    return [[stepValues lastObject] unsignedIntegerValue];
}

#pragma mark - Setup

- (instancetype)init {
    self = [super init];
    if (self) {
        _fileManager = [NSFileManager defaultManager];
        if (@available(iOS 16, *)) {
            _pasteboardQueue = dispatch_queue_create("com.lindo.kayoko.queue.pasteboard",
                                                     DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        }
        _thumbnailCache = [[MTThumbnailCache alloc] init];
        _automaticPromotionMode = kMTPreferenceKeyAutomaticPromotionModeDefaultValue;
        _applicationBlacklist = [NSSet set];
        _pendingPasteboardWrite = [[MTPasteboardPendingWrite alloc] init];
        __weak typeof(self) weakSelf = self;
        _historyRepository =
            [[MTHistoryRepository alloc] initWithDatabasePath:[MTPasteboardManager historyDatabasePath]
                                                       imagesPath:[MTPasteboardManager historyImagesPath]
                                                    limitProvider:^NSUInteger(NSString *historyKey) {
                                                      return [weakSelf limitForHistoryKey:historyKey];
                                                    }];
        _historyChangeNotifier = [[MTHistoryChangeNotifier alloc] init];
        if (@available(iOS 15, *)) {
            [self prepareGeneralPasteboard];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
              [self prepareGeneralPasteboard];
            });
        }
    }
    return self;
}

- (void)prepareGeneralPasteboard {
    _pasteboard = [UIPasteboard generalPasteboard];
    _lastChangeCount = [_pasteboard changeCount];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(generalPasteboardDidChange:)
                                                 name:UIPasteboardChangedNotification
                                               object:_pasteboard];
}

- (void)warmUpHistoryAccess {
    if (_maintenanceMode) {
        return;
    }
    [_historyRepository prepareStore];
}

- (void)enterMaintenanceModeUntilProcessExit {
    _maintenanceMode = YES;
    [_historyRepository closeStore];
}

- (void)checkpointHistoryDatabase {
    if (_maintenanceMode) {
        return;
    }
    [_historyRepository checkpointWriteAheadLog];
}

- (void)resetThumbnailMemoryCache {
    [_thumbnailCache removeAllMemoryCachedThumbnails];
}

#pragma mark - Image Storage Helpers

- (NSString *)randomStringWithLength:(NSUInteger)length {
    NSString *characters = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSMutableString *string = [NSMutableString stringWithCapacity:length];

    for (NSUInteger i = 0; i < length; i++) {
        [string appendFormat:@"%c", [characters characterAtIndex:arc4random_uniform((uint32_t)[characters length])]];
    }

    return string;
}

- (BOOL)imageHasAlpha:(UIImage *)image {
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo([image CGImage]);
    return (alpha == kCGImageAlphaFirst || alpha == kCGImageAlphaLast || alpha == kCGImageAlphaPremultipliedFirst ||
            alpha == kCGImageAlphaPremultipliedLast);
}

- (UIImage *)imageByApplyingOrientation:(UIImage *)image {
    if ([image imageOrientation] == UIImageOrientationUp) {
        return image;
    }

    UIGraphicsBeginImageContext([image size]);
    [image drawInRect:CGRectMake(0, 0, [image size].width, [image size].height)];
    UIImage *rotatedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return rotatedImage;
}

- (CGSize)pixelSizeForEncodedImageData:(NSData *)imageData {
    if ([imageData length] == 0) {
        return CGSizeZero;
    }

    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    if (!imageSource) {
        return CGSizeZero;
    }
    NSDictionary<NSString *, id> *properties =
        CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL));
    CFRelease(imageSource);

    CGFloat width = [properties[(NSString *)kCGImagePropertyPixelWidth] doubleValue];
    CGFloat height = [properties[(NSString *)kCGImagePropertyPixelHeight] doubleValue];
    if (!isfinite(width) || !isfinite(height) || width <= 0 || height <= 0) {
        return CGSizeZero;
    }
    NSUInteger orientation = [properties[(NSString *)kCGImagePropertyOrientation] unsignedIntegerValue];
    return orientation >= 5 && orientation <= 8 ? CGSizeMake(height, width) : CGSizeMake(width, height);
}

#pragma mark - Pasteboard Representation Helpers

- (UIImage *)imageFromPasteboardItemDictionary:(NSDictionary<NSString *, id> *)dictionary {
    for (id value in [dictionary allValues]) {
        if ([value isKindOfClass:[UIImage class]]) {
            return value;
        }
    }

    NSArray<NSString *> *imageTypeIdentifiers = @[
        @"public.png",
        @"public.jpeg",
        @"public.jpeg-2000",
        @"public.tiff",
        @"public.image",
        @"com.apple.uikit.image",
    ];
    for (NSString *typeIdentifier in imageTypeIdentifiers) {
        id value = dictionary[typeIdentifier];
        if (![value isKindOfClass:[NSData class]]) {
            continue;
        }
        UIImage *image = [UIImage imageWithData:value];
        if (image) {
            return image;
        }
    }

    for (NSString *typeIdentifier in dictionary) {
        if ([imageTypeIdentifiers containsObject:typeIdentifier]) {
            continue;
        }
        id value = dictionary[typeIdentifier];
        if (![value isKindOfClass:[NSData class]]) {
            continue;
        }
        UIImage *image = [UIImage imageWithData:value];
        if (image) {
            return image;
        }
    }
    return nil;
}

- (NSString *)plainTextFromPasteboardItemDictionary:(NSDictionary<NSString *, id> *)dictionary {
    NSArray<NSString *> *textTypeIdentifiers = @[
        @"public.utf8-plain-text",
        @"public.plain-text",
        @"public.text",
        @"public.url",
        @"public.file-url",
    ];
    for (NSString *typeIdentifier in textTypeIdentifiers) {
        id value = dictionary[typeIdentifier];
        NSString *text = nil;
        if ([value isKindOfClass:[NSString class]]) {
            text = value;
        } else if ([value isKindOfClass:[NSURL class]]) {
            text = [value absoluteString];
        } else if ([value isKindOfClass:[NSAttributedString class]]) {
            text = [value string];
        } else if ([value isKindOfClass:[NSData class]]) {
            text = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
        }
        if ([text length] > 0) {
            return text;
        }
    }
    return nil;
}

- (BOOL)storeRichTextRepresentation:(MTRichTextRepresentation *)representation {
    NSString *directoryPath = [MTPasteboardManager historyRichTextPath];
    NSError *directoryError = nil;
    if (![_fileManager createDirectoryAtPath:directoryPath
                 withIntermediateDirectories:YES
                                  attributes:nil
                                       error:&directoryError] &&
        ![_fileManager fileExistsAtPath:directoryPath]) {
        HBLogDebug(@"Mt: Failed to create rich text directory: %@", directoryError);
        return NO;
    }

    NSString *filePath = [directoryPath stringByAppendingPathComponent:[representation stableFileName]];
    if ([_fileManager fileExistsAtPath:filePath]) {
        NSData *existingData = [_fileManager contentsAtPath:filePath];
        if ([existingData isEqualToData:[representation data]]) {
            return YES;
        }
        HBLogDebug(@"Mt: Rich text file conflicts with existing content: %@", filePath);
        return NO;
    }

    NSError *writeError = nil;
    if (![[representation data] writeToFile:filePath options:NSDataWritingAtomic error:&writeError]) {
        HBLogDebug(@"Mt: Failed to save rich text representation: %@", writeError);
        return NO;
    }
    return YES;
}

#pragma mark - Pasteboard Observation

- (void)pullPasteboardChanges {
    [self pullPasteboardChangesWithCompletion:nil];
}

- (void)pullPasteboardChangesWithCompletion:(void (^)(BOOL didSaveAnyItem))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    void (^complete)(BOOL) = ^(BOOL didSaveAnyItem) {
      if (!completion) {
          return;
      }

      dispatch_async(dispatch_get_main_queue(), ^{
        completion(didSaveAnyItem);
      });
    };

    NSString *sourceBundleIdentifier = [self sourceApplicationBundleIdentifierForCurrentPasteboardChangeOnMain];

    if (@available(iOS 16, *)) {
        dispatch_async(_pasteboardQueue, ^{
          complete([self _reallyPullPasteboardChangesWithSourceBundleIdentifier:sourceBundleIdentifier]);
        });
        return;
    }

    NSArray<MTPasteboardItem *> *items =
        [self pasteboardItemsForCurrentChangeWithSourceBundleIdentifier:sourceBundleIdentifier];
    [self savePasteboardItems:items
             toHistoryWithKey:kMTHistoryKeyHistory
                   completion:^(BOOL didSaveAnyItem) {
                     complete(didSaveAnyItem);
                   }];
}

- (BOOL)pasteboardContainsType:(NSString *)pasteboardType {
    return [_pasteboard containsPasteboardTypes:@[ pasteboardType ]];
}

- (void)generalPasteboardDidChange:(NSNotification *)notification {
    (void)notification;
    if ([_pendingPasteboardWrite isActive]) {
        HBLogDebug(@"Mt: pending pasteboard write observed changed notification token=%lu changeCount=%lu",
                   (unsigned long)[_pendingPasteboardWrite token], (unsigned long)[_pasteboard changeCount]);
    }
    if (@available(iOS 16, *)) {
        dispatch_async(_pasteboardQueue, ^{
          [self resolvePendingPasteboardWriteForToken:[_pendingPasteboardWrite token] didExpire:NO];
        });
        return;
    }

    [self resolvePendingPasteboardWriteForToken:[_pendingPasteboardWrite token] didExpire:NO];
}

- (BOOL)shouldIgnoreCurrentPasteboardChangeFromSourceBundleIdentifier:(NSString *)sourceBundleIdentifier {
    if ([self ignoreRemoteReplication] && [self pasteboardContainsType:kMTRemoteClipboardPasteboardType]) {
        return YES;
    }

    if ([[self applicationBlacklist] containsObject:sourceBundleIdentifier]) {
        HBLogDebug(@"Mt: ignored pasteboard change from blacklisted source app bundleIdentifier=%@",
                   sourceBundleIdentifier);
        return YES;
    }

    return [self pasteboardContainsType:@"com.apple.icns"];
}

- (NSString *)sourceApplicationBundleIdentifierForCurrentPasteboardChangeOnMain {
    if ([self pasteboardContainsType:kMTRemoteClipboardPasteboardType]) {
        HBLogDebug(@"Mt: pasteboard source app using Continuity for remote clipboard change "
                   @"pasteboardType=%@ finalBundleIdentifier=%@",
                   kMTRemoteClipboardPasteboardType, kMTContinuityBundleIdentifier);
        return kMTContinuityBundleIdentifier;
    }

    MTKeyboardHostContext *hostContext =
        [[MTKeyboardHostResolver sharedResolver] keyboardHostContextForSourceAttribution];
    if ([[hostContext bundleIdentifier] length] > 0) {
        HBLogDebug(@"Mt: pasteboard source app using %@ keyboard host bundleIdentifier=%@ scene=%@ "
                   @"kind=%@ cached=%@ mtOwned=%@",
                   hostContext.isCached ? @"cached external" : @"current", [hostContext bundleIdentifier],
                   [hostContext identifier], [MTKeyboardHostResolver stringForHostKind:[hostContext kind]],
                   hostContext.isCached ? @"YES" : @"NO", hostContext.isMtOwned ? @"YES" : @"NO");
        return [hostContext bundleIdentifier];
    }

    SBApplication *frontMostApplication = [[UIApplication sharedApplication] _accessibilityFrontMostApplication];
    NSString *frontMostBundleIdentifier = [frontMostApplication bundleIdentifier];
    NSString *fallbackBundleIdentifier =
        [frontMostBundleIdentifier length] > 0 ? frontMostBundleIdentifier : @"com.apple.springboard";
    HBLogDebug(@"Mt: pasteboard source app falling back to frontmost application "
               @"hostScene=%@ hostKind=%@ hostCached=%@ hostBundleIdentifier=%@ frontMostBundleIdentifier=%@ "
               @"finalBundleIdentifier=%@",
               [hostContext identifier] ?: @"nil", [MTKeyboardHostResolver stringForHostKind:[hostContext kind]],
               hostContext.isCached ? @"YES" : @"NO", [hostContext bundleIdentifier] ?: @"nil",
               frontMostBundleIdentifier ?: @"nil", fallbackBundleIdentifier);
    return fallbackBundleIdentifier;
}

- (NSArray<MTPasteboardItem *> *)pasteboardItemsForCurrentChangeWithSourceBundleIdentifier:
    (NSString *)sourceBundleIdentifier {
    NSUInteger currentChangeCount = [_pasteboard changeCount];
    if (currentChangeCount == _lastChangeCount) {
        return @[];
    }

    _lastChangeCount = currentChangeCount;

    if ([self shouldIgnoreCurrentPasteboardChangeFromSourceBundleIdentifier:sourceBundleIdentifier]) {
        return @[];
    }

    NSMutableArray<MTPasteboardItem *> *items = [[NSMutableArray alloc] init];
    for (id pasteboardValue in [_pasteboard items]) {
        @autoreleasepool {
            if (![pasteboardValue isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary<NSString *, id> *pasteboardItem = pasteboardValue;
            UIImage *image = [self imageFromPasteboardItemDictionary:pasteboardItem];
            if (image) {
                if (![self saveImages]) {
                    continue;
                }

                NSString *imageName = [self randomStringWithLength:32];
                NSData *imageData = nil;
                if ([self imageHasAlpha:image]) {
                    imageName = [imageName stringByAppendingString:@".png"];
                    imageData = UIImagePNGRepresentation([self imageByApplyingOrientation:image]);
                } else {
                    imageName = [imageName stringByAppendingString:@".jpg"];
                    imageData = UIImageJPEGRepresentation(image, 1);
                }
                if ([imageData length] == 0) {
                    continue;
                }

                NSString *filePath =
                    [[MTPasteboardManager historyImagesPath] stringByAppendingPathComponent:imageName];
                NSError *writeError = nil;
                if (![imageData writeToFile:filePath options:NSDataWritingAtomic error:&writeError]) {
                    HBLogDebug(@"Mt: Failed to save captured pasteboard image: %@", writeError);
                    continue;
                }

                MTPasteboardItem *item =
                    [[MTPasteboardItem alloc] initWithBundleIdentifier:sourceBundleIdentifier
                                                                andContent:imageName
                                                            withImageNamed:imageName];
                CGSize pixelSize = [self pixelSizeForEncodedImageData:imageData];
                [item setImagePixelWidth:(NSUInteger)llround(pixelSize.width)];
                [item setImagePixelHeight:(NSUInteger)llround(pixelSize.height)];
                [item setImageByteCount:(unsigned long long)[imageData length]];
                [items addObject:item];
                continue;
            }

            if (![self saveText]) {
                continue;
            }

            NSString *plainText = [self plainTextFromPasteboardItemDictionary:pasteboardItem];
            MTRichTextRepresentation *richTextRepresentation =
                [MTRichTextRepresentation preferredRepresentationFromDictionary:pasteboardItem];
            if ([plainText length] == 0) {
                plainText = [richTextRepresentation plainText];
            }
            if ([plainText length] == 0) {
                continue;
            }

            MTPasteboardItem *item = [[MTPasteboardItem alloc] initWithBundleIdentifier:sourceBundleIdentifier
                                                                                     andContent:plainText
                                                                                 withImageNamed:nil];
            if (richTextRepresentation) {
                NSError *prepareError = nil;
                if (![_historyRepository ensureStorePreparedWithError:&prepareError]) {
                    HBLogDebug(@"Mt: Failed to prepare history store before saving rich text: %@", prepareError);
                    continue;
                }
                if ([self storeRichTextRepresentation:richTextRepresentation]) {
                    [item setRichTextUTI:[richTextRepresentation typeIdentifier]];
                    [item setRichTextName:[richTextRepresentation stableFileName]];
                }
            }
            [items addObject:item];
        }
    }

    return items;
}

- (BOOL)_reallyPullPasteboardChangesWithSourceBundleIdentifier:(NSString *)sourceBundleIdentifier {
    if ([_pendingPasteboardWrite isActive]) {
        HBLogDebug(@"Mt: ignored pasteboard pull while local write is pending token=%lu changeCount=%lu",
                   (unsigned long)[_pendingPasteboardWrite token], (unsigned long)[_pasteboard changeCount]);
        [self resolvePendingPasteboardWriteForToken:[_pendingPasteboardWrite token] didExpire:NO];
        return NO;
    }

    NSArray<MTPasteboardItem *> *items =
        [self pasteboardItemsForCurrentChangeWithSourceBundleIdentifier:sourceBundleIdentifier];
    return [self savePasteboardItemsSynchronously:items toHistoryWithKey:kMTHistoryKeyHistory];
}

#pragma mark - History Access

- (BOOL)savePasteboardItemsSynchronously:(NSArray<MTPasteboardItem *> *)items
                        toHistoryWithKey:(NSString *)historyKey {
    if (_maintenanceMode) {
        return NO;
    }

    BOOL didSaveAnyItem = NO;
    for (MTPasteboardItem *item in items) {
        if ([self addPasteboardItem:item toHistoryWithKey:historyKey]) {
            didSaveAnyItem = YES;
        }
    }
    return didSaveAnyItem;
}

- (void)savePasteboardItems:(NSArray<MTPasteboardItem *> *)items
           toHistoryWithKey:(NSString *)historyKey
                 completion:(void (^)(BOOL didSaveAnyItem))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *dictionaries =
        [[NSMutableArray alloc] initWithCapacity:[items count]];
    for (MTPasteboardItem *item in items) {
        if ([[item content] isEqualToString:@""]) {
            continue;
        }
        [dictionaries addObject:[item dictionaryRepresentation]];
    }

    if ([dictionaries count] == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSUInteger limit = [self limitForHistoryKey:historyKey];
    __weak typeof(self) weakSelf = self;
    [_historyRepository
        addItemDictionaries:dictionaries
               toHistoryKey:historyKey
                 completion:^(NSArray<NSDictionary<NSString *, id> *> *savedDictionaries) {
                   __strong typeof(weakSelf) strongSelf = weakSelf;
                   if (!strongSelf) {
                       return;
                   }
                   for (NSDictionary<NSString *, id> *dictionary in savedDictionaries) {
                       [strongSelf
                           postHistoryChangedNotificationForHistoryKey:historyKey
                                                            changeType:
                                                                kMTPasteboardManagerHistoryChangeTypeUpsertTop
                                                        itemDictionary:dictionary
                                                                 limit:limit];
                   }
                   if (completion) {
                       completion([savedDictionaries count] > 0);
                   }
                 }];
}

#pragma mark - History Mutations

- (BOOL)addPasteboardItem:(MTPasteboardItem *)item toHistoryWithKey:(NSString *)historyKey {
    if (_maintenanceMode) {
        return NO;
    }

    if ([[item content] isEqualToString:@""]) {
        return NO;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    NSUInteger limit = [self limitForHistoryKey:historyKey];
    NSError *error = nil;
    BOOL success = [_historyRepository addItemDictionary:dictionary toHistoryKey:historyKey error:&error];
    if (!success) {
        HBLogDebug(@"Mt: Failed to add history item: %@", error);
        return NO;
    }

    NSDictionary<NSString *, id> *savedDictionary = [_historyRepository latestItemForHistoryKey:historyKey error:nil];
    if (![savedDictionary[kMTItemKeyContent] isEqualToString:dictionary[kMTItemKeyContent]]) {
        savedDictionary = dictionary;
    }
    [self postHistoryChangedNotificationForHistoryKey:historyKey
                                           changeType:kMTPasteboardManagerHistoryChangeTypeUpsertTop
                                       itemDictionary:savedDictionary
                                                limit:limit];
    return YES;
}

- (void)removePasteboardItem:(MTPasteboardItem *)item
          fromHistoryWithKey:(NSString *)historyKey
           shouldRemoveImage:(BOOL)shouldRemoveImage {
    if (_maintenanceMode) {
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    NSError *error = nil;
    BOOL success = [_historyRepository removeItemDictionary:dictionary
                                             fromHistoryKey:historyKey
                                          shouldRemoveImage:shouldRemoveImage
                                                      error:&error];
    if (!success) {
        HBLogDebug(@"Mt: Failed to remove history item: %@", error);
        return;
    }

    [self postHistoryChangedNotificationForHistoryKey:historyKey
                                           changeType:kMTPasteboardManagerHistoryChangeTypeRemove
                                       itemDictionary:dictionary
                                                limit:[self limitForHistoryKey:historyKey]];
}

- (void)removePasteboardItem:(MTPasteboardItem *)item
          fromHistoryWithKey:(NSString *)historyKey
           shouldRemoveImage:(BOOL)shouldRemoveImage
                  completion:(void (^)(BOOL success))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    [_historyRepository removeItemDictionary:dictionary
                              fromHistoryKey:historyKey
                           shouldRemoveImage:shouldRemoveImage
                                  completion:completion];
}

- (void)movePasteboardItem:(MTPasteboardItem *)item
        fromHistoryWithKey:(NSString *)sourceHistoryKey
          toHistoryWithKey:(NSString *)destinationHistoryKey
                completion:(void (^)(BOOL success))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    [_historyRepository moveItemDictionary:dictionary
                            fromHistoryKey:sourceHistoryKey
                              toHistoryKey:destinationHistoryKey
                                completion:completion];
}

- (void)setNote:(NSString *)note
         tagUUID:(NSString *)tagUUID
forPasteboardItem:(MTPasteboardItem *)item
 inHistoryWithKey:(NSString *)historyKey
       completion:(void (^)(BOOL success))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    if (!item || [historyKey length] == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    [_historyRepository setNote:note
                        tagUUID:tagUUID
               forItemDictionary:dictionary
                    inHistoryKey:historyKey
                      completion:completion];
}

- (void)replaceContent:(NSString *)content
     forPasteboardItem:(MTPasteboardItem *)item
      inHistoryWithKey:(NSString *)historyKey
            completion:(void (^)(BOOL success))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    if (!item || [historyKey length] == 0 || [content length] == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    [_historyRepository replaceContent:content
                    forItemDictionary:dictionary
                         inHistoryKey:historyKey
                           completion:completion];
}

- (void)removeAllPasteboardItemsFromHistoryWithKey:(NSString *)historyKey
                                shouldRemoveImages:(BOOL)shouldRemoveImages
                           postsChangeNotification:(BOOL)postsChangeNotification
                                        completion:(void (^)(BOOL success))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    [_historyRepository
        removeItemsFromHistoryKey:historyKey
               shouldRemoveImages:shouldRemoveImages
                       completion:^(BOOL success) {
                         if (success && postsChangeNotification) {
                             [self postHistoryChangedNotificationForHistoryKey:historyKey
                                                                    changeType:
                                                                        kMTPasteboardManagerHistoryChangeTypeClear
                                                                itemDictionary:nil
                                                                         limit:[self limitForHistoryKey:historyKey]];
                         }
                         if (completion) {
                             completion(success);
                         }
                       }];
}

- (void)removeAllPasteboardItemsFromHistoryWithKey:(NSString *)historyKey
                                shouldRemoveImages:(BOOL)shouldRemoveImages
                                        completion:(void (^)(BOOL success))completion {
    [self removeAllPasteboardItemsFromHistoryWithKey:historyKey
                                  shouldRemoveImages:shouldRemoveImages
                             postsChangeNotification:YES
                                          completion:completion];
}

- (void)removeImagePasteboardItemsFromHistoryWithKey:(NSString *)historyKey
                             postsChangeNotification:(BOOL)postsChangeNotification
                                          completion:(void (^)(BOOL success))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    [_historyRepository
        removeImageItemsFromHistoryKey:historyKey
                            completion:^(BOOL success) {
                              if (success && postsChangeNotification) {
                                  [self postHistoryChangedNotificationForHistoryKey:historyKey
                                                                         changeType:
                                                                             kMTPasteboardManagerHistoryChangeTypeClear
                                                                     itemDictionary:nil
                                                                              limit:[self limitForHistoryKey:historyKey]];
                              }
                              if (completion) {
                                  completion(success);
                              }
                            }];
}

#pragma mark - Promotion Policy

- (void)setAutomaticPromotionMode:(NSUInteger)automaticPromotionMode {
    if (automaticPromotionMode != kMTAutomaticPromotionModeOff &&
        automaticPromotionMode != kMTAutomaticPromotionModeHistoryOnly &&
        automaticPromotionMode != kMTAutomaticPromotionModeAlways) {
        automaticPromotionMode = kMTPreferenceKeyAutomaticPromotionModeDefaultValue;
    }
    _automaticPromotionMode = automaticPromotionMode;
}

- (BOOL)shouldPromoteSourceHistoryItemFromHistoryKey:(NSString *)historyKey {
    switch ((MTAutomaticPromotionMode)[self automaticPromotionMode]) {
    case kMTAutomaticPromotionModeOff:
        return NO;
    case kMTAutomaticPromotionModeHistoryOnly:
        return [historyKey isEqualToString:kMTHistoryKeyHistory];
    case kMTAutomaticPromotionModeAlways:
        return [historyKey isEqualToString:kMTHistoryKeyHistory] ||
               [historyKey isEqualToString:kMTHistoryKeyFavorites];
    }
    return NO;
}

#pragma mark - Pasteboard Writes

- (void)writePasteboardItem:(MTPasteboardItem *)pasteboardItem
          sourceHistoryItem:(MTPasteboardItem *)sourceHistoryItem
         fromHistoryWithKey:(NSString *)historyKey
       allowsAutomaticPaste:(BOOL)allowsAutomaticPaste {
    BOOL performsAutomaticPaste = [self automaticallyPaste] && allowsAutomaticPaste;
    MTAutomaticPasteMode automaticPasteMode =
        performsAutomaticPaste ? [self resolvedAutomaticPasteMode] : kMTAutomaticPasteModeClassic;
    if (@available(iOS 16, *)) {
        dispatch_async(_pasteboardQueue, ^{
          [self _reallyWritePasteboardItem:pasteboardItem
                         sourceHistoryItem:sourceHistoryItem
                        fromHistoryWithKey:historyKey
                           shouldAutoPaste:performsAutomaticPaste
                        automaticPasteMode:automaticPasteMode];
        });
        return;
    }

    [self _reallyWritePasteboardItem:pasteboardItem
                   sourceHistoryItem:sourceHistoryItem
                  fromHistoryWithKey:historyKey
                     shouldAutoPaste:performsAutomaticPaste
                  automaticPasteMode:automaticPasteMode];
}

- (void)copyPasteboardItemToPasteboard:(MTPasteboardItem *)item
                             completion:(nullable void (^)(BOOL))completion {
    void (^finish)(BOOL) = ^(BOOL didUpdatePasteboard) {
        if (!completion) return;
        dispatch_async(dispatch_get_main_queue(), ^{
          completion(didUpdatePasteboard);
        });
    };
    if (@available(iOS 16, *)) {
        // 不做 dispatch_sync：主线程（面板/预览动作都在主线程）同步等待
        // 剪贴板串行队列的 pasted IPC，pasted 忙/卡时无超时挂死主线程。
        dispatch_async(_pasteboardQueue, ^{
          finish([self _reallyCopyPasteboardItemToPasteboard:item]);
        });
        return;
    }

    finish([self _reallyCopyPasteboardItemToPasteboard:item]);
}

- (BOOL)_reallyCopyPasteboardItemToPasteboard:(MTPasteboardItem *)item {
    [self cancelPendingPasteboardWrite];
    NSUInteger previousChangeCount = [_pasteboard changeCount];
    HBLogDebug(@"Mt: copy write started previousChangeCount=%lu contentLength=%lu hasImage=%@",
               (unsigned long)previousChangeCount, (unsigned long)[[item content] length],
               ([[item imageName] length] > 0) ? @"YES" : @"NO");
    BOOL didUpdatePasteboard = [self setPasteboardContentFromItem:item];
    if (didUpdatePasteboard) {
        NSUInteger token = [self beginPendingPasteboardWriteAfterChangeCount:previousChangeCount
                                                             shouldAutoPaste:NO
                                                          automaticPasteMode:kMTAutomaticPasteModeClassic];
        [self resolvePendingPasteboardWriteForToken:token didExpire:NO];
    } else {
        HBLogDebug(@"Mt: copy write did not update pasteboard previousChangeCount=%lu",
                   (unsigned long)previousChangeCount);
    }
    return didUpdatePasteboard;
}

- (void)_reallyWritePasteboardItem:(MTPasteboardItem *)pasteboardItem
                 sourceHistoryItem:(MTPasteboardItem *)sourceHistoryItem
                fromHistoryWithKey:(NSString *)historyKey
                   shouldAutoPaste:(BOOL)shouldAutoPaste
                automaticPasteMode:(MTAutomaticPasteMode)automaticPasteMode {
    if (_isWritingPasteboardItem) {
        HBLogDebug(@"Mt: pasteboard item write ignored because another write is in progress");
        return;
    }

    _isWritingPasteboardItem = YES;

    [self cancelPendingPasteboardWrite];
    NSUInteger previousChangeCount = [_pasteboard changeCount];
    HBLogDebug(@"Mt: pasteboard item write started previousChangeCount=%lu contentLength=%lu hasImage=%@ "
               @"shouldAutoPaste=%@ automaticallyPaste=%@ automaticPasteMode=%lu automaticPromotionMode=%lu "
               @"historyKey=%@",
               (unsigned long)previousChangeCount, (unsigned long)[[pasteboardItem content] length],
               ([[pasteboardItem imageName] length] > 0) ? @"YES" : @"NO", shouldAutoPaste ? @"YES" : @"NO",
               [self automaticallyPaste] ? @"YES" : @"NO", (unsigned long)[self automaticPasteMode],
               (unsigned long)[self automaticPromotionMode], historyKey);
    BOOL didUpdatePasteboard = [self setPasteboardContentFromItem:pasteboardItem];
    if (didUpdatePasteboard) {
        if ([self shouldPromoteSourceHistoryItemFromHistoryKey:historyKey]) {
            [self movePasteboardItemToTop:sourceHistoryItem inHistoryWithKey:historyKey];
        }

        NSUInteger token = [self beginPendingPasteboardWriteAfterChangeCount:previousChangeCount
                                                             shouldAutoPaste:shouldAutoPaste
                                                          automaticPasteMode:automaticPasteMode];
        [self resolvePendingPasteboardWriteForToken:token didExpire:NO];
    } else {
        HBLogDebug(@"Mt: pasteboard item write did not update pasteboard previousChangeCount=%lu",
                   (unsigned long)previousChangeCount);
    }

    _isWritingPasteboardItem = NO;
}

- (NSUInteger)beginPendingPasteboardWriteAfterChangeCount:(NSUInteger)previousChangeCount
                                          shouldAutoPaste:(BOOL)shouldAutoPaste
                                       automaticPasteMode:(MTAutomaticPasteMode)automaticPasteMode {
    NSUInteger token = [_pendingPasteboardWrite beginAfterChangeCount:previousChangeCount
                                                      shouldAutoPaste:shouldAutoPaste
                                                   automaticPasteMode:automaticPasteMode];
    HBLogDebug(@"Mt: pending pasteboard write began token=%lu previousChangeCount=%lu shouldAutoPaste=%@ "
               @"automaticPasteMode=%lu",
               (unsigned long)token, (unsigned long)previousChangeCount, shouldAutoPaste ? @"YES" : @"NO",
               (unsigned long)automaticPasteMode);
    dispatch_queue_t timeoutQueue = dispatch_get_main_queue();
    if (@available(iOS 16, *)) {
        timeoutQueue = _pasteboardQueue;
    }
    __weak typeof(self) weakSelf = self;
    [_pendingPasteboardWrite scheduleExpirationOnQueue:timeoutQueue
                                            afterDelay:kMTPasteboardWriteConfirmationTimeout
                                               handler:^{
                                                 __strong typeof(weakSelf) strongSelf = weakSelf;
                                                 [strongSelf resolvePendingPasteboardWriteForToken:token didExpire:YES];
                                               }];

    return token;
}

- (BOOL)resolvePendingPasteboardWriteForToken:(NSUInteger)token didExpire:(BOOL)didExpire {
    if (![_pendingPasteboardWrite matchesToken:token]) {
        if (didExpire) {
            HBLogDebug(@"Mt: ignored stale pending pasteboard write timeout token=%lu activeToken=%lu active=%@",
                       (unsigned long)token, (unsigned long)[_pendingPasteboardWrite token],
                       ([_pendingPasteboardWrite isActive] ? @"YES" : @"NO"));
        }
        return NO;
    }

    NSUInteger currentChangeCount = [_pasteboard changeCount];
    if (![_pendingPasteboardWrite hasAdvancedToChangeCount:currentChangeCount]) {
        if (didExpire) {
            HBLogDebug(
                @"Mt: pending pasteboard write timed out token=%lu previousChangeCount=%lu currentChangeCount=%lu",
                (unsigned long)token, (unsigned long)[_pendingPasteboardWrite previousChangeCount],
                (unsigned long)currentChangeCount);
            [self cancelPendingPasteboardWrite];
        }
        return NO;
    }

    BOOL shouldAutoPaste = [_pendingPasteboardWrite shouldAutoPaste];
    MTAutomaticPasteMode automaticPasteMode = [_pendingPasteboardWrite automaticPasteMode];
    _lastChangeCount = currentChangeCount;
    [self cancelPendingPasteboardWrite];

    HBLogDebug(@"Mt: pending pasteboard write confirmed token=%lu currentChangeCount=%lu shouldAutoPaste=%@ "
               @"automaticPasteMode=%lu",
               (unsigned long)token, (unsigned long)currentChangeCount, shouldAutoPaste ? @"YES" : @"NO",
               (unsigned long)automaticPasteMode);
    if (shouldAutoPaste) {
        [self performAutomaticPasteForToken:token automaticPasteMode:automaticPasteMode];
    }

    return YES;
}

- (void)performAutomaticPasteForToken:(NSUInteger)token
                   automaticPasteMode:(MTAutomaticPasteMode)automaticPasteMode {
    if (automaticPasteMode == kMTAutomaticPasteModeSimulated) {
        HBLogDebug(@"Mt: scheduling simulated Cmd+V automatic paste token=%lu delay=%.2f", (unsigned long)token,
                   kMTSimulatedAutomaticPasteDelay);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kMTSimulatedAutomaticPasteDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         CFNotificationCenterPostNotification(
                             CFNotificationCenterGetDarwinNotifyCenter(),
                             (__bridge CFStringRef)kMTNotificationKeyPasteWillStart, nil, nil, YES);
                         CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                              (__bridge CFStringRef)kMTNotificationKeyPasteFeedback,
                                                              nil, nil, YES);
                         [[MTKeyboardShortcutSender sharedSender] sendCommandV];
                       });
        return;
    }

    HBLogDebug(@"Mt: posting helper paste notification token=%lu", (unsigned long)token);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kMTNotificationKeyHelperPaste, nil, nil, NO);
}

- (MTAutomaticPasteMode)resolvedAutomaticPasteMode {
    MTAutomaticPasteMode automaticPasteMode = (MTAutomaticPasteMode)[self automaticPasteMode];
    if (automaticPasteMode != kMTAutomaticPasteModeAutomatic) {
        return automaticPasteMode;
    }

    BOOL usesClassic = [self effectiveKeyboardHostUsesClassicAutomaticPaste];
    HBLogDebug(@"Mt: automatic paste auto mode resolved to %@", usesClassic ? @"classic" : @"simulated");
    return usesClassic ? kMTAutomaticPasteModeClassic : kMTAutomaticPasteModeSimulated;
}

- (BOOL)effectiveKeyboardHostUsesClassicAutomaticPaste {
    MTKeyboardHostContext *hostContext =
        [[MTKeyboardHostResolver sharedResolver] effectiveExternalKeyboardHostContext];
    if (!hostContext) {
        HBLogDebug(@"Mt: automatic paste auto mode has no external keyboard host context; using simulated");
        return NO;
    }

    BOOL springBoardHost =
        hostContext.kind == MTKeyboardHostKindSpringBoard || hostContext.kind == MTKeyboardHostKindSpotlight;
    BOOL usesClassic = springBoardHost || [hostContext isHelperInjected];
    HBLogDebug(@"Mt: automatic paste auto mode using %@ keyboard host scene=%@ kind=%@ cached=%@ "
               @"helperMarkerAvailable=%@ helperFlag=%lld injected=%@",
               hostContext.isCached ? @"cached external" : @"current", hostContext.identifier,
               [MTKeyboardHostResolver stringForHostKind:hostContext.kind], hostContext.isCached ? @"YES" : @"NO",
               hostContext.helperMarkerAvailable ? @"YES" : @"NO", hostContext.helperInjectedFlag,
               hostContext.isHelperInjected ? @"YES" : @"NO");
    return usesClassic;
}

- (void)cancelPendingPasteboardWrite {
    [_pendingPasteboardWrite cancel];
}

- (BOOL)setPasteboardContentFromItem:(MTPasteboardItem *)item {
    if (!item) {
        return NO;
    }

    if ([[item imageName] length] > 0) {
        NSString *filePath =
            [NSString stringWithFormat:@"%@/%@", [MTPasteboardManager historyImagesPath], [item imageName]];
        UIImage *image = [UIImage imageWithContentsOfFile:filePath];
        if (!image) {
            return NO;
        }

        [_pasteboard setImage:image];
        return YES;
    }

    if ([[item content] length] == 0) {
        return NO;
    }

    NSString *richTextUTI = [item richTextUTI];
    NSString *richTextName = [item richTextName];
    if ([richTextUTI length] > 0 && [richTextName length] > 0 &&
        [[richTextName lastPathComponent] isEqualToString:richTextName]) {
        NSString *filePath =
            [[MTPasteboardManager historyRichTextPath] stringByAppendingPathComponent:richTextName];
        NSData *richTextData = [_fileManager contentsAtPath:filePath];
        MTRichTextRepresentation *representation = [MTRichTextRepresentation
            preferredRepresentationFromDictionary:@{richTextUTI : richTextData ?: [NSData data]}];
        if ([[representation typeIdentifier] isEqualToString:richTextUTI] &&
            [[representation stableFileName] isEqualToString:richTextName]) {
            id richTextValue = [representation data];
            if ([richTextUTI isEqualToString:@"public.html"]) {
                richTextValue = [[NSString alloc] initWithData:[representation data] encoding:NSUTF8StringEncoding];
            }
            if (richTextValue) {
                [_pasteboard setItems:@[ @{
                                 @"public.utf8-plain-text" : [item content],
                                 richTextUTI : richTextValue,
                             } ]];
                return YES;
            }
        }
    }

    [_pasteboard setString:[item content]];
    return YES;
}

- (void)movePasteboardItemToTop:(MTPasteboardItem *)item inHistoryWithKey:(NSString *)historyKey {
    if (_maintenanceMode) {
        return;
    }

    if (!item || [[item content] length] == 0 || [[historyKey description] length] == 0) {
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    NSUInteger limit = [self limitForHistoryKey:historyKey];
    NSError *error = nil;
    BOOL success = [_historyRepository moveItemDictionaryToTop:dictionary inHistoryKey:historyKey error:&error];
    if (!success) {
        HBLogDebug(@"Mt: Failed to promote history item: %@", error);
        return;
    }

    [self postHistoryChangedNotificationForHistoryKey:historyKey
                                           changeType:kMTPasteboardManagerHistoryChangeTypeUpsertTop
                                       itemDictionary:dictionary
                                                limit:limit];
}

#pragma mark - History Reads

- (NSError *)maintenanceModeError {
    NSString *description = [[MTPasteboardManager localizationBundle]
        localizedStringForKey:
            @"Mt history is unavailable while package maintenance is in progress. Try again after "
            @"installation finishes."
                        value:nil
                        table:@"Tweak"];
    return [NSError errorWithDomain:kMTPasteboardManagerErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey : description}];
}

- (NSMutableArray<NSDictionary<NSString *, id> *> *)getItemsFromHistoryWithKey:(NSString *)historyKey {
    if (_maintenanceMode) {
        return [[NSMutableArray alloc] init];
    }

    NSError *error = nil;
    NSMutableArray<NSDictionary<NSString *, id> *> *history = [_historyRepository itemsForHistoryKey:historyKey
                                                                                               error:&error];
    if (error) {
        HBLogDebug(@"Mt: Failed to load history items: %@", error);
    }
    return history ?: [[NSMutableArray alloc] init];
}

- (void)getItemsFromHistoryWithKey:(NSString *)historyKey completion:(MTPasteboardItemsCompletion)completion {
    [self getItemsFromHistoryWithKey:historyKey searchCriteria:nil completion:completion];
}

- (void)getItemsFromHistoryWithKey:(NSString *)historyKey
                    searchCriteria:(MTSearchCriteria *)searchCriteria
                        completion:(MTPasteboardItemsCompletion)completion {
    if (_maintenanceMode) {
        if (completion) {
            completion([[NSMutableArray alloc] init], [self maintenanceModeError]);
        }
        return;
    }

    [_historyRepository itemsForHistoryKey:historyKey searchCriteria:searchCriteria completion:completion];
}

- (void)availableSearchAppBundleIdentifiersWithCompletion:(MTPasteboardAppBundleIdentifiersCompletion)completion {
    [self availableSearchAppBundleIdentifiersForHistoryKey:nil completion:completion];
}

- (void)availableSearchAppBundleIdentifiersForHistoryKey:(NSString *)historyKey
                                              completion:(MTPasteboardAppBundleIdentifiersCompletion)completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(@[], [self maintenanceModeError]);
        }
        return;
    }

    if ([historyKey length] == 0) {
        [_historyRepository availableSearchAppBundleIdentifiersWithCompletion:completion];
    } else {
        [_historyRepository availableSearchAppBundleIdentifiersForHistoryKey:historyKey completion:completion];
    }
}

- (MTPasteboardItem *)getLatestHistoryItem {
    if (_maintenanceMode) {
        return nil;
    }

    NSError *error = nil;
    NSDictionary<NSString *, id> *dictionary = [_historyRepository latestItemForHistoryKey:kMTHistoryKeyHistory
                                                                                     error:&error];
    if (error) {
        HBLogDebug(@"Mt: Failed to load latest history item: %@", error);
    }
    return [MTPasteboardItem itemFromDictionary:dictionary];
}

- (UIImage *)getImageForItem:(MTPasteboardItem *)item {
    NSData *imageData =
        [_fileManager contentsAtPath:[NSString stringWithFormat:@"%@/%@", [MTPasteboardManager historyImagesPath],
                                                                [item imageName]]];
    return [UIImage imageWithData:imageData];
}

- (void)getThumbnailForItem:(MTPasteboardItem *)item
                 targetSize:(CGSize)targetSize
                 completion:(void (^)(UIImage *_Nullable image))completion {
    NSString *imageName = [[item imageName] copy];
    NSString *imagePath = [[MTPasteboardManager historyImagesPath] stringByAppendingPathComponent:imageName ?: @""];
    [_thumbnailCache thumbnailForImageName:imageName ?: @""
                                 imagePath:imagePath
                                targetSize:targetSize
                                     scale:[[UIScreen mainScreen] scale]
                                completion:completion];
}

#pragma mark - Notifications

- (void)postHistoryChangedNotification {
    [_historyChangeNotifier postReloadNotificationWithObject:self];
}

- (void)postHistoryChangedNotificationForHistoryKey:(NSString *)historyKey
                                         changeType:(NSString *)changeType
                                     itemDictionary:(NSDictionary<NSString *, id> *)itemDictionary
                                              limit:(NSUInteger)limit {
    [_historyChangeNotifier postChangeNotificationForHistoryKey:historyKey
                                                     changeType:changeType
                                                 itemDictionary:itemDictionary
                                                          limit:limit
                                                         object:self];
}

#pragma mark - Limits

- (NSUInteger)limitForHistoryKey:(NSString *)historyKey {
    if ([historyKey isEqualToString:kMTHistoryKeyFavorites]) {
        return NSUIntegerMax;
    }

    return [self maximumHistoryAmount];
}

@end
