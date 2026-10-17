//
//  MTTagCatalog.m
//  Mt
//

#import "MTTagCatalog.h"

#import "MTPasteboardManager.h"
#import "MTTag.h"
#import "MTTagStore.h"

@interface MTTagCatalog ()
@property(nonatomic, copy) NSArray<MTTag *> *cachedTags;
@property(nonatomic, copy) NSDictionary<NSString *, MTTag *> *cachedTagsByUUID;
@property(nonatomic, assign, getter=hasLoadedTags) BOOL loadedTags;
@end

@implementation MTTagCatalog

+ (instancetype)sharedCatalog {
    static MTTagCatalog *catalog = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      catalog = [[MTTagCatalog alloc] init];
    });
    return catalog;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cachedTags = @[];
        _cachedTagsByUUID = @{};
    }
    return self;
}

- (NSArray<MTTag *> *)reloadTags {
    return [self reloadTagsForcingDiskRead:YES];
}

- (NSArray<MTTag *> *)reloadTagsForcingDiskRead:(BOOL)forceDiskRead {
    if (!forceDiskRead && [self hasLoadedTags]) {
        return [self cachedTags];
    }

    MTTagStore *store = [[MTTagStore alloc] initWithTagsPath:[MTTagStore defaultTagsPath]
                                                  localizationBundle:[MTPasteboardManager localizationBundle]];
    NSError *error = nil;
    NSArray<MTTag *> *tags = [store readTagsWithError:&error] ?: @[];

    NSMutableDictionary<NSString *, MTTag *> *tagsByUUID =
        [[NSMutableDictionary alloc] initWithCapacity:[tags count]];
    for (MTTag *tag in tags) {
        if ([[tag uuid] length] > 0) {
            tagsByUUID[[tag uuid]] = tag;
        }
    }

    [self setCachedTags:[tags copy]];
    [self setCachedTagsByUUID:tagsByUUID];
    [self setLoadedTags:YES];
    return [self cachedTags];
}

- (NSArray<MTTag *> *)tags {
    if (![self hasLoadedTags]) {
        return [self reloadTags];
    }
    return [self cachedTags];
}

- (MTTag *)tagForUUID:(NSString *)uuid {
    if ([uuid length] == 0) {
        return nil;
    }
    if (![self hasLoadedTags]) {
        [self reloadTags];
    }
    return [self cachedTagsByUUID][uuid];
}

@end
