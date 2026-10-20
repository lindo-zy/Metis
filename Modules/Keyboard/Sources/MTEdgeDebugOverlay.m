#import "MTEdgeDebugOverlay.h"
#import "MTEdgeGesturePolicy.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <string.h>

// A nil UIKit hitTest alone does not guarantee passthrough to another process.
// Exclude the visual layers from WindowServer hit testing as well. If this
// contract is unavailable, leave the overlay hidden rather than capture taps.
static BOOL MTEdgeDisableLayerHitTesting(id layer) {
    SEL setter = NSSelectorFromString(@"setAllowsHitTesting:"), getter = NSSelectorFromString(@"allowsHitTesting");
    NSMethodSignature *write = [layer methodSignatureForSelector:setter], *read = [layer methodSignatureForSelector:getter];
    if (![layer respondsToSelector:setter] || ![layer respondsToSelector:getter] ||
        write.numberOfArguments != 3 || read.numberOfArguments != 2 || strcmp(write.methodReturnType, "v")) return NO;
    const char *argument = [write getArgumentTypeAtIndex:2], *result = read.methodReturnType;
    if ((strcmp(argument, "B") && strcmp(argument, "c")) || (strcmp(result, "B") && strcmp(result, "c"))) return NO;
    @try {
        ((void (*)(id, SEL, bool))objc_msgSend)(layer, setter, false);
        return !((bool (*)(id, SEL))objc_msgSend)(layer, getter);
    } @catch (__unused NSException *exception) { return NO; }
}

@interface MTEdgeDebugWindow : UIWindow
@end
@implementation MTEdgeDebugWindow
- (BOOL)_canBecomeKeyWindow { return NO; }
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
@end

static MTEdgeDebugWindow *MTEdgeDebugWindowInstance;
static CAShapeLayer *MTEdgeDebugLayer;
static NSDictionary *MTEdgeDebugPreferences;
static NSArray<NSString *> *MTEdgeDebugSlots;
static NSInteger MTEdgeDebugOrientation;
static void MTRenderEdgeDebugRegions(void);

@interface MTEdgeDebugController : UIViewController
@end
@implementation MTEdgeDebugController
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    MTRenderEdgeDebugRegions();
}
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

static void MTRenderEdgeDebugRegions(void) {
    UIView *view = MTEdgeDebugWindowInstance.rootViewController.view;
    if (!view || !MTEdgeDebugLayer) return;
    UIScreen *screen = UIScreen.mainScreen;
    CGSize fixedSize = screen.fixedCoordinateSpace.bounds.size;
    BOOL landscape = MTEdgeDebugOrientation == 3 || MTEdgeDebugOrientation == 4;
    double width = landscape ? fixedSize.height : fixedSize.width;
    double height = landscape ? fixedSize.width : fixedSize.height;
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSString *slot in MTEdgeDebugSlots) {
        MTEdgeRegion region = MTEdgeGestureRegion(MTEdgeGestureRange(MTEdgeDebugPreferences, slot), slot, width, height);
        MTEdgeRegion fixed = MTEdgeRegionToFixed(region, fixedSize.width, fixedSize.height, MTEdgeDebugOrientation);
        CGRect frame = [view convertRect:CGRectMake(fixed.x, fixed.y, fixed.width, fixed.height)
                    fromCoordinateSpace:screen.fixedCoordinateSpace];
        [path appendPath:[UIBezierPath bezierPathWithRect:frame]];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    MTEdgeDebugLayer.frame = view.bounds;
    // One non-zero fill avoids doubled opacity where one/two-finger strips overlap.
    MTEdgeDebugLayer.path = path.CGPath;
    [CATransaction commit];
}

void MTUpdateEdgeDebugOverlay(NSDictionary *preferences, NSArray<NSString *> *slots, NSInteger orientation, BOOL available) {
    if (!NSThread.isMainThread) return;
    if (!available || !MTEdgeGestureFlag(preferences[kMTEdgeGesturesDebug]) || slots.count == 0) {
        MTEdgeDebugWindowInstance.hidden = YES;
        MTEdgeDebugWindowInstance.rootViewController = nil;
        MTEdgeDebugWindowInstance = nil;
        MTEdgeDebugLayer = nil;
        MTEdgeDebugPreferences = nil;
        MTEdgeDebugSlots = nil;
        return;
    }
    if (!MTEdgeDebugWindowInstance) {
        UIWindowScene *scene = nil;
        NSInteger bestScore = NSIntegerMin;
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if (![candidate isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)candidate;
            NSString *identity = candidate.session.persistentIdentifier.lowercaseString ?: @"";
            NSString *role = candidate.session.role.lowercaseString ?: @"";
            if (windowScene.screen != UIScreen.mainScreen || [identity containsString:@"systemaperture"] ||
                [role containsString:@"systemaperture"] || candidate.activationState == UISceneActivationStateUnattached ||
                candidate.activationState == UISceneActivationStateBackground) continue;
            NSInteger score = [identity isEqual:@"com.apple.springboard"] ? 100 :
                ([NSStringFromClass(candidate.class) isEqual:@"SBWindowScene"] ? 50 : 0);
            if (score > bestScore) { scene = windowScene; bestScore = score; }
        }
        MTEdgeDebugWindow *window = scene ? [[MTEdgeDebugWindow alloc] initWithWindowScene:scene] :
            [[MTEdgeDebugWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        window.frame = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
        window.backgroundColor = UIColor.clearColor;
        window.opaque = NO;
        window.userInteractionEnabled = NO;
        window.accessibilityElementsHidden = YES;
        window.windowLevel = UIWindowLevelAlert + 10;
        window.rootViewController = [MTEdgeDebugController new];
        UIView *view = window.rootViewController.view;
        view.frame = window.bounds;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        view.backgroundColor = UIColor.clearColor;
        view.userInteractionEnabled = NO;
        view.accessibilityElementsHidden = YES;
        CAShapeLayer *layer = [CAShapeLayer layer];
        layer.fillColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.20].CGColor;
        layer.fillRule = kCAFillRuleNonZero;
        if (!MTEdgeDisableLayerHitTesting(window.layer) || !MTEdgeDisableLayerHitTesting(view.layer) ||
            !MTEdgeDisableLayerHitTesting(layer)) {
            window.hidden = YES;
            window.rootViewController = nil;
            NSLog(@"[MetisKeyboard][EdgeGesture] debug overlay unavailable: layer passthrough unsupported");
            return;
        }
        [view.layer addSublayer:layer];
        MTEdgeDebugWindowInstance = window;
        MTEdgeDebugLayer = layer;
    }
    MTEdgeDebugPreferences = [preferences copy];
    MTEdgeDebugSlots = [slots copy];
    MTEdgeDebugOrientation = orientation;
    MTEdgeDebugWindowInstance.hidden = NO; // never makeKeyAndVisible
    MTRenderEdgeDebugRegions();
}
