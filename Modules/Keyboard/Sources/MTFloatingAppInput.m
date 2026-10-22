#import "MTFloatingAppInput.h"
#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <notify.h>
#import <objc/message.h>
#include <unistd.h>
#include <string.h>

// Observes the first touch without recognizing or cancelling any gesture.
// Hosted content receives touches in its own app process, not SpringBoard.
@interface MTFloatTouchObserver : UIGestureRecognizer
@property(nonatomic, copy) void (^observedTouch)(void);
@end
@implementation MTFloatTouchObserver
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.observedTouch) self.observedTouch();
    self.state = UIGestureRecognizerStateFailed;
}
@end

@interface MTFloatingAppInputClient : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic) int sessionToken;
@property(nonatomic) int baseToken;
@property(nonatomic) int focusToken;
@property(nonatomic) int inputToken;
@property(nonatomic) int sceneToken;
@property(nonatomic) uint64_t sceneHash;
@property(nonatomic) uint32_t nonce;
@property(nonatomic) uint32_t gestureNonce;
@property(nonatomic) uint8_t gestureSerial;
@property(nonatomic) BOOL floatingTarget;
@property(nonatomic, strong) NSMapTable<UIWindow *, UIPinchGestureRecognizer *> *gestures;
@property(nonatomic, strong) NSMapTable<UIWindow *, MTFloatTouchObserver *> *touchObservers;
- (void)refresh;
@end

@implementation MTFloatingAppInputClient
- (instancetype)init {
    if ((self = [super init])) {
        _sessionToken = _baseToken = _focusToken = _inputToken = _sceneToken = NOTIFY_TOKEN_INVALID;
        _gestures = [NSMapTable weakToStrongObjectsMapTable];
        _touchObservers = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    for (NSNumber *token in @[@(_sessionToken), @(_baseToken), @(_focusToken), @(_inputToken), @(_sceneToken)])
        if (token.intValue != NOTIFY_TOKEN_INVALID) notify_cancel(token.intValue);
}
- (BOOL)matchesWindow:(UIWindow *)window {
    id scene = window.windowScene;
    SEL selector = NSSelectorFromString(@"_sceneIdentifier");
    NSMethodSignature *signature = [scene methodSignatureForSelector:selector];
    if (![scene respondsToSelector:selector] || signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, "@")) return NO;
    @try {
        id identifier = ((id (*)(id, SEL))objc_msgSend)(scene, selector);
        return self.sceneHash && MTFloatInputSceneHash(identifier) == self.sceneHash;
    } @catch (__unused NSException *exception) { return NO; }
}
- (BOOL)isCurrent {
    uint64_t target = 0, base = 0;
    if (!self.nonce || self.sessionToken == NOTIFY_TOKEN_INVALID ||
        notify_get_state(self.sessionToken, &target) != NOTIFY_STATUS_OK ||
        (uint32_t)(target >> 32) != self.nonce) return NO;
    if (self.floatingTarget) return (uint32_t)target == (uint32_t)getpid();
    return self.baseToken != NOTIFY_TOKEN_INVALID && notify_get_state(self.baseToken, &base) == NOTIFY_STATUS_OK &&
        base == MTFloatInputSessionWord((uint32_t)getpid(), self.nonce);
}
- (BOOL)ownsFocus {
    uint64_t word = 0;
    return [self isCurrent] && self.focusToken != NOTIFY_TOKEN_INVALID &&
        notify_get_state(self.focusToken, &word) == NOTIFY_STATUS_OK &&
        word == MTFloatInputSessionWord((uint32_t)getpid(), self.nonce);
}
- (void)focusChanged {
    if (![self isCurrent]) return;
    uint64_t focus = 0;
    if (self.focusToken == NOTIFY_TOKEN_INVALID || notify_get_state(self.focusToken, &focus) != NOTIFY_STATUS_OK ||
        (uint32_t)(focus >> 32) != self.nonce || (uint32_t)focus == (uint32_t)getpid()) return;
    // Leave the other app running and visible; relinquish only text input.
    for (UIWindow *window in self.touchObservers.keyEnumerator.allObjects)
        if ([self matchesWindow:window]) [window endEditing:YES];
}
- (void)observedTouchInWindow:(UIWindow *)window {
    if (![self isCurrent] || ![self matchesWindow:window] || [self ownsFocus]) return;
    if (notify_set_state(self.focusToken, MTFloatInputSessionWord((uint32_t)getpid(), self.nonce)) == NOTIFY_STATUS_OK) {
        notify_post(MTFloatInputFocusName.UTF8String);
        NSLog(@"[MetisKeyboard][FloatingApp] input focus role=%@", self.floatingTarget ? @"floating" : @"base");
    }
}
- (void)clearLocalSession {
    self.nonce = 0; self.gestureNonce = 0; self.sceneHash = 0;
    for (UIWindow *window in self.gestures.keyEnumerator) [window removeGestureRecognizer:[self.gestures objectForKey:window]];
    for (UIWindow *window in self.touchObservers.keyEnumerator) [window removeGestureRecognizer:[self.touchObservers objectForKey:window]];
    [self.gestures removeAllObjects]; [self.touchObservers removeAllObjects];
    for (NSNumber *token in @[@(self.inputToken), @(self.sceneToken)])
        if (token.intValue != NOTIFY_TOKEN_INVALID) notify_cancel(token.intValue);
    self.inputToken = self.sceneToken = NOTIFY_TOKEN_INVALID;
}
- (void)refresh {
    uint64_t target = 0, base = 0;
    if (self.sessionToken != NOTIFY_TOKEN_INVALID) notify_get_state(self.sessionToken, &target);
    if (self.baseToken != NOTIFY_TOKEN_INVALID) notify_get_state(self.baseToken, &base);
    BOOL floating = (uint32_t)target == (uint32_t)getpid();
    uint32_t nonce = floating ? (uint32_t)(target >> 32) :
        ((uint32_t)base == (uint32_t)getpid() && (uint32_t)(base >> 32) == (uint32_t)(target >> 32) ? (uint32_t)(base >> 32) : 0);
    if (nonce != self.nonce || floating != self.floatingTarget) {
        [self clearLocalSession]; self.floatingTarget = floating;
        if (nonce && notify_register_check(MTFloatInputSceneName((uint32_t)getpid()).UTF8String, &_sceneToken) == NOTIFY_STATUS_OK &&
            notify_get_state(self.sceneToken, &_sceneHash) == NOTIFY_STATUS_OK && self.sceneHash &&
            (!floating || notify_register_check(MTFloatInputName((uint32_t)getpid()).UTF8String, &_inputToken) == NOTIFY_STATUS_OK)) self.nonce = nonce;
        if (!self.nonce) [self clearLocalSession];
    }
    if (![self isCurrent]) return;
    NSUInteger installed = 0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || ![scene.session.role isEqual:UIWindowSceneSessionRoleApplication]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || ![self matchesWindow:window]) continue;
            if (![self.touchObservers objectForKey:window]) {
                MTFloatTouchObserver *observer = [MTFloatTouchObserver new];
                observer.cancelsTouchesInView = NO; observer.delaysTouchesBegan = NO; observer.delaysTouchesEnded = NO;
                __weak typeof(self) weakSelf = self;
                __weak UIWindow *weakWindow = window;
                observer.observedTouch = ^{ [weakSelf observedTouchInWindow:weakWindow]; };
                [window addGestureRecognizer:observer]; [self.touchObservers setObject:observer forKey:window];
                installed++;
            }
            if (!floating || [self.gestures objectForKey:window]) continue;
            UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
            pinch.delegate = self; [window addGestureRecognizer:pinch]; [self.gestures setObject:pinch forKey:window];
        }
    }
    if (installed) NSLog(@"[MetisKeyboard][FloatingApp] input observed role=%@ windows=%lu",
        floating ? @"floating" : @"base", (unsigned long)installed);
    [self focusChanged];
}
- (void)windowVisible:(__unused NSNotification *)notification { [self refresh]; }
- (BOOL)gestureRecognizer:(__unused UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    return self.floatingTarget && [self isCurrent] && [self matchesWindow:touch.window];
}
- (BOOL)gestureRecognizer:(__unused UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return ![other isKindOfClass:UIPinchGestureRecognizer.class];
}
- (BOOL)gestureRecognizer:(__unused UIGestureRecognizer *)gesture shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    return [self isCurrent] && [other isKindOfClass:UIPinchGestureRecognizer.class];
}
- (void)pinch:(UIPinchGestureRecognizer *)gesture {
    if (!self.floatingTarget || ![self isCurrent] || self.inputToken == NOTIFY_TOKEN_INVALID) return;
    MTFloatPinchPhase phase;
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            self.gestureSerial++; if (!self.gestureSerial) self.gestureSerial = 1;
            self.gestureNonce = self.nonce; phase = MTFloatPinchBegan; break;
        case UIGestureRecognizerStateChanged: phase = MTFloatPinchChanged; break;
        case UIGestureRecognizerStateEnded: phase = MTFloatPinchEnded; break;
        case UIGestureRecognizerStateCancelled: phase = MTFloatPinchCancelled; break;
        default: return;
    }
    if (self.gestureNonce != self.nonce) return;
    uint64_t word = MTFloatPinchWord(self.nonce, self.gestureSerial, phase, gesture.scale);
    if (word && notify_set_state(self.inputToken, word) == NOTIFY_STATUS_OK)
        notify_post(MTFloatInputName((uint32_t)getpid()).UTF8String);
}
@end

