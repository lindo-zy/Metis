//
//  MTKeyboardHostResolver.m
//  Mt
//

#import "MTKeyboardHostResolver.h"
#import "MTSceneSettingKeys.h"

#import <HBLog.h>
#import <objc/runtime.h>

static NSString *const kMTSpotlightSceneIdentifier = @"searchScreen";
static NSString *const kMTSpotlightBundleIdentifier = @"com.apple.Spotlight";
static NSString *const kMTSpringBoardBundleIdentifier = @"com.apple.springboard";
static NSString *const kMTSpringBoardProcessName = @"SpringBoard";

@class BSSettings;
@class FBSSceneIdentityToken;

@interface BSSettings : NSObject
- (long long)flagForSetting:(unsigned long long)setting;
@end

@interface FBSSceneClientSettings : NSObject
- (BSSettings *)otherSettings;
- (FBSSceneIdentityToken *)preferredSceneHostIdentity;
@end

@interface FBSSceneIdentityToken : NSObject
- (NSString *)identifier;
@end

@interface FBProcess : NSObject
- (NSString *)bundleIdentifier;
- (NSString *)name;
@end

@interface FBScene : NSObject
- (FBSSceneClientSettings *)clientSettings;
- (FBProcess *)clientProcess;
- (UIApplicationSceneSettings *)settings;
- (NSString *)identifier;
@end

@interface FBSceneManager : NSObject
+ (FBScene *)keyboardScene;
+ (instancetype)sharedInstance;
- (FBScene *)sceneWithIdentifier:(NSString *)identifier;
@end

@protocol MTFBSceneManagerClass <NSObject>
+ (FBScene *)keyboardScene;
+ (FBSceneManager *)sharedInstance;
@end

@interface UIKeyboardImpl : NSObject
+ (instancetype)activeInstance;
- (id)inputDelegate;
@end

@protocol MTUIKeyboardImplClass <NSObject>
+ (UIKeyboardImpl *)activeInstance;
@end

NS_ASSUME_NONNULL_BEGIN

@interface MTKeyboardHostContext ()

#pragma mark - Scene

@property(nonatomic, weak, readwrite, nullable) FBScene *scene;
@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite, nullable) NSString *bundleIdentifier;
@property(nonatomic, assign, readwrite) MTKeyboardHostKind kind;

#pragma mark - Helper Marker

@property(nonatomic, assign, readwrite) BOOL helperMarkerAvailable;
@property(nonatomic, assign, readwrite) long long helperInjectedFlag;

#pragma mark - State

@property(nonatomic, assign, readwrite, getter=isMtOwned) BOOL mtOwned;
@property(nonatomic, assign, readwrite, getter=isCached) BOOL cached;

#pragma mark - Lifecycle

- (instancetype)initWithScene:(nullable FBScene *)scene
                   identifier:(NSString *)identifier
             bundleIdentifier:(nullable NSString *)bundleIdentifier
                         kind:(MTKeyboardHostKind)kind NS_DESIGNATED_INITIALIZER;

#pragma mark - State

- (MTKeyboardHostContext *)contextMarkedCached;

@end

@interface MTKeyboardHostResolver ()

#pragma mark - Cache

@property(nonatomic, strong, nullable) MTKeyboardHostContext *lastExternalKeyboardHostContext;

#pragma mark - Lifecycle

- (instancetype)initPrivate;

#pragma mark - Host Context

- (nullable MTKeyboardHostContext *)keyboardHostContextForCurrentInputMtOwned:(BOOL)mtOwned;
- (nullable MTKeyboardHostContext *)keyboardHostContextForScene:(FBScene *)hostScene
                                                         identifier:(NSString *)identifier
                                                        mtOwned:(BOOL)mtOwned
                                                             cached:(BOOL)cached;
- (nullable FBScene *)keyboardHostSceneWithIdentifier:(NSString *_Nullable *_Nullable)identifier;
- (nullable NSString *)bundleIdentifierForScene:(FBScene *)scene kind:(MTKeyboardHostKind)kind;
- (nullable UIResponder *)activeKeyboardInputDelegate;

#pragma mark - Ownership

- (BOOL)objectHasMtClassPrefix:(id)object;
- (BOOL)viewHierarchyIsMtOwned:(UIView *)view;
- (BOOL)responderIsMtOwned:(UIResponder *)responder;

#pragma mark - Scene Classification

- (BOOL)stringMatchesSpringBoard:(NSString *)string;
- (MTKeyboardHostKind)kindForScene:(FBScene *)scene;

@end

NS_ASSUME_NONNULL_END

@implementation MTKeyboardHostContext

#pragma mark - Lifecycle

