#import <Foundation/Foundation.h>

// Retain section headings only when they have matching children. Matching a
// section heading includes its rows, with stable original ordering and IDs.
static inline NSIndexSet *DXSettingsSearchIndices(NSArray<NSDictionary *> *rows, NSString *query) {
    NSString *needle = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!needle.length) return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, rows.count)];
    NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
    NSUInteger section = NSNotFound;
    BOOL sectionMatches = NO;
    for (NSUInteger index = 0; index < rows.count; index++) {
        NSDictionary *row = rows[index];
        NSString *text = [row[@"text"] isKindOfClass:NSString.class] ? row[@"text"] : @"";
        BOOL matches = [text rangeOfString:needle options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch].location != NSNotFound;
        if ([row[@"group"] boolValue]) { section = index; sectionMatches = matches; continue; }
        if (matches || sectionMatches) {
            if (section != NSNotFound) [result addIndex:section];
            [result addIndex:index];
        }
    }
    return result;
}
