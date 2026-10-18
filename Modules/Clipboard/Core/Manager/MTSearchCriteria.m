//
//  MTSearchCriteria.m
//  Mt
//

#import "MTSearchCriteria.h"

NSString *const kMTSearchTokenTypeCategory = @"category";
NSString *const kMTSearchTokenTypeApp = @"app";

NSString *const kMTSearchCategoryText = @"text";
NSString *const kMTSearchCategoryLink = @"link";
NSString *const kMTSearchCategoryPhone = @"phone";
NSString *const kMTSearchCategoryDate = @"date";
NSString *const kMTSearchCategoryAddress = @"address";
NSString *const kMTSearchCategoryFlight = @"flight";
NSString *const kMTSearchCategoryImage = @"image";

@implementation MTSearchToken

#pragma mark - Construction

+ (instancetype)tokenWithType:(NSString *)type
                        value:(NSString *)value
                        title:(NSString *)title
                    imageName:(nullable NSString *)imageName {
    return [[self alloc] initWithType:type value:value title:title imageName:imageName displaySignature:nil];
}

+ (instancetype)tokenWithType:(NSString *)type
                        value:(NSString *)value
                        title:(NSString *)title
                    imageName:(nullable NSString *)imageName
             displaySignature:(nullable NSString *)displaySignature {
    return [[self alloc] initWithType:type
                                value:value
                                title:title
                            imageName:imageName
                     displaySignature:displaySignature];
}

- (instancetype)initWithType:(NSString *)type
                       value:(NSString *)value
                       title:(NSString *)title
                   imageName:(nullable NSString *)imageName {
    return [self initWithType:type value:value title:title imageName:imageName displaySignature:nil];
}

- (instancetype)initWithType:(NSString *)type
                       value:(NSString *)value
                       title:(NSString *)title
                   imageName:(nullable NSString *)imageName
            displaySignature:(nullable NSString *)displaySignature {
    self = [super init];
    if (self) {
        _type = [type copy] ?: @"";
        _value = [value copy] ?: @"";
        _title = [title copy] ?: @"";
        _imageName = [imageName copy];
        _displaySignature = [displaySignature copy];
    }
    return self;
}

#pragma mark - Copying

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithType:[self type]
                                                     value:[self value]
                                                     title:[self title]
                                                 imageName:[self imageName]
                                          displaySignature:[self displaySignature]];
}

- (BOOL)isDisplayEqualToToken:(nullable MTSearchToken *)token {
    if (self == token) {
        return YES;
    }
    if (![token isKindOfClass:[MTSearchToken class]]) {
        return NO;
    }

    return [[self type] isEqualToString:[token type]] && [[self value] isEqualToString:[token value]] &&
           [[self title] isEqualToString:[token title]] &&
           [([self imageName] ?: @"") isEqualToString:([token imageName] ?: @"")] &&
           [([self displaySignature] ?: @"") isEqualToString:([token displaySignature] ?: @"")];
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[MTSearchToken class]]) {
        return NO;
    }

    MTSearchToken *token = object;
    return [[self type] isEqualToString:[token type]] && [[self value] isEqualToString:[token value]];
}

- (NSUInteger)hash {
    return [[self type] hash] ^ [[self value] hash];
}

@end

@implementation MTSearchCriteria

#pragma mark - Construction

+ (instancetype)emptyCriteria {
    return [[self alloc] initWithSearchText:nil categoryValue:nil appBundleIdentifier:nil];
}

+ (instancetype)criteriaWithSearchText:(nullable NSString *)searchText
                         categoryValue:(nullable NSString *)categoryValue
                   appBundleIdentifier:(nullable NSString *)appBundleIdentifier {
    return [[self alloc] initWithSearchText:searchText
                              categoryValue:categoryValue
                        appBundleIdentifier:appBundleIdentifier];
}

- (instancetype)initWithSearchText:(nullable NSString *)searchText
                     categoryValue:(nullable NSString *)categoryValue
               appBundleIdentifier:(nullable NSString *)appBundleIdentifier {
    self = [super init];
    if (self) {
        NSString *trimmedText =
            [(searchText ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        _searchText = [trimmedText copy];
        _categoryValue = [categoryValue length] > 0 ? [categoryValue copy] : nil;
        _appBundleIdentifier = [appBundleIdentifier length] > 0 ? [appBundleIdentifier copy] : nil;
    }
    return self;
}

#pragma mark - Copying

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithSearchText:[self searchText]
                                                   categoryValue:[self categoryValue]
                                             appBundleIdentifier:[self appBundleIdentifier]];
}

- (BOOL)hasCategoryToken {
    return [[self categoryValue] length] > 0;
}

- (BOOL)hasAppToken {
    return [[self appBundleIdentifier] length] > 0;
}

- (BOOL)hasSearchText {
    return [[self searchText] length] > 0;
}

- (BOOL)hasActiveFilters {
    return [self hasSearchText] || [self hasCategoryToken] || [self hasAppToken];
}

#pragma mark - Mutations

- (MTSearchCriteria *)criteriaByReplacingSearchText:(nullable NSString *)searchText {
    return [[MTSearchCriteria alloc] initWithSearchText:searchText
                                              categoryValue:[self categoryValue]
                                        appBundleIdentifier:[self appBundleIdentifier]];
}

- (MTSearchCriteria *)criteriaBySelectingToken:(MTSearchToken *)token {
    if ([[token type] isEqualToString:kMTSearchTokenTypeCategory]) {
        return [[MTSearchCriteria alloc] initWithSearchText:[self searchText]
                                                  categoryValue:[token value]
                                            appBundleIdentifier:[self appBundleIdentifier]];
    }
    if ([[token type] isEqualToString:kMTSearchTokenTypeApp]) {
        return [[MTSearchCriteria alloc] initWithSearchText:[self searchText]
                                                  categoryValue:[self categoryValue]
                                            appBundleIdentifier:[token value]];
    }
    return [self copy];
}

- (MTSearchCriteria *)criteriaByRemovingToken:(MTSearchToken *)token {
    NSString *categoryValue = [self categoryValue];
    NSString *appBundleIdentifier = [self appBundleIdentifier];
    if ([[token type] isEqualToString:kMTSearchTokenTypeCategory] &&
        [[token value] isEqualToString:categoryValue ?: @""]) {
        categoryValue = nil;
    } else if ([[token type] isEqualToString:kMTSearchTokenTypeApp] &&
               [[token value] isEqualToString:appBundleIdentifier ?: @""]) {
        appBundleIdentifier = nil;
    }

    return [[MTSearchCriteria alloc] initWithSearchText:[self searchText]
                                              categoryValue:categoryValue
                                        appBundleIdentifier:appBundleIdentifier];
}

#pragma mark - Equality

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[MTSearchCriteria class]]) {
        return NO;
    }
    return [self isEqualToCriteria:object];
}

- (BOOL)isEqualToCriteria:(MTSearchCriteria *)criteria {
    if (!criteria) {
        return NO;
    }

    return [[self searchText] isEqualToString:[criteria searchText]] &&
           [([self categoryValue] ?: @"") isEqualToString:([criteria categoryValue] ?: @"")] &&
           [([self appBundleIdentifier] ?: @"") isEqualToString:([criteria appBundleIdentifier] ?: @"")];
}

- (NSUInteger)hash {
    return [[self searchText] hash] ^ [[self categoryValue] hash] ^ [[self appBundleIdentifier] hash];
}

@end
