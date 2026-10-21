#pragma once
#import "MTContextGroupTypes.h"
#import "MTContextGroupPreferences.h"

FOUNDATION_EXPORT NSString *MTContextCanonicalGroup(NSString *key);
FOUNDATION_EXPORT NSArray<NSString *> *MTContextGroupKeys(void);
FOUNDATION_EXPORT BOOL MTContextActionAllowed(NSString *action, NSDictionary *preferences);
FOUNDATION_EXPORT NSString *MTContextTypeTitle(NSString *identifier);

@interface MTContextType : NSObject
@property(nonatomic, copy) NSString *kind;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, assign) BOOL enabled;
@property(nonatomic, copy) NSString *source;
@property(nonatomic, copy) NSArray<NSString *> *actions;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface MTContextGroupConfig : NSObject
@property(nonatomic, copy, readonly) NSDictionary *preferences;
+ (instancetype)configFromPreferences:(NSDictionary *)preferences;
+ (NSDictionary *)migratePreferences:(NSDictionary *)preferences;
- (NSArray<MTContextType *> *)typesForGroup:(NSString *)group;
- (NSUInteger)slotsForGroup:(NSString *)group;
- (NSDictionary *)dictionaryRepresentation;
@end