void MTStartFloatingAppInputClient(void) {
    if ([NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"] ||
        ![NSBundle.mainBundle.bundleURL.pathExtension.lowercaseString isEqual:@"app"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        static MTFloatingAppInputClient *client;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            client = [MTFloatingAppInputClient new];
            __weak MTFloatingAppInputClient *weakClient = client;
            int base = NOTIFY_TOKEN_INVALID;
            if (notify_register_check(MTFloatInputBaseName.UTF8String, &base) != NOTIFY_STATUS_OK) { client = nil; return; }
            client.baseToken = base;
            int focus = NOTIFY_TOKEN_INVALID;
            if (notify_register_dispatch(MTFloatInputFocusName.UTF8String, &focus, dispatch_get_main_queue(),
                ^(__unused int token) { [weakClient focusChanged]; }) != NOTIFY_STATUS_OK) { client = nil; return; }
            client.focusToken = focus;
            int token = NOTIFY_TOKEN_INVALID;
            if (notify_register_dispatch(MTFloatInputSessionName.UTF8String, &token, dispatch_get_main_queue(),
                ^(__unused int event) { [weakClient refresh]; }) != NOTIFY_STATUS_OK) { client = nil; return; }
            client.sessionToken = token;
            for (NSString *name in @[UIWindowDidBecomeVisibleNotification, UISceneDidActivateNotification])
                [NSNotificationCenter.defaultCenter addObserver:client selector:@selector(windowVisible:) name:name object:nil];
            [client refresh];
        });
    });
}
