#import "MTEdgeDebugOverlay.h"
#import "MTEdgeGesturePolicy.h"
#import "MTPathResolver.h"
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
static CALayer *MTEdgeDistanceLayer;
static NSDictionary *MTEdgeDebugPreferences;
static NSArray<NSString *> *MTEdgeDebugSlots;
static NSInteger MTEdgeDebugOrientation;
static void MTRenderEdgeDebugRegions(void);

static NSString *MTEdgeDistanceCaption(NSString *slot, double distance) {
    NSBundle *bundle = [NSBundle bundleWithPath:MTResolvePath(@"/Library/PreferenceBundles/MetisKeyboardPrefs.bundle")];
    NSString *key = [@"EDGE_DISTANCE_GUIDE_" stringByAppendingString:slot.uppercaseString];
    NSDictionary *fallbacks = @{@"left": @"Left · 1 finger", @"right": @"Right · 1 finger",
        @"left2": @"Left · 2 fingers", @"right2": @"Right · 2 fingers"};
    NSString *title = [bundle localizedStringForKey:key value:fallbacks[slot] table:nil] ?: fallbacks[slot];
    NSString *format = [bundle localizedStringForKey:@"EDGE_DISTANCE_GUIDE_FORMAT" value:@"%@ · Slide %.0f pt to trigger" table:nil]
        ?: @"%@ · Slide %.0f pt to trigger";
    return [NSString stringWithFormat:format, title, distance];
}

static CGPoint MTEdgeGuideHostPoint(UIView *view, double x, double y, CGSize fixedSize) {
    MTEdgeRegion physical = MTEdgeRegionToFixed((MTEdgeRegion){x, y, 0, 0}, fixedSize.width, fixedSize.height, MTEdgeDebugOrientation);
    return [view convertPoint:CGPointMake(physical.x, physical.y) fromCoordinateSpace:UIScreen.mainScreen.fixedCoordinateSpace];
}

