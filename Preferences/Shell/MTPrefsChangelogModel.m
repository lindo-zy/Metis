#import "MTPrefsChangelogModel.h"

NSUInteger const MTPrefsChangelogEntryLimit = 5;

static NSString *const MTPrefsChangelogResourceName = @"Changelog";
static NSString *const MTPrefsChangelogResourceType = @"plist";

static NSString *MTChangelogTagName(MTChangelogTag tag) {
    switch (tag) {
        case MTChangelogTagAdded: return @"新增";
        case MTChangelogTagImproved: return @"优化";
        case MTChangelogTagFixed: return @"修复";
        case MTChangelogTagChanged: return @"调整";
    }
    return @"调整";
}

// 数据文件用中文标签书写（便于人工维护），归一化后不区分未知写法。
static MTChangelogTag MTChangelogTagFromString(NSString *raw) {
    NSString *name = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([name isEqualToString:@"新增"]) return MTChangelogTagAdded;
    if ([name isEqualToString:@"优化"]) return MTChangelogTagImproved;
    if ([name isEqualToString:@"修复"]) return MTChangelogTagFixed;
    return MTChangelogTagChanged;
}

@implementation MTChangelogItem

+ (instancetype)itemWithTag:(MTChangelogTag)tag text:(NSString *)text {
    MTChangelogItem *item = [[self alloc] init];
    item->_tag = tag;
    item->_text = [text copy];
    return item;
}

- (NSString *)tagDisplayName {
    return MTChangelogTagName(self.tag);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@ %@>", NSStringFromClass(self.class),
            self.tagDisplayName, self.text];
}

@end

@implementation MTChangelogEntry

+ (instancetype)entryWithVersion:(NSString *)version items:(NSArray<MTChangelogItem *> *)items {
    MTChangelogEntry *entry = [[self alloc] init];
    entry->_version = [version copy];
    entry->_items = [items copy] ?: @[];
    return entry;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@ items=%@>", NSStringFromClass(self.class),
            self.version, @(self.items.count)];
}

@end

@implementation MTPrefsChangelogModel

#pragma mark - Resource

+ (NSArray<MTChangelogEntry *> *)entries {
    return [self entriesWithLimit:MTPrefsChangelogEntryLimit];
}

+ (NSArray<MTChangelogEntry *> *)entriesWithLimit:(NSUInteger)limit {
    NSUInteger effectiveLimit = limit > 0 ? limit : MTPrefsChangelogEntryLimit;
    NSArray *raw = nil;
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *path = [bundle pathForResource:MTPrefsChangelogResourceName
                                      ofType:MTPrefsChangelogResourceType];
    if (path.length) {
        raw = [NSArray arrayWithContentsOfFile:path];
    }
    return [self entriesFromArray:raw limit:effectiveLimit];
}

#pragma mark - Pure transform

+ (NSArray<MTChangelogEntry *> *)entriesFromArray:(NSArray *)raw limit:(NSUInteger)limit {
    NSUInteger effectiveLimit = limit > 0 ? limit : MTPrefsChangelogEntryLimit;
    if (![raw isKindOfClass:NSArray.class] || raw.count == 0) return @[];

    NSMutableArray<MTChangelogEntry *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *seenVersions = [NSMutableSet set];

    for (id object in raw) {
        if (![object isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *dictionary = (NSDictionary *)object;

        id versionValue = dictionary[@"version"];
        if (![versionValue isKindOfClass:NSString.class]) continue;
        NSString *version = [(NSString *)versionValue
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!version.length) continue;
        if ([seenVersions containsObject:version]) continue;

        id rawItems = dictionary[@"items"];
        if (![rawItems isKindOfClass:NSArray.class]) continue;

        NSMutableArray<MTChangelogItem *> *items = [NSMutableArray array];
        for (id rawItem in (NSArray *)rawItems) {
            if (![rawItem isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *itemDictionary = (NSDictionary *)rawItem;
            id textValue = itemDictionary[@"text"];
            if (![textValue isKindOfClass:NSString.class]) continue;
            NSString *text = [(NSString *)textValue
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!text.length) continue;
            id tagValue = itemDictionary[@"tag"];
            MTChangelogTag tag = [tagValue isKindOfClass:NSString.class]
                ? MTChangelogTagFromString((NSString *)tagValue)
                : MTChangelogTagChanged;
            [items addObject:[MTChangelogItem itemWithTag:tag text:text]];
        }
        // 没有任何可用条目的版本不展示，避免出现只有标题的空块。
        if (items.count == 0) continue;

        [seenVersions addObject:version];
        [entries addObject:[MTChangelogEntry entryWithVersion:version items:items]];
    }

    [entries sortUsingComparator:^NSComparisonResult(MTChangelogEntry *lhs, MTChangelogEntry *rhs) {
        return [MTPrefsChangelogModel compareVersion:rhs.version toVersion:lhs.version];
    }];

    if (entries.count > effectiveLimit) {
        return [entries subarrayWithRange:NSMakeRange(0, effectiveLimit)];
    }
    return [entries copy];
}

#pragma mark - Version compare

+ (NSComparisonResult)compareVersion:(NSString *)lhs toVersion:(NSString *)rhs {
    NSArray<NSString *> *left = [(lhs ?: @"") componentsSeparatedByString:@"."];
    NSArray<NSString *> *right = [(rhs ?: @"") componentsSeparatedByString:@"."];
    NSUInteger count = MAX(left.count, right.count);
    for (NSUInteger index = 0; index < count; index++) {
        NSInteger leftValue = index < left.count ? left[index].integerValue : 0;
        NSInteger rightValue = index < right.count ? right[index].integerValue : 0;
        if (leftValue != rightValue) {
            return leftValue > rightValue ? NSOrderedDescending : NSOrderedAscending;
        }
    }
    return NSOrderedSame;
}

#pragma mark - Title

+ (NSString *)sheetTitleForEntries:(NSArray<MTChangelogEntry *> *)entries {
    if (entries.count == 0) return @"更新说明";
    MTChangelogEntry *latest = entries.firstObject;
    if (entries.count == 1) {
        return [NSString stringWithFormat:@"更新说明 · %@", latest.version];
    }
    MTChangelogEntry *previous = entries[1];
    return [NSString stringWithFormat:@"更新（%@ → %@）", previous.version, latest.version];
}

@end