- (instancetype)initWithScene:(nullable FBScene *)scene
                   identifier:(NSString *)identifier
             bundleIdentifier:(nullable NSString *)bundleIdentifier
                         kind:(MTKeyboardHostKind)kind {
    self = [super init];
    if (self) {
        _scene = scene;
        _identifier = [identifier copy] ?: @"";
        _bundleIdentifier = [bundleIdentifier copy];
        _kind = kind;
    }
    return self;
}

#pragma mark - State

- (BOOL)isHelperInjected {
    return self.helperInjectedFlag == 1;
}

- (MTKeyboardHostContext *)contextMarkedCached {
    MTKeyboardHostContext *context = [[MTKeyboardHostContext alloc] initWithScene:self.scene
                                                                               identifier:self.identifier
                                                                         bundleIdentifier:self.bundleIdentifier
                                                                                     kind:self.kind];
    context.helperMarkerAvailable = self.helperMarkerAvailable;
    context.helperInjectedFlag = self.helperInjectedFlag;
    context.mtOwned = self.mtOwned;
    context.cached = YES;
    return context;
}

@end

@implementation MTKeyboardHostResolver

#pragma mark - Lifecycle

+ (instancetype)sharedResolver {
    static MTKeyboardHostResolver *resolver;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      resolver = [[self alloc] initPrivate];
    });
    return resolver;
}

+ (NSString *)stringForHostKind:(MTKeyboardHostKind)kind {
    switch (kind) {
    case MTKeyboardHostKindApplication:
        return @"application";
    case MTKeyboardHostKindSpringBoard:
        return @"springboard";
    case MTKeyboardHostKindSpotlight:
        return @"spotlight";
    case MTKeyboardHostKindUnknown:
    default:
        return @"unknown";
    }
}

- (instancetype)initPrivate {
    self = [super init];
    return self;
}

#pragma mark - Public Context

- (MTKeyboardHostContext *)currentKeyboardHostContext {
    return [self keyboardHostContextForCurrentInputMtOwned:[self currentKeyboardInputIsMtOwned]];
}

- (MTKeyboardHostContext *)effectiveExternalKeyboardHostContext {
    BOOL mtOwned = [self currentKeyboardInputIsMtOwned];
    MTKeyboardHostContext *currentContext = [self keyboardHostContextForCurrentInputMtOwned:mtOwned];
    if (currentContext && !currentContext.isMtOwned) {
        return currentContext;
    }

    MTKeyboardHostContext *cachedContext = [self.lastExternalKeyboardHostContext contextMarkedCached];
    if (cachedContext) {
        HBLogDebug(@"Mt: keyboard host resolver using cached external host because current input is %@ "
                   @"currentScene=%@ cachedScene=%@ cachedKind=%@ helperFlag=%lld",
                   mtOwned ? @"Mt-owned" : @"unavailable", currentContext.identifier ?: @"nil",
                   cachedContext.identifier, [[self class] stringForHostKind:cachedContext.kind],
                   cachedContext.helperInjectedFlag);
    } else {
        HBLogDebug(@"Mt: keyboard host resolver has %@ input but no cached external host "
                   @"currentScene=%@",
                   mtOwned ? @"Mt-owned" : @"unavailable", currentContext.identifier ?: @"nil");
    }
    return cachedContext;
}

- (MTKeyboardHostContext *)keyboardHostContextForSourceAttribution {
    BOOL mtOwned = [self currentKeyboardInputIsMtOwned];
    MTKeyboardHostContext *currentContext = [self keyboardHostContextForCurrentInputMtOwned:mtOwned];
    if (currentContext && !currentContext.isMtOwned) {
        return currentContext;
    }

    MTKeyboardHostContext *cachedContext = [self.lastExternalKeyboardHostContext contextMarkedCached];
    if (mtOwned) {
        if (cachedContext) {
            HBLogDebug(@"Mt: keyboard host resolver using cached external host for source attribution because "
                       @"current input is Mt-owned currentScene=%@ cachedScene=%@ cachedKind=%@ helperFlag=%lld",
                       currentContext.identifier ?: @"nil", cachedContext.identifier,
                       [[self class] stringForHostKind:cachedContext.kind], cachedContext.helperInjectedFlag);
        } else {
            HBLogDebug(@"Mt: keyboard host resolver has Mt-owned input but no cached external host for "
                       @"source attribution currentScene=%@",
                       currentContext.identifier ?: @"nil");
        }
        return cachedContext;
    }

    if (cachedContext) {
        HBLogDebug(@"Mt: keyboard host resolver ignoring cached external host for source attribution because "
                   @"current input is unavailable currentScene=%@ cachedScene=%@ cachedKind=%@",
                   currentContext.identifier ?: @"nil", cachedContext.identifier,
                   [[self class] stringForHostKind:cachedContext.kind]);
    } else {
        HBLogDebug(@"Mt: keyboard host resolver has unavailable input and no current keyboard host for "
                   @"source attribution currentScene=%@",
                   currentContext.identifier ?: @"nil");
    }
    return nil;
}