static BOOL MTRenderEdgeDistanceGuides(UIView *view, CGSize fixedSize, double width, double height) {
    // Clear old captions/rulers on range, assignment, or orientation changes.
    for (CALayer *layer in [MTEdgeDistanceLayer.sublayers copy]) [layer removeFromSuperlayer];
    CGPoint origin = MTEdgeGuideHostPoint(view, 0, 0, fixedSize);
    CGPoint xAxis = MTEdgeGuideHostPoint(view, 1, 0, fixedSize);
    CGPoint yAxis = MTEdgeGuideHostPoint(view, 0, 1, fixedSize);
    MTEdgeDistanceLayer.bounds = CGRectMake(0, 0, width, height);
    MTEdgeDistanceLayer.anchorPoint = CGPointZero;
    MTEdgeDistanceLayer.position = origin;
    // Rotate both paths and text from displayed orientation into the actual
    // SpringBoard host window; labels stay upright in either landscape side.
    MTEdgeDistanceLayer.affineTransform = CGAffineTransformMake(xAxis.x - origin.x, xAxis.y - origin.y,
        yAxis.x - origin.x, yAxis.y - origin.y, 0, 0);
    NSMutableArray<NSString *> *slots = [NSMutableArray array];
    for (NSString *slot in MTEdgeGestureSlots()) if ([MTEdgeDebugSlots containsObject:slot]) [slots addObject:slot];
    NSUInteger index = 0;
    for (NSString *slot in slots) {
        NSDictionary *range = MTEdgeGestureRange(MTEdgeDebugPreferences, slot);
        MTEdgeDistanceGuide guide = MTEdgeDistanceGuideLayout(range, slot, width, height, index++, slots.count);
        if (guide.label.width <= 0) continue;
        double distance = fabs(guide.endX - guide.startX);
        CAShapeLayer *band = [CAShapeLayer layer];
        band.frame = MTEdgeDistanceLayer.bounds;
        band.fillColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.12].CGColor;
        band.path = [UIBezierPath bezierPathWithRect:CGRectMake(fmin(guide.startX, guide.endX), guide.y - 4, distance, 8)].CGPath;
        CAShapeLayer *ruler = [CAShapeLayer layer];
        ruler.frame = MTEdgeDistanceLayer.bounds;
        ruler.fillColor = NULL;
        ruler.strokeColor = [UIColor colorWithRed:0.95 green:0.08 blue:0.08 alpha:0.85].CGColor;
        ruler.lineWidth = 2;
        ruler.lineCap = kCALineCapRound;
        ruler.lineJoin = kCALineJoinRound;
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(guide.startX, guide.y - 6)];
        [path addLineToPoint:CGPointMake(guide.startX, guide.y + 6)];
        [path moveToPoint:CGPointMake(guide.endX, guide.y - 6)];
        [path addLineToPoint:CGPointMake(guide.endX, guide.y + 6)];
        [path moveToPoint:CGPointMake(guide.startX, guide.y)];
        [path addLineToPoint:CGPointMake(guide.endX, guide.y)];
        double direction = guide.endX > guide.startX ? 1 : -1;
        [path moveToPoint:CGPointMake(guide.endX - direction * 7, guide.y - 5)];
        [path addLineToPoint:CGPointMake(guide.endX, guide.y)];
        [path addLineToPoint:CGPointMake(guide.endX - direction * 7, guide.y + 5)];
        ruler.path = path.CGPath;
        CATextLayer *caption = [CATextLayer layer];
        caption.frame = CGRectMake(guide.label.x, guide.label.y, guide.label.width, guide.label.height);
        caption.string = MTEdgeDistanceCaption(slot, distance);
        caption.fontSize = 12;
        caption.contentsScale = UIScreen.mainScreen.scale;
        caption.alignmentMode = kCAAlignmentCenter;
        caption.foregroundColor = [UIColor colorWithRed:0.70 green:0 blue:0 alpha:1].CGColor;
        caption.backgroundColor = [UIColor colorWithWhite:1 alpha:0.72].CGColor;
        caption.cornerRadius = 5;
        if (!MTEdgeDisableLayerHitTesting(band) || !MTEdgeDisableLayerHitTesting(ruler) || !MTEdgeDisableLayerHitTesting(caption)) return NO;
        [MTEdgeDistanceLayer addSublayer:band];
        [MTEdgeDistanceLayer addSublayer:ruler];
        [MTEdgeDistanceLayer addSublayer:caption];
    }
    return YES;
}

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
    BOOL guidesReady = MTRenderEdgeDistanceGuides(view, fixedSize, width, height);
    [CATransaction commit];
    if (!guidesReady) {
        MTEdgeDebugWindowInstance.hidden = YES;
        NSLog(@"[MetisKeyboard][EdgeGesture] distance guide hidden: layer passthrough unsupported");
    }
}

void MTUpdateEdgeDebugOverlay(NSDictionary *preferences, NSArray<NSString *> *slots, NSInteger orientation, BOOL available) {
    if (!NSThread.isMainThread) return;
    if (!available || !MTEdgeGestureFlag(preferences[kMTEdgeGesturesDebug]) || slots.count == 0) {
        MTEdgeDebugWindowInstance.hidden = YES;
        MTEdgeDebugWindowInstance.rootViewController = nil;
        MTEdgeDebugWindowInstance = nil;
        MTEdgeDebugLayer = nil;
        MTEdgeDistanceLayer = nil;
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
        CALayer *distanceLayer = [CALayer layer];
        layer.fillColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.20].CGColor;
        layer.fillRule = kCAFillRuleNonZero;
        if (!MTEdgeDisableLayerHitTesting(window.layer) || !MTEdgeDisableLayerHitTesting(view.layer) ||
            !MTEdgeDisableLayerHitTesting(layer) || !MTEdgeDisableLayerHitTesting(distanceLayer)) {
            window.hidden = YES;
            window.rootViewController = nil;
            NSLog(@"[MetisKeyboard][EdgeGesture] debug overlay unavailable: layer passthrough unsupported");
            return;
        }
        [view.layer addSublayer:layer];
        [view.layer addSublayer:distanceLayer];
        MTEdgeDebugWindowInstance = window;
        MTEdgeDebugLayer = layer;
        MTEdgeDistanceLayer = distanceLayer;
    }
    MTEdgeDebugPreferences = [preferences copy];
    MTEdgeDebugSlots = [slots copy];
    MTEdgeDebugOrientation = orientation;
    MTEdgeDebugWindowInstance.hidden = NO; // never makeKeyAndVisible
    MTRenderEdgeDebugRegions();
}
