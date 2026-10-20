#import "MTArcDebugOverlay.h"
#import "MTArcGesturePolicy.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <string.h>

// Match edge debug's WindowServer passthrough contract as well as UIKit's.
// Hide the overlay if the private layer contract is absent or has changed ABI.
static BOOL MTArcDisableLayerHitTesting(id layer) {
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

@interface MTArcDebugWindow : UIWindow
@end
@implementation MTArcDebugWindow
- (BOOL)_canBecomeKeyWindow { return NO; }
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
@end

static MTArcDebugWindow *MTArcDebugWindowInstance;
static CAShapeLayer *MTArcDebugLayer;
static NSDictionary *MTArcDebugPreferences;
static NSArray<NSString *> *MTArcDebugSlots;
static NSInteger MTArcDebugOrientation;

static CGPoint MTArcDebugHostPoint(UIView *view, CGPoint displayed, CGSize fixedSize) {
    CGPoint physical = MTArcPointToFixed(displayed.x, displayed.y, fixedSize.width, fixedSize.height, MTArcDebugOrientation);
    return [view convertPoint:physical fromCoordinateSpace:UIScreen.mainScreen.fixedCoordinateSpace];
}

static void MTRenderArcDebugRegions(void) {
    UIView *view = MTArcDebugWindowInstance.rootViewController.view;
    if (!view || !MTArcDebugLayer) return;
    CGSize fixed = UIScreen.mainScreen.fixedCoordinateSpace.bounds.size;
    BOOL landscape = MTArcDebugOrientation == 3 || MTArcDebugOrientation == 4;
    double width = landscape ? fixed.height : fixed.width;
    double height = landscape ? fixed.width : fixed.height;
    // Build the exact quarter-disks in display coordinates, then map the whole
    // path into the host. A radius in pt stays identical to recognition in all
    // four interface orientations, regardless of the scene's own orientation.
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSString *slot in MTArcDebugSlots) {
        if (!MTArcGestureSlotValid(slot)) continue;
        BOOL left = [slot isEqual:@"bottomLeft"];
        double radius = MTArcGestureRadius(MTArcDebugPreferences, slot);
        CGPoint corner = CGPointMake(left ? 0 : width, height);
        [path moveToPoint:corner];
        [path addLineToPoint:CGPointMake(left ? 0 : width - radius, left ? height - radius : height)];
        [path addArcWithCenter:corner radius:radius startAngle:left ? -M_PI_2 : M_PI
                     endAngle:left ? 0 : M_PI * 1.5 clockwise:YES];
        [path closePath];
    }
    CGPoint origin = MTArcDebugHostPoint(view, CGPointZero, fixed);
    CGPoint xAxis = MTArcDebugHostPoint(view, CGPointMake(1, 0), fixed);
    CGPoint yAxis = MTArcDebugHostPoint(view, CGPointMake(0, 1), fixed);
    [path applyTransform:CGAffineTransformMake(xAxis.x - origin.x, xAxis.y - origin.y,
        yAxis.x - origin.x, yAxis.y - origin.y, origin.x, origin.y)];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    MTArcDebugLayer.frame = view.bounds;
    MTArcDebugLayer.path = path.CGPath;
    [CATransaction commit];
}

@interface MTArcDebugController : UIViewController
@end
@implementation MTArcDebugController
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; MTRenderArcDebugRegions(); }
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

void MTUpdateArcDebugOverlay(NSDictionary *preferences, NSArray<NSString *> *slots, NSInteger orientation, BOOL available) {
    if (!NSThread.isMainThread) return;
    if (!available || !MTArcGestureFlag(preferences[kMTArcGesturesDebug]) || slots.count == 0) {
        MTArcDebugWindowInstance.hidden = YES;
        MTArcDebugWindowInstance.rootViewController = nil;
        MTArcDebugWindowInstance = nil;
        MTArcDebugLayer = nil;
        MTArcDebugPreferences = nil;
        MTArcDebugSlots = nil;
        return;
    }
    if (!MTArcDebugWindowInstance) {
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
        MTArcDebugWindow *window = scene ? [[MTArcDebugWindow alloc] initWithWindowScene:scene] :
            [[MTArcDebugWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        window.frame = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
        window.backgroundColor = UIColor.clearColor;
        window.opaque = NO;
        window.userInteractionEnabled = NO;
        window.accessibilityElementsHidden = YES;
        window.windowLevel = UIWindowLevelAlert + 10;
        window.rootViewController = [MTArcDebugController new];
        UIView *view = window.rootViewController.view;
        view.frame = window.bounds;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        view.backgroundColor = UIColor.clearColor;
        view.userInteractionEnabled = NO;
        view.accessibilityElementsHidden = YES;
        CAShapeLayer *layer = [CAShapeLayer layer];
        layer.fillColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.20].CGColor;
        layer.fillRule = kCAFillRuleNonZero;
        if (!MTArcDisableLayerHitTesting(window.layer) || !MTArcDisableLayerHitTesting(view.layer) ||
            !MTArcDisableLayerHitTesting(layer)) {
            window.hidden = YES;
            window.rootViewController = nil;
            NSLog(@"[MetisKeyboard][ArcGesture] debug overlay unavailable: layer passthrough unsupported");
            return;
        }
        [view.layer addSublayer:layer];
        MTArcDebugWindowInstance = window;
        MTArcDebugLayer = layer;
    }
    MTArcDebugPreferences = [preferences copy];
    MTArcDebugSlots = [slots copy];
    MTArcDebugOrientation = orientation;
    MTArcDebugWindowInstance.hidden = NO; // never become key or take app focus
    MTRenderArcDebugRegions();
}