- (FBScene *)currentKeyboardHostScene {
    return [[self currentKeyboardHostContext] scene];
}

#pragma mark - Scene Helpers

- (UIApplicationSceneSettings *)settingsForScene:(FBScene *)scene {
    if (![scene respondsToSelector:@selector(settings)]) {
        return nil;
    }
    return [scene settings];
}

- (BOOL)sceneIsCurrentKeyboardHostScene:(FBScene *)scene {
    if (!scene) {
        return NO;
    }
    return scene == [self currentKeyboardHostScene];
}

- (BOOL)sceneIsHostedBySpringBoard:(FBScene *)scene {
    if (!scene) {
        return NO;
    }

    if ([scene respondsToSelector:@selector(identifier)] && [self stringMatchesSpringBoard:[scene identifier]]) {
        return YES;
    }

    if (![scene respondsToSelector:@selector(clientProcess)]) {
        return NO;
    }

    FBProcess *process = [scene clientProcess];
    if ([process respondsToSelector:@selector(bundleIdentifier)] &&
        [self stringMatchesSpringBoard:[process bundleIdentifier]]) {
        return YES;
    }
    return [process respondsToSelector:@selector(name)] && [self stringMatchesSpringBoard:[process name]];
}

- (BOOL)sceneIsSpotlightScene:(FBScene *)scene {
    if (![scene respondsToSelector:@selector(identifier)]) {
        return NO;
    }
    return [[scene identifier] isEqualToString:kMTSpotlightSceneIdentifier];
}

#pragma mark - Host Context

- (BOOL)currentKeyboardInputIsMtOwned {
    UIResponder *keyboardInputDelegate = [self activeKeyboardInputDelegate];
    return [self responderIsMtOwned:keyboardInputDelegate];
}

- (MTKeyboardHostContext *)keyboardHostContextForCurrentInputMtOwned:(BOOL)mtOwned {
    NSString *hostSceneIdentifier = nil;
    FBScene *hostScene = [self keyboardHostSceneWithIdentifier:&hostSceneIdentifier];
    if (!hostScene || [hostSceneIdentifier length] == 0) {
        return nil;
    }

    MTKeyboardHostContext *context = [self keyboardHostContextForScene:hostScene
                                                                identifier:hostSceneIdentifier
                                                               mtOwned:mtOwned
                                                                    cached:NO];
    if (context && !mtOwned) {
        self.lastExternalKeyboardHostContext = context;
    }
    return context;
}

- (MTKeyboardHostContext *)keyboardHostContextForScene:(FBScene *)hostScene
                                                identifier:(NSString *)identifier
                                               mtOwned:(BOOL)mtOwned
                                                    cached:(BOOL)cached {
    BOOL helperMarkerAvailable = NO;
    long long helperInjectedFlag = 0;

    if ([hostScene respondsToSelector:@selector(clientSettings)]) {
        FBSSceneClientSettings *hostClientSettings = [hostScene clientSettings];
        if ([hostClientSettings respondsToSelector:@selector(otherSettings)]) {
            BSSettings *otherSettings = [hostClientSettings otherSettings];
            if ([otherSettings respondsToSelector:@selector(flagForSetting:)]) {
                helperMarkerAvailable = YES;
                helperInjectedFlag = [otherSettings flagForSetting:kMTSceneClientSettingHelperInjected];
            }
        }
    }

    MTKeyboardHostKind kind = [self kindForScene:hostScene];
    MTKeyboardHostContext *context =
        [[MTKeyboardHostContext alloc] initWithScene:hostScene
                                              identifier:identifier
                                        bundleIdentifier:[self bundleIdentifierForScene:hostScene kind:kind]
                                                    kind:kind];
    context.helperMarkerAvailable = helperMarkerAvailable;
    context.helperInjectedFlag = helperInjectedFlag;
    context.mtOwned = mtOwned;
    context.cached = cached;
    return context;
}

