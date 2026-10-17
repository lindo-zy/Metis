#import "MTAppSearch.h"

NSString *MTAppSearchNormalize(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSString *folded = [[text stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch
        locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]] lowercaseString];
    return [[folded componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]
        componentsJoinedByString:@""];
}

static NSString *MTAppSearchDigits(NSString *text) {
    NSString *letters = @"abcdefghijklmnopqrstuvwxyz", *digits = @"22233344455566677778889999";
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c >= '0' && c <= '9') [result appendFormat:@"%C", c];
        else {
            NSRange range = [letters rangeOfString:[NSString stringWithCharacters:&c length:1]];
            if (range.location == NSNotFound) return @"";
            [result appendString:[digits substringWithRange:NSMakeRange(range.location, 1)]];
        }
    }
    return result;
}

@implementation MTAppSearchEntry
+ (instancetype)entryWithIdentifier:(NSString *)identifier name:(NSString *)name aliases:(NSArray *)aliases {
    MTAppSearchEntry *entry = [self new];
    entry->_identifier = [identifier copy];
    entry->_name = [name copy];
    NSMutableOrderedSet *terms = [NSMutableOrderedSet orderedSet];
    NSMutableArray *sources = [NSMutableArray arrayWithObject:name ?: @""];
    for (id alias in aliases) if ([alias isKindOfClass:NSString.class] && [alias length] <= 128) [sources addObject:alias];
    for (NSString *source in sources) {
        NSString *normalized = MTAppSearchNormalize(source);
        if (normalized.length) [terms addObject:normalized];
        NSMutableString *latin = [source mutableCopy];
        CFStringTransform((__bridge CFMutableStringRef)latin, NULL, kCFStringTransformMandarinLatin, false);
        CFStringTransform((__bridge CFMutableStringRef)latin, NULL, kCFStringTransformStripCombiningMarks, false);
        NSString *full = MTAppSearchNormalize(latin);
        if (full.length) [terms addObject:full];
        NSMutableString *initials = [NSMutableString string];
        for (NSString *word in [latin componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]) {
            if (word.length) [initials appendString:[[word substringToIndex:1] lowercaseString]];
        }
        if (initials.length) [terms addObject:initials];
        for (NSString *text in @[full, initials]) {
            NSString *digits = MTAppSearchDigits(text);
            if (digits.length) [terms addObject:digits];
        }
    }
    entry->_terms = terms.array;
    return entry;
}
@end
@implementation MTAppSearchMatch
@end

static BOOL MTAppSearchNeighbor(unichar a, unichar b) {
    if (a < '1' || a > '9' || b < '1' || b > '9') return NO;
    NSInteger x = a - '1', y = b - '1';
    return labs(x / 3 - y / 3) + labs(x % 3 - y % 3) == 1;
}

static NSInteger MTAppSearchQuality(MTAppSearchEntry *entry, NSString *query) {
    NSInteger best = NSIntegerMax;
    BOOL numeric = query.length >= 3 && [query rangeOfCharacterFromSet:
        [NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location == NSNotFound;
    for (NSString *term in entry.terms) {
        if ([term isEqual:query]) return 0;
        if ([term hasPrefix:query]) { best = MIN(best, 1); continue; }
        if ([term containsString:query]) { best = MIN(best, 2); continue; }
        if (!numeric || term.length < query.length || term.length > 128) continue;
        NSUInteger mistakes = 0;
        for (NSUInteger i = 0; i < query.length; i++) {
            unichar a = [term characterAtIndex:i], b = [query characterAtIndex:i];
            if (a == b) continue;
            if (++mistakes > 1 || !MTAppSearchNeighbor(a, b)) { mistakes = 2; break; }
        }
        if (mistakes == 1) best = MIN(best, 3);
    }
    return best;
}

static double MTAppSearchUsage(NSDictionary *usage, NSString *identifier, NSString *key) {
    id record = usage[identifier];
    id value = [record isKindOfClass:NSDictionary.class] ? record[key] : nil;
    double number = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0;
    return isfinite(number) ? MAX(0, number) : 0;
}

NSArray<MTAppSearchMatch *> *MTAppSearch(NSArray<MTAppSearchEntry *> *entries, NSString *rawQuery,
    NSArray<NSString *> *favorites, NSDictionary *usage) {
    NSString *query = MTAppSearchNormalize(rawQuery);
    if (query.length == 0 || query.length > 64) return @[];
    NSSet *pinned = [NSSet setWithArray:favorites ?: @[]];
    NSMutableArray<MTAppSearchMatch *> *matches = [NSMutableArray array];
    for (MTAppSearchEntry *entry in entries) {
        NSInteger quality = MTAppSearchQuality(entry, query);
        if (quality == NSIntegerMax) continue;
        MTAppSearchMatch *match = [MTAppSearchMatch new]; match.entry = entry; match.quality = quality;
        [matches addObject:match];
    }
    [matches sortUsingComparator:^NSComparisonResult(MTAppSearchMatch *a, MTAppSearchMatch *b) {
        if (a.quality != b.quality) return a.quality < b.quality ? NSOrderedAscending : NSOrderedDescending;
        BOOL ap = [pinned containsObject:a.entry.identifier], bp = [pinned containsObject:b.entry.identifier];
        if (ap != bp) return ap ? NSOrderedAscending : NSOrderedDescending;
        for (NSString *key in @[@"count", @"last"]) {
            double av = MTAppSearchUsage(usage, a.entry.identifier, key), bv = MTAppSearchUsage(usage, b.entry.identifier, key);
            if (av != bv) return av > bv ? NSOrderedAscending : NSOrderedDescending;
        }
        NSComparisonResult name = [a.entry.name localizedStandardCompare:b.entry.name];
        return name == NSOrderedSame ? [a.entry.identifier compare:b.entry.identifier] : name;
    }];
    return matches;
}
