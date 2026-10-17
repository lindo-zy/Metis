#import <Foundation/Foundation.h>

@interface MTAppSearchEntry : NSObject
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSArray<NSString *> *terms;
+ (instancetype)entryWithIdentifier:(NSString *)identifier name:(NSString *)name aliases:(NSArray *)aliases;
@end

@interface MTAppSearchMatch : NSObject
@property(nonatomic, strong) MTAppSearchEntry *entry;
@property(nonatomic) NSInteger quality; // 0 exact, 1 prefix, 2 substring, 3 adjacent-key typo
@end

FOUNDATION_EXPORT NSString *MTAppSearchNormalize(NSString *text);
FOUNDATION_EXPORT NSArray<MTAppSearchMatch *> *MTAppSearch(NSArray<MTAppSearchEntry *> *entries,
    NSString *query, NSArray<NSString *> *favorites, NSDictionary *usage);
