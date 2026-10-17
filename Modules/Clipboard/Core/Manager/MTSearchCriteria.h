//
//  MTSearchCriteria.h
//  Mt
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kMTSearchTokenTypeCategory;
extern NSString *const kMTSearchTokenTypeApp;
extern NSString *const kMTSearchTokenTypeTag;

extern NSString *const kMTSearchCategoryText;
extern NSString *const kMTSearchCategoryLink;
extern NSString *const kMTSearchCategoryPhone;
extern NSString *const kMTSearchCategoryDate;
extern NSString *const kMTSearchCategoryAddress;
extern NSString *const kMTSearchCategoryFlight;
extern NSString *const kMTSearchCategoryImage;

@interface MTSearchToken : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSString *type;
@property(nonatomic, copy, readonly) NSString *value;
@property(nonatomic, copy, readonly) NSString *title;
@property(nonatomic, copy, readonly, nullable) NSString *imageName;
@property(nonatomic, copy, readonly, nullable) NSString *displaySignature;

+ (instancetype)tokenWithType:(NSString *)type
                        value:(NSString *)value
                        title:(NSString *)title
                    imageName:(nullable NSString *)imageName;
+ (instancetype)tokenWithType:(NSString *)type
                        value:(NSString *)value
                        title:(NSString *)title
                    imageName:(nullable NSString *)imageName
             displaySignature:(nullable NSString *)displaySignature;
- (instancetype)initWithType:(NSString *)type
                       value:(NSString *)value
                       title:(NSString *)title
                   imageName:(nullable NSString *)imageName;
- (instancetype)initWithType:(NSString *)type
                       value:(NSString *)value
                       title:(NSString *)title
                   imageName:(nullable NSString *)imageName
            displaySignature:(nullable NSString *)displaySignature NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (BOOL)isDisplayEqualToToken:(nullable MTSearchToken *)token;

@end

@interface MTSearchCriteria : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSString *searchText;
@property(nonatomic, copy, readonly, nullable) NSString *categoryValue;
@property(nonatomic, copy, readonly, nullable) NSString *appBundleIdentifier;
@property(nonatomic, copy, readonly, nullable) NSString *tagUUID;
@property(nonatomic, assign, readonly) BOOL hasCategoryToken;
@property(nonatomic, assign, readonly) BOOL hasAppToken;
@property(nonatomic, assign, readonly) BOOL hasTagToken;
@property(nonatomic, assign, readonly) BOOL hasSearchText;
@property(nonatomic, assign, readonly) BOOL hasActiveFilters;

+ (instancetype)emptyCriteria;
+ (instancetype)criteriaWithSearchText:(nullable NSString *)searchText
                         categoryValue:(nullable NSString *)categoryValue
                   appBundleIdentifier:(nullable NSString *)appBundleIdentifier
                               tagUUID:(nullable NSString *)tagUUID;

- (instancetype)initWithSearchText:(nullable NSString *)searchText
                     categoryValue:(nullable NSString *)categoryValue
               appBundleIdentifier:(nullable NSString *)appBundleIdentifier
                           tagUUID:(nullable NSString *)tagUUID NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (MTSearchCriteria *)criteriaByReplacingSearchText:(nullable NSString *)searchText;
- (MTSearchCriteria *)criteriaBySelectingToken:(MTSearchToken *)token;
- (MTSearchCriteria *)criteriaByRemovingToken:(MTSearchToken *)token;
- (BOOL)isEqualToCriteria:(nullable MTSearchCriteria *)criteria;

@end

NS_ASSUME_NONNULL_END
