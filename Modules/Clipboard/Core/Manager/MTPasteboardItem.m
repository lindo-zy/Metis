//
//  MTPasteboardItem.m
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import "MTPasteboardItem.h"

#import <math.h>

NSString *const kMTContinuityBundleIdentifier = @"com.apple.continuity";

@implementation MTPasteboardItem

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                              andContent:(NSString *)content
                          withImageNamed:(NSString *)imageName {
    self = [super init];

    if (self) {
        [self setBundleIdentifier:bundleIdentifier];
        [self setContent:content];
        [self setImageName:imageName];
        [self setRichTextName:@""];
        [self setCapturedAt:[NSDate date]];
        [self setHasLink:[content hasPrefix:@"http://"] || [content hasPrefix:@"https://"]];
    }

    return self;
}

+ (MTPasteboardItem *)itemFromDictionary:(NSDictionary<NSString *, id> *)dictionary {
    if (!dictionary) {
        return nil;
    }

    NSString *bundleIdentifier = dictionary[kMTItemKeyBundleIdentifier];
    NSString *content = dictionary[kMTItemKeyContent];
    NSString *imageName = dictionary[kMTItemKeyImageName];
    MTPasteboardItem *item = [[MTPasteboardItem alloc] initWithBundleIdentifier:bundleIdentifier
                                                                             andContent:content
                                                                         withImageNamed:imageName];
    id note = dictionary[kMTItemKeyNote];
    if ([note isKindOfClass:[NSString class]] && [note length] > 0) {
        [item setNote:note];
    }
    id capturedAt = dictionary[kMTItemKeyCapturedAt];
    if ([capturedAt isKindOfClass:[NSNumber class]]) {
        NSTimeInterval capturedAtTimestamp = [capturedAt doubleValue];
        if (isfinite(capturedAtTimestamp) && capturedAtTimestamp > 0.0) {
            [item setCapturedAt:[NSDate dateWithTimeIntervalSince1970:capturedAtTimestamp]];
        }
    }
    id imagePixelWidth = dictionary[kMTItemKeyImagePixelWidth];
    id imagePixelHeight = dictionary[kMTItemKeyImagePixelHeight];
    if ([imagePixelWidth isKindOfClass:[NSNumber class]] && [imagePixelHeight isKindOfClass:[NSNumber class]]) {
        NSInteger width = [imagePixelWidth integerValue];
        NSInteger height = [imagePixelHeight integerValue];
        if (width > 0 && height > 0) {
            [item setImagePixelWidth:(NSUInteger)width];
            [item setImagePixelHeight:(NSUInteger)height];
        }
    }
    id richTextUTI = dictionary[kMTItemKeyRichTextUTI];
    id richTextName = dictionary[kMTItemKeyRichTextName];
    if ([richTextUTI isKindOfClass:[NSString class]] && [richTextUTI length] > 0 &&
        [richTextName isKindOfClass:[NSString class]] && [richTextName length] > 0) {
        [item setRichTextUTI:richTextUTI];
        [item setRichTextName:richTextName];
    }
    id imageByteCount = dictionary[kMTItemKeyImageByteCount];
    if ([imageByteCount isKindOfClass:[NSNumber class]] && [imageByteCount longLongValue] > 0) {
        [item setImageByteCount:[imageByteCount unsignedLongLongValue]];
    }
    return item;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSTimeInterval capturedAtTimestamp = [[self capturedAt] timeIntervalSince1970];
    if (!isfinite(capturedAtTimestamp) || capturedAtTimestamp <= 0.0) {
        capturedAtTimestamp = [[NSDate date] timeIntervalSince1970];
    }
    NSMutableDictionary<NSString *, id> *dictionary = [@{
        kMTItemKeyBundleIdentifier : [self bundleIdentifier] ?: @"com.apple.springboard",
        kMTItemKeyContent : [self content] ?: @"",
        kMTItemKeyImageName : [self imageName] ?: @"",
        kMTItemKeyHasLink : @([self hasLink]),
        kMTItemKeyCapturedAt : @(capturedAtTimestamp),
        kMTItemKeyImagePixelWidth : @([self imagePixelWidth]),
        kMTItemKeyImagePixelHeight : @([self imagePixelHeight]),
        kMTItemKeyImageByteCount : @([self imageByteCount])
    } mutableCopy];
    if ([[self note] length] > 0) {
        dictionary[kMTItemKeyNote] = [self note];
    }
    if ([[self richTextUTI] length] > 0 && [[self richTextName] length] > 0) {
        dictionary[kMTItemKeyRichTextUTI] = [self richTextUTI];
        dictionary[kMTItemKeyRichTextName] = [self richTextName];
    }
    return dictionary;
}

@end
