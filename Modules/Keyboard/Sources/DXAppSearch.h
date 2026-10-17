#import <Foundation/Foundation.h>

@interface DXAppSearchEntry : NSObject
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSArray<NSString *> *terms;
+ (instancetype)entryWithIdentifier:(NSString *)identifier name:(NSString *)name aliases:(NSArray *)aliases;
@end

@interface DXAppSearchMatch : NSObject
@property(nonatomic, strong) DXAppSearchEntry *entry;
@property(nonatomic) NSInteger quality; // 0 exact, 1 prefix, 2 substring, 3 adjacent-key typo
@end

FOUNDATION_EXPORT NSString *DXAppSearchNormalize(NSString *text);
FOUNDATION_EXPORT NSArray<DXAppSearchMatch *> *DXAppSearch(NSArray<DXAppSearchEntry *> *entries,
    NSString *query, NSArray<NSString *> *favorites, NSDictionary *usage);
