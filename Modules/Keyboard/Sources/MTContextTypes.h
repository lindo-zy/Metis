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

// 应用动作组：一组 App 共用一批预留区动作。
//
// 读取时完成全部校验与去重：一个 App 只属于第一个声明它的组，非法 bundle id、
// 非法动作、重复 id、超限条目一律丢弃。设置页与判定层共用同一份结果，避免两处
// 规则漂移。应用组不参与「内容识别」（没有类型/绑定那一层），动作直接是选择器。
@interface MTContextAppGroup : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSArray<NSString *> *bundleIDs;
@property(nonatomic, copy) NSArray<NSString *> *actions;
@property(nonatomic, assign) BOOL enabled;
+ (NSArray<MTContextAppGroup *> *)groupsFromPreferences:(NSDictionary *)preferences;
+ (MTContextAppGroup *)groupForBundleID:(NSString *)bundleID inGroups:(NSArray<MTContextAppGroup *> *)groups;
+ (BOOL)isValidBundleID:(NSString *)bundleID;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface MTContextGroupConfig : NSObject
@property(nonatomic, copy, readonly) NSDictionary *preferences;
@property(nonatomic, copy, readonly) NSArray<MTContextAppGroup *> *appGroups;
+ (instancetype)configFromPreferences:(NSDictionary *)preferences;
+ (NSDictionary *)migratePreferences:(NSDictionary *)preferences;
- (NSArray<MTContextType *> *)typesForGroup:(NSString *)group;
- (NSUInteger)slotsForGroup:(NSString *)group;
- (NSDictionary *)dictionaryRepresentation;
@end