- (FBScene *)keyboardHostSceneWithIdentifier:(NSString **)identifier {
    Class<MTFBSceneManagerClass> managerClass =
        (Class<MTFBSceneManagerClass>)NSClassFromString(@"FBSceneManager");
    if (![managerClass respondsToSelector:@selector(keyboardScene)] ||
        ![managerClass respondsToSelector:@selector(sharedInstance)]) {
        return nil;
    }

    FBScene *keyboardScene = [managerClass keyboardScene];
    FBSceneManager *sceneManager = [managerClass sharedInstance];
    if (![keyboardScene respondsToSelector:@selector(clientSettings)] ||
        ![sceneManager respondsToSelector:@selector(sceneWithIdentifier:)]) {
        return nil;
    }

    FBSSceneClientSettings *keyboardClientSettings = [keyboardScene clientSettings];
    if (![keyboardClientSettings respondsToSelector:@selector(preferredSceneHostIdentity)]) {
        return nil;
    }

    FBSSceneIdentityToken *hostIdentity = [keyboardClientSettings preferredSceneHostIdentity];
    if (![hostIdentity respondsToSelector:@selector(identifier)]) {
        return nil;
    }

    NSString *hostSceneIdentifier = [hostIdentity identifier];
    if (![hostSceneIdentifier isKindOfClass:[NSString class]] || [hostSceneIdentifier length] == 0) {
        return nil;
    }

    if (identifier) {
        *identifier = hostSceneIdentifier;
    }
    return [sceneManager sceneWithIdentifier:hostSceneIdentifier];
}

- (nullable NSString *)bundleIdentifierForScene:(FBScene *)scene kind:(MTKeyboardHostKind)kind {
    if (kind == MTKeyboardHostKindSpotlight) {
        return kMTSpotlightBundleIdentifier;
    }
    if (kind == MTKeyboardHostKindSpringBoard) {
        return kMTSpringBoardBundleIdentifier;
    }

    if (![scene respondsToSelector:@selector(clientProcess)]) {
        return nil;
    }

    FBProcess *process = [scene clientProcess];
    if (![process respondsToSelector:@selector(bundleIdentifier)]) {
        return nil;
    }

    NSString *bundleIdentifier = [process bundleIdentifier];
    return [bundleIdentifier length] > 0 ? bundleIdentifier : nil;
}

- (UIResponder *)activeKeyboardInputDelegate {
    Class<MTUIKeyboardImplClass> keyboardImplClass =
        (Class<MTUIKeyboardImplClass>)NSClassFromString(@"UIKeyboardImpl");
    if (![keyboardImplClass respondsToSelector:@selector(activeInstance)]) {
        return nil;
    }

    UIKeyboardImpl *keyboardImpl = [keyboardImplClass activeInstance];
    if (![keyboardImpl respondsToSelector:@selector(inputDelegate)]) {
        return nil;
    }

    id inputDelegate = [keyboardImpl inputDelegate];
    return [inputDelegate isKindOfClass:[UIResponder class]] ? inputDelegate : nil;
}

#pragma mark - Ownership

- (BOOL)objectHasMtClassPrefix:(id)object {
    if (!object) {
        return NO;
    }

    Class cls = [object class];
    while (cls) {
        if ([NSStringFromClass(cls) hasPrefix:@"MT"]) {
            return YES;
        }
        cls = class_getSuperclass(cls);
    }
    return NO;
}

- (BOOL)viewHierarchyIsMtOwned:(UIView *)view {
    NSUInteger depth = 0;
    while (view && depth < 64) {
        if ([self objectHasMtClassPrefix:view]) {
            return YES;
        }
        view = [view superview];
        depth++;
    }
    return NO;
}

- (BOOL)responderIsMtOwned:(UIResponder *)responder {
    UIResponder *currentResponder = responder;
    NSUInteger depth = 0;
    while (currentResponder && depth < 64) {
        if ([self objectHasMtClassPrefix:currentResponder]) {
            return YES;
        }
        if ([currentResponder isKindOfClass:[UIView class]] &&
            [self viewHierarchyIsMtOwned:[(UIView *)currentResponder superview]]) {
            return YES;
        }
        currentResponder = [currentResponder nextResponder];
        depth++;
    }
    return NO;
}

#pragma mark - Scene Classification

- (BOOL)stringMatchesSpringBoard:(NSString *)string {
    if (![string isKindOfClass:[NSString class]] || [string length] == 0) {
        return NO;
    }

    return [string caseInsensitiveCompare:kMTSpringBoardBundleIdentifier] == NSOrderedSame ||
           [string caseInsensitiveCompare:kMTSpringBoardProcessName] == NSOrderedSame;
}

- (MTKeyboardHostKind)kindForScene:(FBScene *)scene {
    if ([self sceneIsSpotlightScene:scene]) {
        return MTKeyboardHostKindSpotlight;
    }
    if ([self sceneIsHostedBySpringBoard:scene]) {
        return MTKeyboardHostKindSpringBoard;
    }
    return scene ? MTKeyboardHostKindApplication : MTKeyboardHostKindUnknown;
}

@end
