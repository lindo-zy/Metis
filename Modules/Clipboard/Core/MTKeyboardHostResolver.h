#import <UIKit/UIKit.h>

@class FBScene;
@class UIApplicationSceneSettings;

typedef NS_ENUM(NSUInteger, MTKeyboardHostKind) {
    MTKeyboardHostKindUnknown = 0,
    MTKeyboardHostKindApplication,
    MTKeyboardHostKindSpringBoard,
    MTKeyboardHostKindSpotlight
};

NS_ASSUME_NONNULL_BEGIN

@interface MTKeyboardHostContext : NSObject

@property(nonatomic, weak, readonly, nullable) FBScene *scene;
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly, nullable) NSString *bundleIdentifier;
@property(nonatomic, assign, readonly) MTKeyboardHostKind kind;
@property(nonatomic, assign, readonly) BOOL helperMarkerAvailable;
@property(nonatomic, assign, readonly) long long helperInjectedFlag;
@property(nonatomic, assign, readonly, getter=isHelperInjected) BOOL helperInjected;
@property(nonatomic, assign, readonly, getter=isMtOwned) BOOL mtOwned;
@property(nonatomic, assign, readonly, getter=isCached) BOOL cached;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MTKeyboardHostResolver : NSObject

+ (instancetype)sharedResolver;
+ (NSString *)stringForHostKind:(MTKeyboardHostKind)kind;

- (nullable MTKeyboardHostContext *)currentKeyboardHostContext;
- (nullable MTKeyboardHostContext *)effectiveExternalKeyboardHostContext;
- (nullable MTKeyboardHostContext *)keyboardHostContextForSourceAttribution;
- (nullable FBScene *)currentKeyboardHostScene;
- (nullable UIApplicationSceneSettings *)settingsForScene:(FBScene *)scene;
- (BOOL)sceneIsCurrentKeyboardHostScene:(FBScene *)scene;
- (BOOL)sceneIsHostedBySpringBoard:(FBScene *)scene;
- (BOOL)sceneIsSpotlightScene:(FBScene *)scene;
- (BOOL)currentKeyboardInputIsMtOwned;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
