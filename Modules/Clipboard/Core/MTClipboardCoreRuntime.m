//
//  MTClipboardCoreRuntime.m
//  Mt
//

#import "MTClipboardCoreRuntime.h"
#import "MTModuleGate.h"
#import "MTKeyboardHostResolver.h"
#import "MTMainViewController.h"
#import "MTHeaderButtonStyle.h"
#import "MTNotificationKeys.h"
#import "MTPanelPresentationMode.h"
#import "MTPasteboardManager.h"
#import "MTPasteboardItem.h"
#import "MTPreferenceKeys.h"
#import "MTQuickAction.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreFoundation/CoreFoundation.h>
#import <HBLog.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <notify.h>
#import <roothide.h>

static NSTimeInterval const kMTMinimumFeedbackInterval = 0.6;
static NSTimeInterval const kMTPasteSuppressionExpirationDelay = 1.0;

static UIColor *MTFloatingPreviewColorFromHex(NSString *hexColor) {
    NSString *value = [hexColor stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value hasPrefix:@"#"]) {
        value = [value substringFromIndex:1];
    }
    unsigned long long number = 0;
    NSScanner *scanner = [NSScanner scannerWithString:value ?: @""];
    if (![scanner scanHexLongLong:&number] || scanner.isAtEnd == NO || (value.length != 6 && value.length != 8)) {
        return [UIColor colorWithWhite:0.20 alpha:0.72];
    }
    CGFloat red = ((number >> (value.length == 8 ? 24 : 16)) & 0xFF) / 255.0;
    CGFloat green = ((number >> (value.length == 8 ? 16 : 8)) & 0xFF) / 255.0;
    CGFloat blue = ((number >> (value.length == 8 ? 8 : 0)) & 0xFF) / 255.0;
    return [UIColor colorWithRed:red green:green blue:blue alpha:0.72];
}

@interface UIApplication (MTPrivate)
- (UIInterfaceOrientation)_frontMostAppOrientation;
@end

@interface UIApplicationSceneSettings : NSObject
- (UIUserInterfaceStyle)userInterfaceStyle;
@end

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end

@protocol MTSBLockScreenManagerClass <NSObject>
+ (SBLockScreenManager *)sharedInstance;
@end

@protocol MTKeyboardAppearanceProviding <NSObject>
- (UIKeyboardAppearance)keyboardAppearance;
@end

@interface TITextInputTraits : NSObject <MTKeyboardAppearanceProviding>
- (UIKeyboardAppearance)keyboardAppearance;
@end

@interface UIKeyboardImpl : NSObject
+ (instancetype)activeInstance;
- (TITextInputTraits *)textInputTraits;
- (NSObject<MTKeyboardAppearanceProviding> *)inputDelegate;
- (NSObject<MTKeyboardAppearanceProviding> *)delegate;
@end

@protocol MTUIKeyboardImplClass <NSObject>
+ (UIKeyboardImpl *)activeInstance;
@end

@interface MTOverlayWindow : UIWindow
@end

@interface MTFloatingPreviewWindow : MTOverlayWindow
@end

NS_ASSUME_NONNULL_BEGIN

@interface MTPasteSuppressionState : NSObject
@property(nonatomic, assign, readonly, getter=isActive) BOOL active;
- (void)beginWithExpirationDelay:(NSTimeInterval)expirationDelay;
- (BOOL)consumeIfActive;
@end

@interface MTPasteSuppressionState ()

#pragma mark - State

@property(nonatomic, assign, readwrite, getter=isActive) BOOL active;
@property(nonatomic, assign) NSUInteger token;

#pragma mark - Expiration

@property(nonatomic, copy, nullable) dispatch_block_t expirationBlock;

#pragma mark - Lifecycle

- (void)clear;

#pragma mark - Expiration

- (void)cancelExpiration;
- (void)expireForToken:(NSUInteger)token;

@end

NS_ASSUME_NONNULL_END

@implementation MTOverlayWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *rootView = [[self rootViewController] view];
    if (!rootView || [rootView isHidden]) {
        return nil;
    }

    return [super hitTest:point withEvent:event];
}

@end

@implementation MTFloatingPreviewWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    return hitView == self ? nil : hitView;
}

@end

@interface MTFloatingPreviewView : UIView
@end

@implementation MTFloatingPreviewView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    return hitView == self ? nil : hitView;
}

@end

@interface MTFloatingPreviewViewController : UIViewController

@property(nonatomic, strong) UIButton *button;
@property(nonatomic, strong) UIPanGestureRecognizer *panGestureRecognizer;
@property(nonatomic, strong) UITapGestureRecognizer *doubleTapGestureRecognizer;
@property(nonatomic, copy, nullable) void (^tapHandler)(void);
@property(nonatomic, copy, nullable) void (^doubleTapHandler)(void);
@property(nonatomic, copy, nullable) void (^positionChangedHandler)(BOOL dockedRight, CGFloat verticalPosition);
@property(nonatomic, assign) BOOL doubleTapEnabled;
@property(nonatomic, assign) BOOL hasCustomPosition;
@property(nonatomic, assign) BOOL dockedRight;
@property(nonatomic, assign) CGFloat verticalPosition;
@property(nonatomic, assign) CGFloat bubbleDiameter;
@property(nonatomic, strong) UIColor *bubbleColor;
@property(nonatomic, assign) BOOL didMoveDuringPan;
@property(nonatomic, strong, nullable) CALayer *countdownRingContainer;
@property(nonatomic, strong, nullable) CAShapeLayer *countdownTrackLayer;
@property(nonatomic, strong, nullable) CAShapeLayer *countdownArcLayer;
@property(nonatomic, strong, nullable) CALayer *countdownHeadLayer;

- (void)setPreviewImage:(nullable UIImage *)image;
- (void)applyBubbleDiameter:(CGFloat)diameter color:(UIColor *)color;
- (void)startCountdownRingWithDuration:(NSTimeInterval)duration;
- (void)stopCountdownRing;

@end

@implementation MTFloatingPreviewViewController

static CGFloat const kMTFloatingPreviewDefaultDiameter = 64.0;
// Keep the bubble fully visible vertically while allowing its outer edge to
// touch the left/right screen edges with no artificial horizontal gap.
static CGFloat const kMTFloatingPreviewHorizontalEdgeInset = 0.0;
static CGFloat const kMTFloatingPreviewVerticalEdgeInset = 12.0;
// The countdown ring orbits just outside the bubble's rim.
static CGFloat const kMTCountdownRingGap = 3.0;
static CGFloat const kMTCountdownRingStrokeWidth = 3.0;
// Extra horizontal travel past the rim + ring so the hide slide fully clears
// the screen edge (including the ring glow) before the window is hidden.
static CGFloat const kMTFloatingPreviewExitOvershoot = 8.0;

- (void)loadView {
    [self setView:[[MTFloatingPreviewView alloc] initWithFrame:CGRectZero]];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTintColor:[UIColor whiteColor]];
    if (!self.bubbleColor) {
        [self setBubbleColor:[UIColor colorWithWhite:0.20 alpha:0.72]];
    }
    if (self.bubbleDiameter <= 0.0) {
        [self setBubbleDiameter:kMTFloatingPreviewDefaultDiameter];
    }
    [button setBackgroundColor:[[self bubbleColor] colorWithAlphaComponent:0.72]];
    [[button layer] setCornerRadius:[self bubbleDiameter] * 0.5];
    [[button layer] setBorderWidth:1.0];
    [[button layer] setBorderColor:[[UIColor colorWithWhite:1.0 alpha:0.42] CGColor]];
    [[button layer] setShadowColor:[[UIColor blackColor] CGColor]];
    [[button layer] setShadowOpacity:0.28];
    [[button layer] setShadowRadius:8.0];
    [[button layer] setShadowOffset:CGSizeMake(0, 3)];
    UITapGestureRecognizer *tapGestureRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(buttonTapped:)];
    [button addGestureRecognizer:tapGestureRecognizer];
    UITapGestureRecognizer *doubleTapGestureRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(buttonDoubleTapped:)];
    [doubleTapGestureRecognizer setNumberOfTapsRequired:2];
    [doubleTapGestureRecognizer setEnabled:[self doubleTapEnabled]];
    [button addGestureRecognizer:doubleTapGestureRecognizer];
    UIPanGestureRecognizer *panGestureRecognizer =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGestureRecognizer:)];
    [panGestureRecognizer setCancelsTouchesInView:NO];
    [button addGestureRecognizer:panGestureRecognizer];
    [tapGestureRecognizer requireGestureRecognizerToFail:panGestureRecognizer];
    [tapGestureRecognizer requireGestureRecognizerToFail:doubleTapGestureRecognizer];
    [doubleTapGestureRecognizer requireGestureRecognizerToFail:panGestureRecognizer];
    [[self view] addSubview:button];
    [self setButton:button];
    [self setPanGestureRecognizer:panGestureRecognizer];
    [self setDoubleTapGestureRecognizer:doubleTapGestureRecognizer];
    [self installCountdownRingLayers];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat size = MAX(1.0, [self bubbleDiameter]);
    CGRect bounds = [[self view] bounds];
    CGFloat verticalInset = kMTFloatingPreviewVerticalEdgeInset;
    CGFloat minimumCenterY = CGRectGetMinY(bounds) + verticalInset + size * 0.5;
    CGFloat maximumCenterY = MAX(minimumCenterY, CGRectGetMaxY(bounds) - verticalInset - size * 0.5);
    CGFloat centerY = [self hasCustomPosition]
                          ? minimumCenterY + ([self verticalPosition] * (maximumCenterY - minimumCenterY))
                          : CGRectGetMidY(bounds);
    centerY = MIN(MAX(centerY, minimumCenterY), maximumCenterY);
    CGFloat minimumCenterX = CGRectGetMinX(bounds) + kMTFloatingPreviewHorizontalEdgeInset + size * 0.5;
    CGFloat maximumCenterX = CGRectGetMaxX(bounds) - kMTFloatingPreviewHorizontalEdgeInset - size * 0.5;
    CGFloat centerX = ([self hasCustomPosition] && ![self dockedRight]) ? minimumCenterX : maximumCenterX;
    centerX = MIN(MAX(centerX, minimumCenterX), MAX(minimumCenterX, maximumCenterX));
    [[self button] setFrame:CGRectMake(centerX - size * 0.5, centerY - size * 0.5, size, size)];
    [self refreshCountdownRingGeometry];
}

- (void)applyBubbleDiameter:(CGFloat)diameter color:(UIColor *)color {
    [self setBubbleDiameter:MAX(1.0, diameter)];
    [self setBubbleColor:color ?: [UIColor colorWithWhite:0.20 alpha:0.72]];
    [[self button] setBackgroundColor:[[self bubbleColor] colorWithAlphaComponent:0.72]];
    [[self button] layer].cornerRadius = [self bubbleDiameter] * 0.5;
    [self refreshCountdownRingColors];
    [[self view] setNeedsLayout];
}

- (void)handlePanGestureRecognizer:(UIPanGestureRecognizer *)gestureRecognizer {
    UIView *view = [self view];
    UIButton *button = [self button];
    if (!view || !button) {
        return;
    }

    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan) {
        [self setDidMoveDuringPan:NO];
    }

    CGPoint translation = [gestureRecognizer translationInView:view];
    if (fabs(translation.x) > 2.0 || fabs(translation.y) > 2.0) {
        [self setDidMoveDuringPan:YES];
    }
    CGPoint center = [button center];
    center.x += translation.x;
    center.y += translation.y;
    [gestureRecognizer setTranslation:CGPointZero inView:view];

    CGFloat halfSize = MAX(1.0, [self bubbleDiameter]) * 0.5;
    CGRect bounds = [view bounds];
    CGFloat minimumX = CGRectGetMinX(bounds) + kMTFloatingPreviewHorizontalEdgeInset + halfSize;
    CGFloat maximumX = MAX(minimumX, CGRectGetMaxX(bounds) - kMTFloatingPreviewHorizontalEdgeInset - halfSize);
    CGFloat minimumY = CGRectGetMinY(bounds) + kMTFloatingPreviewVerticalEdgeInset + halfSize;
    CGFloat maximumY = MAX(minimumY, CGRectGetMaxY(bounds) - kMTFloatingPreviewVerticalEdgeInset - halfSize);
    center.x = MIN(MAX(center.x, minimumX), maximumX);
    center.y = MIN(MAX(center.y, minimumY), maximumY);

    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan ||
        [gestureRecognizer state] == UIGestureRecognizerStateChanged) {
        [self setHasCustomPosition:YES];
        [button setCenter:center];
        return;
    }

    if ([gestureRecognizer state] == UIGestureRecognizerStateEnded ||
        [gestureRecognizer state] == UIGestureRecognizerStateCancelled ||
        [gestureRecognizer state] == UIGestureRecognizerStateFailed) {
        [self setHasCustomPosition:YES];
        [self setDockedRight:center.x >= CGRectGetMidX(bounds)];
        [self setVerticalPosition:(center.y - minimumY) / MAX(1.0, maximumY - minimumY)];
        if ([self positionChangedHandler]) {
            [self positionChangedHandler]([self dockedRight], [self verticalPosition]);
        }
        [UIView animateWithDuration:0.2
                         animations:^{
                           [[self view] setNeedsLayout];
                           [[self view] layoutIfNeeded];
                         }];
    }
}

- (void)setPreviewImage:(UIImage *)image {
    UIImage *previewImage = image ?: [UIImage systemImageNamed:@"doc.on.clipboard.fill"];
    [[self button] setImage:[previewImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                   forState:UIControlStateNormal];
}

- (void)buttonTapped:(UITapGestureRecognizer *)recognizer {
    (void)recognizer;
    if ([self didMoveDuringPan]) {
        [self setDidMoveDuringPan:NO];
        return;
    }
    if ([self tapHandler]) {
        [self tapHandler]();
    }
}

- (void)buttonDoubleTapped:(UITapGestureRecognizer *)recognizer {
    (void)recognizer;
    if (![self doubleTapEnabled] || [self didMoveDuringPan]) {
        [self setDidMoveDuringPan:NO];
        return;
    }
    if ([self doubleTapHandler]) {
        [self doubleTapHandler]();
    }
}

- (void)setDoubleTapEnabled:(BOOL)doubleTapEnabled {
    _doubleTapEnabled = doubleTapEnabled;
    [[self doubleTapGestureRecognizer] setEnabled:doubleTapEnabled];
}

#pragma mark - Countdown Ring

- (UIColor *)countdownRingColor {
    CGFloat hue = 0.0, saturation = 0.0, brightness = 0.0, alpha = 0.0;
    if ([[self bubbleColor] getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha] &&
        saturation > 0.05) {
        return [UIColor colorWithHue:hue
                          saturation:MIN(1.0, saturation * 1.25 + 0.15)
                          brightness:MIN(1.0, brightness + 0.35)
                               alpha:1.0];
    }
    // Neutral bubble colors get a cyan glow so the ring still reads as light.
    return [UIColor colorWithHue:0.52 saturation:0.72 brightness:1.0 alpha:1.0];
}

- (void)installCountdownRingLayers {
    UIColor *ringColor = [self countdownRingColor];
    CGFloat stroke = kMTCountdownRingStrokeWidth;

    CALayer *container = [[CALayer alloc] init];
    [container setHidden:YES];

    CAShapeLayer *trackLayer = [CAShapeLayer layer];
    [trackLayer setFillColor:[[UIColor clearColor] CGColor]];
    [trackLayer setStrokeColor:[[UIColor colorWithWhite:1.0 alpha:0.15] CGColor]];
    [trackLayer setLineWidth:stroke];

    CAShapeLayer *arcLayer = [CAShapeLayer layer];
    [arcLayer setFillColor:[[UIColor clearColor] CGColor]];
    [arcLayer setStrokeColor:[ringColor CGColor]];
    [arcLayer setLineWidth:stroke];
    [arcLayer setLineCap:kCALineCapRound];
    [arcLayer setShadowColor:[ringColor CGColor]];
    [arcLayer setShadowOpacity:0.85];
    [arcLayer setShadowRadius:5.0];
    [arcLayer setShadowOffset:CGSizeZero];

    CGFloat headSize = stroke * 1.9;
    CALayer *headLayer = [[CALayer alloc] init];
    [headLayer setBounds:CGRectMake(0.0, 0.0, headSize, headSize)];
    [headLayer setCornerRadius:headSize * 0.5];
    [headLayer setBackgroundColor:[[UIColor whiteColor] CGColor]];
    [headLayer setShadowColor:[ringColor CGColor]];
    [headLayer setShadowOpacity:1.0];
    [headLayer setShadowRadius:4.0];
    [headLayer setShadowOffset:CGSizeZero];

    [container addSublayer:trackLayer];
    [container addSublayer:arcLayer];
    [container addSublayer:headLayer];
    [[self button].layer addSublayer:container];

    [self setCountdownRingContainer:container];
    [self setCountdownTrackLayer:trackLayer];
    [self setCountdownArcLayer:arcLayer];
    [self setCountdownHeadLayer:headLayer];
    [self refreshCountdownRingGeometry];
}

- (void)refreshCountdownRingColors {
    UIColor *ringColor = [self countdownRingColor];
    [[self countdownArcLayer] setStrokeColor:[ringColor CGColor]];
    [[self countdownArcLayer] setShadowColor:[ringColor CGColor]];
    [[self countdownHeadLayer] setShadowColor:[ringColor CGColor]];
}

- (void)refreshCountdownRingGeometry {
    CALayer *container = [self countdownRingContainer];
    UIButton *button = [self button];
    if (!container || !button) {
        return;
    }

    CGFloat diameter = MAX(1.0, [self bubbleDiameter]);
    CGFloat side = diameter + 2.0 * kMTCountdownRingGap;
    CGRect frame = CGRectMake(-kMTCountdownRingGap, -kMTCountdownRingGap, side, side);
    if (CGRectEqualToRect([container frame], frame)) {
        return;
    }
    [container setFrame:frame];

    CGFloat radius = side * 0.5 - kMTCountdownRingStrokeWidth * 0.5;
    // The stroke path starts at 12 o'clock and runs clockwise, so strokeEnd 1.0
    // covers the full 360° and unwinding it retreats counter-clockwise.
    UIBezierPath *circle = [UIBezierPath
        bezierPathWithArcCenter:CGPointMake(side * 0.5, side * 0.5)
                         radius:radius
                     startAngle:-M_PI_2
                       endAngle:(-M_PI_2 + 2.0 * M_PI)
                      clockwise:YES];
    [[self countdownTrackLayer] setFrame:[container bounds]];
    [[self countdownTrackLayer] setPath:[circle CGPath]];
    [[self countdownArcLayer] setFrame:[container bounds]];
    [[self countdownArcLayer] setPath:[circle CGPath]];
    [[self countdownHeadLayer] setPosition:CGPointMake(side * 0.5, side * 0.5 - radius)];
}

- (UIBezierPath *)countdownHeadOrbitPath {
    CGFloat diameter = MAX(1.0, [self bubbleDiameter]);
    CGFloat side = diameter + 2.0 * kMTCountdownRingGap;
    CGFloat radius = side * 0.5 - kMTCountdownRingStrokeWidth * 0.5;
    return [UIBezierPath
        bezierPathWithArcCenter:CGPointMake(side * 0.5, side * 0.5)
                         radius:radius
                     startAngle:-M_PI_2
                       endAngle:(-M_PI_2 - 2.0 * M_PI)
                      clockwise:NO];
}

- (void)startCountdownRingWithDuration:(NSTimeInterval)duration {
    CALayer *container = [self countdownRingContainer];
    CAShapeLayer *arcLayer = [self countdownArcLayer];
    CALayer *headLayer = [self countdownHeadLayer];
    if (!container || !arcLayer || !headLayer || duration <= 0.0) {
        [self stopCountdownRing];
        return;
    }

    [self refreshCountdownRingGeometry];
    CGPoint headHomePosition = [headLayer position];

    CAMediaTimingFunction *linear = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    CAKeyframeAnimation *arcFadeAnimation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    [arcFadeAnimation setValues:@[ @1.0, @1.0, @0.0 ]];
    [arcFadeAnimation setKeyTimes:@[ @0.0, @0.96, @1.0 ]];
    [arcFadeAnimation setDuration:duration];
    [arcFadeAnimation setTimingFunction:linear];
    [arcFadeAnimation setFillMode:kCAFillModeForwards];
    [arcFadeAnimation setRemovedOnCompletion:NO];

    CAKeyframeAnimation *headFadeAnimation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    [headFadeAnimation setValues:@[ @1.0, @1.0, @0.0 ]];
    [headFadeAnimation setKeyTimes:@[ @0.0, @0.96, @1.0 ]];
    [headFadeAnimation setDuration:duration];
    [headFadeAnimation setTimingFunction:linear];
    [headFadeAnimation setFillMode:kCAFillModeForwards];
    [headFadeAnimation setRemovedOnCompletion:NO];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *layer in [container sublayers]) {
        [layer removeAllAnimations];
    }
    // Model reset and animation registration share one transaction, so the ring
    // never flashes its pre-animation full-circle state between frames.
    [container setHidden:NO];
    [arcLayer setStrokeStart:0.0];
    [arcLayer setStrokeEnd:1.0];
    [arcLayer setOpacity:1.0];
    [headLayer setOpacity:1.0];
    [headLayer setPosition:headHomePosition];

    // The sweep and the head dot share the duration of the auto-hide countdown,
    // so the light dies out exactly when the bubble hides itself.
    CABasicAnimation *sweepAnimation = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    [sweepAnimation setFromValue:@1.0];
    [sweepAnimation setToValue:@0.0];
    [sweepAnimation setDuration:duration];
    [sweepAnimation setTimingFunction:linear];
    [sweepAnimation setFillMode:kCAFillModeForwards];
    [sweepAnimation setRemovedOnCompletion:NO];
    [arcLayer addAnimation:sweepAnimation forKey:@"mtCountdownSweep"];
    [arcLayer addAnimation:arcFadeAnimation forKey:@"mtCountdownFade"];

    CAKeyframeAnimation *orbitAnimation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    [orbitAnimation setPath:[[self countdownHeadOrbitPath] CGPath]];
    [orbitAnimation setCalculationMode:kCAAnimationPaced];
    [orbitAnimation setDuration:duration];
    [orbitAnimation setTimingFunction:linear];
    [orbitAnimation setFillMode:kCAFillModeForwards];
    [orbitAnimation setRemovedOnCompletion:NO];
    [headLayer addAnimation:orbitAnimation forKey:@"mtCountdownOrbit"];
    [headLayer addAnimation:headFadeAnimation forKey:@"mtCountdownFade"];
    [CATransaction commit];
}

- (void)stopCountdownRing {
    CALayer *container = [self countdownRingContainer];
    if (!container) {
        return;
    }

    for (CALayer *layer in [container sublayers]) {
        [layer removeAllAnimations];
    }
    [container setHidden:YES];
}

@end

@implementation MTPasteSuppressionState

- (void)beginWithExpirationDelay:(NSTimeInterval)expirationDelay {
    self.token++;
    self.active = YES;

    [self cancelExpiration];

    NSUInteger token = self.token;
    __weak typeof(self) weakSelf = self;
    dispatch_block_t expirationBlock = dispatch_block_create(0, ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || strongSelf.token != token) {
          return;
      }

      [strongSelf expireForToken:token];
    });
    self.expirationBlock = expirationBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(expirationDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), expirationBlock);
}

- (BOOL)consumeIfActive {
    if (!self.active) {
        return NO;
    }

    [self clear];
    return YES;
}

- (void)clear {
    [self cancelExpiration];
    self.active = NO;
}

- (void)cancelExpiration {
    dispatch_block_t expirationBlock = self.expirationBlock;
    if (expirationBlock) {
        dispatch_block_cancel(expirationBlock);
        self.expirationBlock = nil;
    }
}

- (void)expireForToken:(NSUInteger)token {
    if (self.token != token) {
        return;
    }

    self.expirationBlock = nil;
    self.active = NO;
}

@end

NS_ASSUME_NONNULL_BEGIN

@interface MTClipboardCoreRuntime () <MTMainViewControllerDelegate>

#pragma mark - Runtime Configuration

@property(nonatomic, assign, readwrite, getter=isEnabled) BOOL enabled;
@property(nonatomic, assign, readwrite) NSUInteger activationMethod;
@property(nonatomic, assign) BOOL privacyMode;
@property(nonatomic, assign) BOOL floatingPreview;
@property(nonatomic, assign) BOOL floatingPreviewDoubleTapAction;
@property(nonatomic, assign) BOOL floatingPreviewCountdownRing;
@property(nonatomic, assign) CGFloat floatingPreviewSize;
@property(nonatomic, assign) CGFloat floatingPreviewDuration;
@property(nonatomic, strong) UIColor *floatingPreviewColor;
@property(nonatomic, assign) BOOL floatingPreviewDockedRight;
@property(nonatomic, assign) CGFloat floatingPreviewVerticalPosition;
@property(nonatomic, assign, readwrite) MTGestureRecognizerMode gestureRecognizerMode;
@property(nonatomic, assign, readwrite) BOOL pasteTipsDisabled;

#pragma mark - View State

@property(nonatomic, strong, nullable) MTMainViewController *mainViewController;
@property(nonatomic, weak, nullable) UIWindow *statusBarWindow;
@property(nonatomic, strong, nullable) UIControl *portraitOutsideDismissOverlayView;
@property(nonatomic, strong, nullable) UIWindow *overlayWindow;
@property(nonatomic, strong, nullable) UIWindow *floatingPreviewWindow;
@property(nonatomic, strong, nullable) MTFloatingPreviewViewController *floatingPreviewViewController;
@property(nonatomic, strong, nullable) MTPasteboardItem *floatingPreviewItem;
@property(nonatomic, copy, nullable) dispatch_block_t floatingPreviewExpirationBlock;
@property(nonatomic, assign) NSUInteger floatingPreviewDisplayToken;
@property(nonatomic, assign) MTPanelPresentationMode activePresentationMode;
@property(nonatomic, assign) BOOL pendingHeightPreferenceApply;
@property(nonatomic, assign) BOOL didRequestInitialHistoryPreload;

#pragma mark - Preferences

@property(nonatomic, strong, nullable) NSUserDefaults *preferences;
@property(nonatomic, assign) NSUInteger maximumHistoryAmount;
@property(nonatomic, assign) BOOL saveText;
@property(nonatomic, assign) BOOL saveImages;
@property(nonatomic, assign) BOOL swipeToSelectWords;
@property(nonatomic, assign) BOOL automaticallyPaste;
@property(nonatomic, assign) MTAutomaticPasteMode automaticPasteMode;
@property(nonatomic, assign) MTAutomaticPromotionMode automaticPromotionMode;
@property(nonatomic, assign) MTInitialViewMode initialViewMode;
@property(nonatomic, assign) BOOL alwaysScrollToTop;
@property(nonatomic, assign) MTClearButtonMode clearButtonMode;
@property(nonatomic, assign) BOOL dismissOnOutsideTouch;
@property(nonatomic, assign) BOOL playSoundEffects;
@property(nonatomic, assign) BOOL playHapticFeedback;
@property(nonatomic, assign) NSUInteger previewLineCount;
@property(nonatomic, assign) MTItemDetailsMode itemDetailsMode;
@property(nonatomic, assign) CGFloat heightInPoints;
@property(nonatomic, assign) MTOverlayWindowLevelMode overlayWindowLevelMode;
@property(nonatomic, assign) CGFloat customOverlayWindowLevel;

#pragma mark - Feedback

@property(nonatomic, strong, nullable) AVAudioPlayer *clipboardFeedbackSoundPlayer;
@property(nonatomic, strong, nullable) AVAudioPlayer *pasteFeedbackSoundPlayer;
@property(nonatomic, assign) NSTimeInterval lastPasteFeedbackOccurred;
@property(nonatomic, assign) NSTimeInterval lastCopyFeedbackOccurred;

#pragma mark - Pasteboard Capture

@property(nonatomic, strong) MTPasteSuppressionState *pasteSuppressionState;

#pragma mark - Device State

@property(nonatomic, assign) int lockStateToken;
@property(nonatomic, assign, getter=isPackageMaintenanceMode) BOOL packageMaintenanceMode;

#pragma mark - Panel Host

- (BOOL)preparePanelHostForPresentationMode:(MTPanelPresentationMode)presentationMode;
- (CGRect)fullscreenPanelFrameInWindow:(nullable UIWindow *)window;
- (MTPanelPresentationMode)currentPresentationMode;
- (void)showQuickPreviewForItem:(MTPasteboardItem *)item;
- (nullable UIWindow *)floatingPreviewWindowCreatingIfNeeded;
- (void)showFloatingPreviewForItem:(MTPasteboardItem *)item;
- (void)hideFloatingPreviewAnimated:(BOOL)animated;
- (void)handleFloatingPreviewTap;
- (void)handleFloatingPreviewDoubleTap;
- (void)presentFloatingPreviewActionsForItem:(MTPasteboardItem *)item;
- (void)openFloatingPreviewAction:(NSDictionary<NSString *, id> *)action
                          forItem:(MTPasteboardItem *)item;
- (void)cancelFloatingPreviewExpiration;
- (void)applyFloatingPreviewAppearance;

@end

NS_ASSUME_NONNULL_END

@implementation MTClipboardCoreRuntime

+ (instancetype)sharedRuntime {
    static MTClipboardCoreRuntime *runtime = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      runtime = [[self alloc] initPrivate];
    });
    return runtime;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _previewLineCount = 1;
        _itemDetailsMode = kMTPreferenceKeyItemDetailsModeDefaultValue;
        _heightInPoints = 420;
        _activePresentationMode = MTPanelPresentationModePortraitDrawer;
        _pasteSuppressionState = [[MTPasteSuppressionState alloc] init];
    }
    return self;
}

- (BOOL)panelVisible {
    return self.mainViewController && ![self.mainViewController isHidden];
}

- (BOOL)fullscreenSearchActive {
    if (!self.panelVisible) {
        return NO;
    }

    return [self activePresentationMode] == MTPanelPresentationModeCompactLandscapeFullscreen ||
           [self.mainViewController isFullscreenSearchActive];
}

- (BOOL)systemMultitaskingGestureSuppressed {
    return self.panelVisible && [self.mainViewController shouldSuppressSystemMultitaskingGesture];
}

#pragma mark - Panel


- (CGRect)referenceBoundsForWindow:(nullable UIWindow *)window {
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    if (!window) {
        return screenBounds;
    }
    CGRect windowBounds = [window bounds];
    if (CGRectGetWidth(windowBounds) < 200.0 || CGRectGetHeight(windowBounds) < 200.0) {
        return screenBounds;
    }
    return windowBounds;
}

- (CGRect)portraitPanelFrameInWindow:(nullable UIWindow *)window {
    CGRect bounds = [self referenceBoundsForWindow:window];
    CGFloat inset = kMTPanelFloatingInset;

    CGFloat width = MIN(kMTPanelFloatingMaxWidth, CGRectGetWidth(bounds) - inset * 2.0);
    width = MAX(width, 280.0);
    CGFloat x = CGRectGetMidX(bounds) - width * 0.5;

    CGFloat maxHeight = MAX(CGRectGetHeight(bounds) - inset * 2.0, 220.0);
    CGFloat height = MIN(MAX(self.heightInPoints, 220.0), maxHeight);
    CGFloat y = CGRectGetMaxY(bounds) - height - inset;
    return CGRectMake(x, y, width, height);
}

- (CGRect)fullscreenPanelFrameInWindow:(UIWindow *)window {
    CGRect bounds = [self referenceBoundsForWindow:window];
    CGFloat inset = kMTPanelFloatingInset;

    CGFloat width = MIN(kMTPanelFloatingMaxWidth, CGRectGetWidth(bounds) - inset * 2.0);
    width = MAX(width, 280.0);
    CGFloat x = CGRectGetMidX(bounds) - width * 0.5;

    CGFloat y = CGRectGetMinY(bounds) + inset;
    CGFloat height = MAX(CGRectGetHeight(bounds) - inset * 2.0, 220.0);
    return CGRectMake(x, y, width, height);
}





- (UIControl *)ensurePortraitOutsideDismissOverlayInWindow:(UIWindow *)window {
    if (self.portraitOutsideDismissOverlayView && [self.portraitOutsideDismissOverlayView superview] == window) {
        return self.portraitOutsideDismissOverlayView;
    }

    [self.portraitOutsideDismissOverlayView removeFromSuperview];
    UIControl *outsideDismissOverlayView = [[UIControl alloc] initWithFrame:[window bounds]];
    [outsideDismissOverlayView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [outsideDismissOverlayView setBackgroundColor:[UIColor colorWithWhite:0 alpha:0.06]];
    [outsideDismissOverlayView setAlpha:0];
    [outsideDismissOverlayView setHidden:YES];
    [outsideDismissOverlayView setUserInteractionEnabled:NO];
    [window addSubview:outsideDismissOverlayView];
    self.portraitOutsideDismissOverlayView = outsideDismissOverlayView;
    return outsideDismissOverlayView;
}

- (void)createMainViewControllerIfNeeded {
    if (self.mainViewController) {
        return;
    }

    CGRect initialFrame = [self portraitPanelFrameInWindow:self.statusBarWindow];
    self.mainViewController = [[MTMainViewController alloc] initWithFrame:initialFrame];
    [self.mainViewController setDelegate:self];
    [self applyPreferencesToView];
    if (self.didRequestInitialHistoryPreload) {
        [self.mainViewController preloadHistoryIfNeeded];
    }
}

- (void)installPanelInStatusBarWindow:(UIWindow *)window {
    if (!window) {
        return;
    }

    self.statusBarWindow = window;
    [self createMainViewControllerIfNeeded];

    if (![self.mainViewController isHidden]) {
        [self preparePanelHostForPresentationMode:[self currentPresentationMode]];
        return;
    }

    [self preparePanelHostForPresentationMode:MTPanelPresentationModePortraitDrawer];
}

- (CGFloat)overlayWindowLevel {
    if (self.overlayWindowLevelMode == kMTOverlayWindowLevelModeCustom) {
        return self.customOverlayWindowLevel;
    }

    return CGFLOAT_MAX;
}

- (UIInterfaceOrientation)frontmostAppInterfaceOrientation {
    UIApplication *application = [UIApplication sharedApplication];
    if (![application respondsToSelector:@selector(_frontMostAppOrientation)]) {
        return UIInterfaceOrientationUnknown;
    }

    return [application _frontMostAppOrientation];
}

- (UIInterfaceOrientationMask)compactLandscapeSupportedInterfaceOrientations {
    switch ([self frontmostAppInterfaceOrientation]) {
    case UIInterfaceOrientationLandscapeLeft:
        return UIInterfaceOrientationMaskLandscapeLeft;
    case UIInterfaceOrientationLandscapeRight:
        return UIInterfaceOrientationMaskLandscapeRight;
    default:
        return UIInterfaceOrientationMaskLandscape;
    }
}

- (nullable UIWindow *)overlayWindowCreatingIfNeeded {
    UIWindowScene *windowScene = [self.statusBarWindow windowScene];
    if (!windowScene) {
        return nil;
    }

    if (self.overlayWindow && [self.overlayWindow windowScene] != windowScene) {
        [self.overlayWindow setHidden:YES];
        [self.overlayWindow setRootViewController:nil];
        self.overlayWindow = nil;
    }

    if (!self.overlayWindow) {
        UIWindow *window = [[MTOverlayWindow alloc] initWithWindowScene:windowScene];
        [window setBackgroundColor:[UIColor clearColor]];
        [window setOpaque:NO];
        [window setClipsToBounds:YES];
        [window setHidden:YES];
        self.overlayWindow = window;
    }

    [self.overlayWindow setWindowLevel:[self overlayWindowLevel]];
    return self.overlayWindow;
}

- (nullable UIWindow *)floatingPreviewWindowCreatingIfNeeded {
    UIWindowScene *windowScene = [self.statusBarWindow windowScene];
    if (!windowScene) {
        return nil;
    }

    if (self.floatingPreviewWindow && [self.floatingPreviewWindow windowScene] != windowScene) {
        [self.floatingPreviewWindow setHidden:YES];
        [self.floatingPreviewWindow setRootViewController:nil];
        self.floatingPreviewWindow = nil;
        self.floatingPreviewViewController = nil;
    }

    if (!self.floatingPreviewWindow) {
        UIWindow *window = [[MTFloatingPreviewWindow alloc] initWithWindowScene:windowScene];
        [window setBackgroundColor:[UIColor clearColor]];
        [window setOpaque:NO];
        [window setClipsToBounds:YES];
        [window setWindowLevel:[self overlayWindowLevel]];
        [window setHidden:YES];

        MTFloatingPreviewViewController *viewController =
            [[MTFloatingPreviewViewController alloc] init];
        __weak typeof(self) weakSelf = self;
        [viewController setTapHandler:^{
          [weakSelf handleFloatingPreviewTap];
        }];
        [viewController setDoubleTapHandler:^{
          [weakSelf handleFloatingPreviewDoubleTap];
        }];
        [viewController setPositionChangedHandler:^(BOOL dockedRight, CGFloat verticalPosition) {
          __strong typeof(weakSelf) strongSelf = weakSelf;
          if (!strongSelf) {
              return;
          }
          strongSelf.floatingPreviewDockedRight = dockedRight;
          strongSelf.floatingPreviewVerticalPosition = MIN(MAX(verticalPosition, 0.0), 1.0);
          [strongSelf.preferences setBool:dockedRight forKey:kMTPreferenceKeyFloatingPreviewDockedRight];
          [strongSelf.preferences setDouble:strongSelf.floatingPreviewVerticalPosition
                                     forKey:kMTPreferenceKeyFloatingPreviewVerticalPosition];
          [strongSelf.preferences synchronize];
        }];
        [window setRootViewController:viewController];
        self.floatingPreviewWindow = window;
        self.floatingPreviewViewController = viewController;
        // Load the view before applying persisted appearance. Otherwise viewDidLoad
        // can overwrite a color/size that was set while the view was still lazy.
        [viewController view];
    }

    [self.floatingPreviewWindow setWindowLevel:[self overlayWindowLevel]];
    [self applyFloatingPreviewAppearance];
    return self.floatingPreviewWindow;
}

- (void)applyFloatingPreviewAppearance {
    if (!self.floatingPreviewViewController) {
        return;
    }
    [self.floatingPreviewViewController setDockedRight:self.floatingPreviewDockedRight];
    [self.floatingPreviewViewController setVerticalPosition:self.floatingPreviewVerticalPosition];
    [self.floatingPreviewViewController setHasCustomPosition:YES];
    [self.floatingPreviewViewController setDoubleTapEnabled:self.floatingPreviewDoubleTapAction];
    [self.floatingPreviewViewController applyBubbleDiameter:self.floatingPreviewSize
                                                       color:self.floatingPreviewColor];
}

- (void)cancelFloatingPreviewExpiration {
    dispatch_block_t expirationBlock = self.floatingPreviewExpirationBlock;
    if (expirationBlock) {
        dispatch_block_cancel(expirationBlock);
        self.floatingPreviewExpirationBlock = nil;
    }
}

- (void)hideFloatingPreviewAnimated:(BOOL)animated {
    [self cancelFloatingPreviewExpiration];
    self.floatingPreviewItem = nil;
    NSUInteger displayToken = ++self.floatingPreviewDisplayToken;

    UIWindow *window = self.floatingPreviewWindow;
    MTFloatingPreviewViewController *viewController = self.floatingPreviewViewController;
    if (!window || [window isHidden]) {
        return;
    }

    if ([viewController presentedViewController]) {
        [viewController dismissViewControllerAnimated:NO completion:nil];
    }
    [[viewController button] setHidden:NO];

    void (^hide)(void) = ^{
      [viewController stopCountdownRing];
      [[viewController view] setAlpha:0.0];
      [[viewController view] setTransform:CGAffineTransformMakeScale(0.82, 0.82)];
      [window setHidden:YES];
    };
    if (!animated) {
        hide();
        return;
    }

    // Slide the bubble out through its nearest screen edge instead of shrinking
    // in place; the instant alpha drop in hide() lands once it is off-screen.
    UIView *floatingView = [viewController view];
    CGFloat exitDistance = MAX([viewController bubbleDiameter], 1.0) +
                           kMTCountdownRingGap + kMTCountdownRingStrokeWidth +
                           kMTFloatingPreviewExitOvershoot;
    BOOL exitRight = [[viewController button] center].x >= CGRectGetMidX([floatingView bounds]);
    CGAffineTransform exitTransform =
        CGAffineTransformMakeTranslation(exitRight ? exitDistance : -exitDistance, 0.0);

    [UIView animateWithDuration:0.22
        delay:0.0
        options:UIViewAnimationOptionCurveEaseIn
        animations:^{
          [floatingView setTransform:exitTransform];
        }
        completion:^(__unused BOOL finished) {
          if (self.floatingPreviewDisplayToken == displayToken) {
              hide();
          }
        }];
}

- (void)showFloatingPreviewForItem:(MTPasteboardItem *)item {
    if (!item || !self.floatingPreview || !self.enabled || !self.mainViewController ||
        ![self.mainViewController isHidden] || [self.mainViewController isEditingAnyContent]) {
        return;
    }

    BOOL locked = NO;
    if ([self readUILocked:&locked] && locked) {
        return;
    }

    UIWindow *window = [self floatingPreviewWindowCreatingIfNeeded];
    MTFloatingPreviewViewController *viewController = self.floatingPreviewViewController;
    if (!window || !viewController) {
        return;
    }

    // Re-apply the persisted appearance after the view has been materialized.
    // This keeps the first display after SpringBoard relaunch identical to later displays.
    [self applyFloatingPreviewAppearance];

    [self cancelFloatingPreviewExpiration];
    NSUInteger displayToken = ++self.floatingPreviewDisplayToken;
    self.floatingPreviewItem = item;
    [[viewController button] setHidden:NO];
    UIImage *image = [UIImage systemImageNamed:item.imageName.length > 0 ? @"photo.fill" : @"doc.on.clipboard.fill"];
    [viewController setPreviewImage:image];

    // A transformed view has an undefined frame. Reset the root view before
    // every geometry update, then animate only after its final layout is known.
    UIView *floatingView = [viewController view];
    [floatingView setTransform:CGAffineTransformIdentity];
    UIWindowScene *windowScene = [window windowScene];
    CGRect screenBounds = windowScene ? [[windowScene coordinateSpace] bounds] : [[UIScreen mainScreen] bounds];
    screenBounds = CGRectMake(0.0, 0.0, CGRectGetWidth(screenBounds), CGRectGetHeight(screenBounds));
    [window setFrame:screenBounds];
    [floatingView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [floatingView setFrame:[window bounds]];
    [floatingView.layer removeAllAnimations];
    [UIView performWithoutAnimation:^{
      [floatingView setNeedsLayout];
      [floatingView layoutIfNeeded];
      [floatingView setAlpha:0.0];
      [floatingView setTransform:CGAffineTransformMakeScale(0.82, 0.82)];
    }];
    [window setHidden:NO];
    [window bringSubviewToFront:[viewController view]];

    NSTimeInterval duration = MIN(MAX(self.floatingPreviewDuration,
                                      kMTPreferenceKeyFloatingPreviewDurationMinimumValue),
                                  kMTPreferenceKeyFloatingPreviewDurationMaximumValue);
    // The rim light sweep covers exactly the auto-hide countdown window.
    if (self.floatingPreviewCountdownRing) {
        [viewController startCountdownRingWithDuration:duration];
    } else {
        [viewController stopCountdownRing];
    }

    [UIView animateWithDuration:0.18
        animations:^{
          [[viewController view] setAlpha:1.0];
          [[viewController view] setTransform:CGAffineTransformIdentity];
        }
        completion:nil];

    __weak typeof(self) weakSelf = self;
    dispatch_block_t expirationBlock = dispatch_block_create(0, ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          return;
      }
      if (strongSelf.floatingPreviewDisplayToken != displayToken) {
          return;
      }
      [strongSelf hideFloatingPreviewAnimated:YES];
    });
    self.floatingPreviewExpirationBlock = expirationBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), expirationBlock);
}

- (void)handleFloatingPreviewTap {
    MTPasteboardItem *item = self.floatingPreviewItem;
    if (!item) {
        return;
    }

    [self hideFloatingPreviewAnimated:NO];
    [self showQuickPreviewForItem:item];
}

- (void)handleFloatingPreviewDoubleTap {
    if (![self floatingPreviewDoubleTapAction]) {
        return;
    }

    MTPasteboardItem *item = self.floatingPreviewItem;
    if (!item) {
        return;
    }

    [self presentFloatingPreviewActionsForItem:item];
}

- (void)presentFloatingPreviewActionsForItem:(MTPasteboardItem *)item {
    BOOL isImageItem = [[item imageName] length] > 0;
    MTQuickActionKind kind = isImageItem ? MTQuickActionKindImage : MTQuickActionKindText;
    NSArray<NSDictionary<NSString *, id> *> *actions = [MTQuickAction actionsForKind:kind];
    if ([actions count] == 0) {
        return;
    }

    [self cancelFloatingPreviewExpiration];
    // 悬浮面板已移除：直接执行第一个动作（单动作与多动作行为一致）。
    [self openFloatingPreviewAction:[actions firstObject] forItem:item];
}

- (void)openFloatingPreviewAction:(NSDictionary<NSString *, id> *)action
                          forItem:(MTPasteboardItem *)item {
    BOOL isImageItem = [[item imageName] length] > 0;
    if (!isImageItem) {
        [self hideFloatingPreviewAnimated:NO];
        __weak typeof(self) weakSelf = self;
        [MTQuickAction openAction:action
                                input:[item content] ?: @""
                    completionHandler:^(BOOL success) {
                      if (!success) {
                          [weakSelf playFailureHapticFeedbackIfNeeded];
                      }
                    }];
        return;
    }

    // 图片动作先把条目写回剪贴板（异步，不在主线程等 pasted IPC），成功后
    // 抑制本次内部写带来的新预览，再执行动作。
    __weak typeof(self) weakSelf = self;
    [[MTPasteboardManager sharedInstance] copyPasteboardItemToPasteboard:item
                                                                   completion:^(BOOL didUpdate) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!didUpdate) {
            [strongSelf hideFloatingPreviewAnimated:NO];
            [strongSelf playFailureHapticFeedbackIfNeeded];
            return;
        }
        // The image action intentionally writes the existing item back to the
        // pasteboard. Do not treat that internal write as a new floating preview.
        [strongSelf.pasteSuppressionState beginWithExpirationDelay:kMTPasteSuppressionExpirationDelay];

        [strongSelf hideFloatingPreviewAnimated:NO];
        [MTQuickAction openAction:action
                                input:@""
                    completionHandler:^(BOOL success) {
                      if (!success) {
                          [weakSelf playFailureHapticFeedbackIfNeeded];
                      }
                    }];
    }];
}

- (void)applyOverlayWindowFrame:(UIWindow *)window {
    CGRect bounds = [[UIScreen mainScreen] bounds];
    [window setFrame:bounds];
    [[window rootViewController].view setFrame:[window bounds]];
    [[window rootViewController].view setNeedsLayout];
}

- (void)tearDownOverlayWindowHost {
    [self.overlayWindow setHidden:YES];
    if ([self.overlayWindow rootViewController] == self.mainViewController) {
        [self.overlayWindow setRootViewController:nil];
    }
    [self.mainViewController setMtSupportedInterfaceOrientations:UIInterfaceOrientationMaskAll];
}

- (void)handleMainPanelDidHide {
    if ([self activePresentationMode] != MTPanelPresentationModeCompactLandscapeFullscreen &&
        [self.overlayWindow rootViewController] != self.mainViewController) {
        return;
    }

    [self tearDownOverlayWindowHost];
}

- (void)mainViewControllerDidRequestFocusRestore:(MTMainViewController *)viewController {
    if (viewController != self.mainViewController) {
        return;
    }

    [self requestHelperFocusRestore];
}

- (void)mainViewControllerDidHide:(MTMainViewController *)viewController {
    if (viewController != self.mainViewController) {
        return;
    }

    [self handleMainPanelDidHide];
}

- (BOOL)prepareCompactLandscapeHost {
    UIWindow *window = [self overlayWindowCreatingIfNeeded];
    if (!window) {
        return NO;
    }

    [self.mainViewController setOutsideDismissOverlayView:nil];
    [self.mainViewController
        setMtSupportedInterfaceOrientations:[self compactLandscapeSupportedInterfaceOrientations]];
    [self.mainViewController setPresentationMode:MTPanelPresentationModeCompactLandscapeFullscreen];
    [self applyOverlayWindowFrame:window];
    if ([window rootViewController] != self.mainViewController) {
        [[self.mainViewController view] removeFromSuperview];
        [window setRootViewController:self.mainViewController];
    }
    [window setHidden:NO];
    [self applyOverlayWindowFrame:window];

    UIView *panelView = [self.mainViewController view];
    [panelView setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
    [panelView setFrame:[self fullscreenPanelFrameInWindow:window]];
    [panelView setNeedsLayout];
    self.activePresentationMode = MTPanelPresentationModeCompactLandscapeFullscreen;
    return YES;
}

- (BOOL)preparePortraitHost {
    UIWindow *window = [self overlayWindowCreatingIfNeeded];
    if (!window) {
        return NO;
    }

    UIControl *outsideDismissOverlayView = [self ensurePortraitOutsideDismissOverlayInWindow:window];
    [self.mainViewController setOutsideDismissOverlayView:outsideDismissOverlayView];
    [self.mainViewController setMtSupportedInterfaceOrientations:UIInterfaceOrientationMaskAll];
    [self.mainViewController setPresentationMode:MTPanelPresentationModePortraitDrawer];

    UIView *panelView = [self.mainViewController view];
    [self applyOverlayWindowFrame:window];
    if ([window rootViewController] != self.mainViewController) {
        [panelView removeFromSuperview];
        [window setRootViewController:self.mainViewController];
    }
    [window setHidden:NO];
    [self applyOverlayWindowFrame:window];
    [window bringSubviewToFront:outsideDismissOverlayView];
    [window bringSubviewToFront:panelView];
    // Portrait floating card: center horizontally, pin to bottom with gaps.
    [panelView setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                   UIViewAutoresizingFlexibleTopMargin];
    [panelView setFrame:[self portraitPanelFrameInWindow:window]];
    [panelView setNeedsLayout];
    self.activePresentationMode = MTPanelPresentationModePortraitDrawer;
    return YES;
}

- (BOOL)preparePanelHostForPresentationMode:(MTPanelPresentationMode)presentationMode {
    if (!self.mainViewController) {
        return NO;
    }

    if (!CGAffineTransformIsIdentity([[self.mainViewController view] transform])) {
        [[self.mainViewController view] setTransform:CGAffineTransformIdentity];
    }

    if (presentationMode == MTPanelPresentationModeCompactLandscapeFullscreen) {
        return [self prepareCompactLandscapeHost];
    }

    return [self preparePortraitHost];
}

- (void)preloadInitialHistory {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    self.didRequestInitialHistoryPreload = YES;

    MTPasteboardManager *pasteboardManager = [MTPasteboardManager sharedInstance];
    [pasteboardManager warmUpHistoryAccess];

    if (self.mainViewController) {
        [self.mainViewController preloadHistoryIfNeeded];
    }
}

- (void)applyHeightPreferenceToViewApplyingWhenHidden:(BOOL)applyWhenHidden {
    if (!self.mainViewController) {
        return;
    }

    if (!applyWhenHidden && [self.mainViewController isHidden]) {
        return;
    }

    if ([self activePresentationMode] == MTPanelPresentationModeCompactLandscapeFullscreen) {
        UIWindow *window = self.overlayWindow;
        UIView *panelView = [self.mainViewController view];
        CGRect newFrame = [self fullscreenPanelFrameInWindow:window];
        if (!CGRectEqualToRect([panelView frame], newFrame)) {
            if (!CGAffineTransformIsIdentity([panelView transform])) {
                [panelView setTransform:CGAffineTransformIdentity];
            }
            [panelView setFrame:newFrame];
            [panelView setNeedsLayout];
        }
        return;
    }
    if ([self.mainViewController isFullscreenSearchActive] || [self.mainViewController isNoteEditing] ||
        [self.mainViewController isPreviewTextEditing]) {
        return;
    }

    UIView *panelView = [self.mainViewController view];
    UIWindow *hostWindow = (UIWindow *)[panelView superview];
    if (![hostWindow isKindOfClass:[UIWindow class]]) {
        hostWindow = self.statusBarWindow;
    }
    CGRect newFrame = [self portraitPanelFrameInWindow:hostWindow];
    if (!CGRectEqualToRect([panelView frame], newFrame)) {
        if (!CGAffineTransformIsIdentity([panelView transform])) {
            [panelView setTransform:CGAffineTransformIdentity];
        }
        [panelView setFrame:newFrame];
        [panelView setNeedsLayout];
    }
}

- (void)applyPreferencesToView {
    if (!self.mainViewController) {
        return;
    }

    if ([self.mainViewController automaticallyPaste] != self.automaticallyPaste) {
        [self.mainViewController setAutomaticallyPaste:self.automaticallyPaste];
    }
    if ([self.mainViewController privacyMode] != self.privacyMode) {
        [self.mainViewController setPrivacyMode:self.privacyMode];
    }
    if ([self.mainViewController dismissOnOutsideTouch] != self.dismissOnOutsideTouch) {
        [self.mainViewController setDismissOnOutsideTouch:self.dismissOnOutsideTouch];
    }
    if ([self.mainViewController swipeToSelectWords] != self.swipeToSelectWords) {
        [self.mainViewController setSwipeToSelectWords:self.swipeToSelectWords];
    }
    if ([self.mainViewController previewLineCount] != self.previewLineCount) {
        [self.mainViewController setPreviewLineCount:self.previewLineCount];
    }
    if ([self.mainViewController itemDetailsMode] != self.itemDetailsMode) {
        [self.mainViewController setItemDetailsMode:self.itemDetailsMode];
    }
    if ([self.mainViewController initialViewMode] != self.initialViewMode) {
        [self.mainViewController setInitialViewMode:self.initialViewMode];
    }
    if ([self.mainViewController alwaysScrollToTop] != self.alwaysScrollToTop) {
        [self.mainViewController setAlwaysScrollToTop:self.alwaysScrollToTop];
    }
    if ([self.mainViewController clearButtonMode] != self.clearButtonMode) {
        [self.mainViewController setClearButtonMode:self.clearButtonMode];
    }
    if ([self.mainViewController shouldPlayFeedback] != self.playHapticFeedback) {
        [self.mainViewController setShouldPlayFeedback:self.playHapticFeedback];
    }

    [self applyHeightPreferenceToViewApplyingWhenHidden:YES];
}

- (void)requestHelperFocusRestore {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kMTNotificationKeyHelperRestoreFocus, nil, nil, YES);
}

#pragma mark - Preferences

- (void)readPasteTipPreferencesFromPreferences:(NSUserDefaults *)preferences {
    // Metis 门控桥接：唯一整体开关权威是 com.lindo.metis（MTModuleGate）；
    // 旧模块键已退役，旧 Enabled 仅作为迁移导入源，运行端一律被总开关覆盖。
    [MTModuleGate reload];
    self.enabled = [MTModuleGate globalEnabled];
    self.pasteTipsDisabled = [[preferences objectForKey:kMTPreferenceKeyDisablePasteTips] boolValue];
}

- (BOOL)refreshPasteTipPreferences {
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
    [preferences registerDefaults:@{
        kMTPreferenceKeyEnabled : @(kMTPreferenceKeyEnabledDefaultValue),
        kMTPreferenceKeyDisablePasteTips : @(kMTPreferenceKeyDisablePasteTipsDefaultValue),
    }];

    [self readPasteTipPreferencesFromPreferences:preferences];
    return self.enabled;
}

- (void)loadHookShapePreferences {
    // dyld 加载期（MTClipboardCore constructor）调用：只读决定「装哪些 hook」的
    // 三项值。完整偏好应用（NSUserDefaults 套件初始化、40 项 registerDefaults、
    // 外观刷新）延后到主队列 / SB didFinishLaunching 的 loadPreferences。
    [MTModuleGate reload];
    self.enabled = [MTModuleGate globalEnabled];

    // 细节域（com.lindo.metis.clipboard）直读：SpringBoard 非沙盒，cfprefsd
    // 正常时即权威值；冷启动首解锁保护期读空时维持默认，后续 loadPreferences
    // 补齐。绝不读 MTX 旧插件域。
    CFStringRef domain = (__bridge CFStringRef)kMTClipboardPreferencesIdentifier;
    Boolean valid = false;
    CFIndex activation = CFPreferencesGetAppIntegerValue(
        (__bridge CFStringRef)kMTPreferenceKeyActivationMethod, domain, &valid);
    self.activationMethod =
        valid ? (NSUInteger)activation : kMTPreferenceKeyActivationMethodDefaultValue;
    CFIndex gestureMode = CFPreferencesGetAppIntegerValue(
        (__bridge CFStringRef)kMTPreferenceKeyGestureRecognizerMode, domain, &valid);
    self.gestureRecognizerMode =
        valid ? (MTGestureRecognizerMode)gestureMode : kMTPreferenceKeyGestureRecognizerModeDefaultValue;
    if (self.gestureRecognizerMode != kMTGestureRecognizerModeClassic &&
        self.gestureRecognizerMode != kMTGestureRecognizerModeSystem) {
        self.gestureRecognizerMode = kMTPreferenceKeyGestureRecognizerModeDefaultValue;
    }
}

- (void)loadPreferences {
    self.preferences = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
    [self.preferences registerDefaults:@{
        kMTPreferenceKeyEnabled : @(kMTPreferenceKeyEnabledDefaultValue),
        kMTPreferenceKeyActivationMethod : @(kMTPreferenceKeyActivationMethodDefaultValue),
        kMTPreferenceKeyPrivacyMode : @(kMTPreferenceKeyPrivacyModeDefaultValue),
        kMTPreferenceKeyFloatingPreview : @(kMTPreferenceKeyFloatingPreviewDefaultValue),
        kMTPreferenceKeyFloatingPreviewDoubleTapAction : @(kMTPreferenceKeyFloatingPreviewDoubleTapActionDefaultValue),
        kMTPreferenceKeyFloatingPreviewCountdownRing : @(kMTPreferenceKeyFloatingPreviewCountdownRingDefaultValue),
        kMTPreferenceKeyFloatingPreviewSize : @(kMTPreferenceKeyFloatingPreviewSizeDefaultValue),
        kMTPreferenceKeyFloatingPreviewDuration : @(kMTPreferenceKeyFloatingPreviewDurationDefaultValue),
        kMTPreferenceKeyFloatingPreviewColor : kMTPreferenceKeyFloatingPreviewColorDefaultValue,
        kMTPreferenceKeyFloatingPreviewDockedRight : @(kMTPreferenceKeyFloatingPreviewDockedRightDefaultValue),
        kMTPreferenceKeyFloatingPreviewVerticalPosition : @(kMTPreferenceKeyFloatingPreviewVerticalPositionDefaultValue),
        kMTPreferenceKeyImageDoubleTapActionURL : kMTPreferenceKeyImageDoubleTapActionURLDefaultValue,
        kMTPreferenceKeyGestureRecognizerMode : @(kMTPreferenceKeyGestureRecognizerModeDefaultValue),
        kMTPreferenceKeyMaximumHistoryAmount : @(kMTPreferenceKeyMaximumHistoryAmountDefaultValue),
        kMTPreferenceKeySaveText : @(kMTPreferenceKeySaveTextDefaultValue),
        kMTPreferenceKeySaveImages : @(kMTPreferenceKeySaveImagesDefaultValue),
        kMTPreferenceKeySwipeToSelectWords : @(kMTPreferenceKeySwipeToSelectWordsDefaultValue),
        kMTPreferenceKeyAutomaticallyPaste : @(kMTPreferenceKeyAutomaticallyPasteDefaultValue),
        kMTPreferenceKeyAutomaticPasteMode : @(kMTPreferenceKeyAutomaticPasteModeDefaultValue),
        kMTPreferenceKeyAutomaticPromotionMode : @(kMTPreferenceKeyAutomaticPromotionModeDefaultValue),
        kMTPreferenceKeyInitialViewMode : @(kMTPreferenceKeyInitialViewModeDefaultValue),
        kMTPreferenceKeyAlwaysScrollToTop : @(kMTPreferenceKeyAlwaysScrollToTopDefaultValue),
        kMTPreferenceKeyClearButtonMode : @(kMTPreferenceKeyClearButtonModeDefaultValue),
        kMTPreferenceKeyDismissOnOutsideTouch : @(kMTPreferenceKeyDismissOnOutsideTouchDefaultValue),
        kMTPreferenceKeyDisablePasteTips : @(kMTPreferenceKeyDisablePasteTipsDefaultValue),
        kMTPreferenceKeyIgnoreRemoteReplication : @(kMTPreferenceKeyIgnoreRemoteReplicationDefaultValue),
        kMTPreferenceKeyApplicationBlacklist : @[],
        kMTPreferenceKeyPlaySoundEffects : @(kMTPreferenceKeyPlaySoundEffectsDefaultValue),
        kMTPreferenceKeyPlayHapticFeedback : @(kMTPreferenceKeyPlayHapticFeedbackDefaultValue),
        kMTPreferenceKeyPreviewLineCount : @(kMTPreferenceKeyPreviewLineCountDefaultValue),
        kMTPreferenceKeyItemDetailsMode : @(kMTPreferenceKeyItemDetailsModeDefaultValue),
        kMTPreferenceKeyHeightInPoints : @(kMTPreferenceKeyHeightInPointsDefaultValue),
        kMTPreferenceKeyOverlayWindowLevelMode : @(kMTPreferenceKeyOverlayWindowLevelModeDefaultValue),
        kMTPreferenceKeyOverlayWindowLevel : @(kMTPreferenceKeyOverlayWindowLevelDefaultValue),
    }];

    [self readPasteTipPreferencesFromPreferences:self.preferences];
    self.activationMethod = [[self.preferences objectForKey:kMTPreferenceKeyActivationMethod] unsignedIntegerValue];
    self.privacyMode = [[self.preferences objectForKey:kMTPreferenceKeyPrivacyMode] boolValue];
    self.floatingPreview = [[self.preferences objectForKey:kMTPreferenceKeyFloatingPreview] boolValue];
    self.floatingPreviewDoubleTapAction =
        [[self.preferences objectForKey:kMTPreferenceKeyFloatingPreviewDoubleTapAction] boolValue];
    self.floatingPreviewCountdownRing =
        [[self.preferences objectForKey:kMTPreferenceKeyFloatingPreviewCountdownRing] boolValue];
    self.floatingPreviewSize = [[self.preferences objectForKey:kMTPreferenceKeyFloatingPreviewSize] doubleValue];
    if (!isfinite(self.floatingPreviewSize)) {
        self.floatingPreviewSize = kMTPreferenceKeyFloatingPreviewSizeDefaultValue;
    }
    self.floatingPreviewSize = MIN(MAX(self.floatingPreviewSize,
                                       kMTPreferenceKeyFloatingPreviewSizeMinimumValue),
                                   kMTPreferenceKeyFloatingPreviewSizeMaximumValue);
    self.floatingPreviewDuration = [[self.preferences objectForKey:kMTPreferenceKeyFloatingPreviewDuration] doubleValue];
    if (!isfinite(self.floatingPreviewDuration)) {
        self.floatingPreviewDuration = kMTPreferenceKeyFloatingPreviewDurationDefaultValue;
    }
    self.floatingPreviewDuration = MIN(MAX(self.floatingPreviewDuration,
                                           kMTPreferenceKeyFloatingPreviewDurationMinimumValue),
                                       kMTPreferenceKeyFloatingPreviewDurationMaximumValue);
    NSString *floatingPreviewColorHex = [self.preferences stringForKey:kMTPreferenceKeyFloatingPreviewColor];
    self.floatingPreviewColor = MTFloatingPreviewColorFromHex(floatingPreviewColorHex);
    self.floatingPreviewDockedRight = [[self.preferences objectForKey:kMTPreferenceKeyFloatingPreviewDockedRight] boolValue];
    self.floatingPreviewVerticalPosition = [[self.preferences objectForKey:kMTPreferenceKeyFloatingPreviewVerticalPosition] doubleValue];
    if (!isfinite(self.floatingPreviewVerticalPosition)) {
        self.floatingPreviewVerticalPosition = kMTPreferenceKeyFloatingPreviewVerticalPositionDefaultValue;
    }
    self.floatingPreviewVerticalPosition = MIN(MAX(self.floatingPreviewVerticalPosition, 0.0), 1.0);
    [self applyFloatingPreviewAppearance];
    if (!self.enabled || !self.floatingPreview) {
        [self hideFloatingPreviewAnimated:NO];
    }
    self.gestureRecognizerMode =
        [[self.preferences objectForKey:kMTPreferenceKeyGestureRecognizerMode] unsignedIntegerValue];
    if (self.gestureRecognizerMode != kMTGestureRecognizerModeClassic &&
        self.gestureRecognizerMode != kMTGestureRecognizerModeSystem) {
        self.gestureRecognizerMode = kMTPreferenceKeyGestureRecognizerModeDefaultValue;
    }
    self.maximumHistoryAmount = [MTPasteboardManager
        normalizedMaximumHistoryAmountForValue:[[self.preferences objectForKey:kMTPreferenceKeyMaximumHistoryAmount]
                                                   unsignedIntegerValue]];
    self.saveText = [[self.preferences objectForKey:kMTPreferenceKeySaveText] boolValue];
    self.saveImages = [[self.preferences objectForKey:kMTPreferenceKeySaveImages] boolValue];
    self.swipeToSelectWords = [[self.preferences objectForKey:kMTPreferenceKeySwipeToSelectWords] boolValue];
    self.automaticallyPaste = [[self.preferences objectForKey:kMTPreferenceKeyAutomaticallyPaste] boolValue];
    self.automaticPasteMode =
        [[self.preferences objectForKey:kMTPreferenceKeyAutomaticPasteMode] unsignedIntegerValue];
    if (self.automaticPasteMode != kMTAutomaticPasteModeClassic &&
        self.automaticPasteMode != kMTAutomaticPasteModeSimulated &&
        self.automaticPasteMode != kMTAutomaticPasteModeAutomatic) {
        self.automaticPasteMode = kMTPreferenceKeyAutomaticPasteModeDefaultValue;
    }
    self.automaticPromotionMode =
        [[self.preferences objectForKey:kMTPreferenceKeyAutomaticPromotionMode] unsignedIntegerValue];
    if (self.automaticPromotionMode != kMTAutomaticPromotionModeOff &&
        self.automaticPromotionMode != kMTAutomaticPromotionModeHistoryOnly &&
        self.automaticPromotionMode != kMTAutomaticPromotionModeAlways) {
        self.automaticPromotionMode = kMTPreferenceKeyAutomaticPromotionModeDefaultValue;
    }
    self.initialViewMode = [[self.preferences objectForKey:kMTPreferenceKeyInitialViewMode] unsignedIntegerValue];
    if (self.initialViewMode != kMTInitialViewModeHistory &&
        self.initialViewMode != kMTInitialViewModeFavorites &&
        self.initialViewMode != kMTInitialViewModePreviousSelection) {
        self.initialViewMode = kMTPreferenceKeyInitialViewModeDefaultValue;
    }
    self.alwaysScrollToTop = [[self.preferences objectForKey:kMTPreferenceKeyAlwaysScrollToTop] boolValue];
    self.clearButtonMode = [[self.preferences objectForKey:kMTPreferenceKeyClearButtonMode] unsignedIntegerValue];
    if (self.clearButtonMode != kMTClearButtonModeOff &&
        self.clearButtonMode != kMTClearButtonModeHistoryOnly &&
        self.clearButtonMode != kMTClearButtonModeAlways) {
        self.clearButtonMode = kMTPreferenceKeyClearButtonModeDefaultValue;
    }
    self.dismissOnOutsideTouch = [[self.preferences objectForKey:kMTPreferenceKeyDismissOnOutsideTouch] boolValue];
    BOOL ignoreRemoteReplication =
        [[self.preferences objectForKey:kMTPreferenceKeyIgnoreRemoteReplication] boolValue];
    NSSet<NSString *> *applicationBlacklist =
        [NSSet setWithArray:[self.preferences arrayForKey:kMTPreferenceKeyApplicationBlacklist] ?: @[]];
    self.playSoundEffects = [[self.preferences objectForKey:kMTPreferenceKeyPlaySoundEffects] boolValue];
    self.playHapticFeedback = [[self.preferences objectForKey:kMTPreferenceKeyPlayHapticFeedback] boolValue];
    self.previewLineCount = [[self.preferences objectForKey:kMTPreferenceKeyPreviewLineCount] unsignedIntegerValue];
    self.itemDetailsMode = [[self.preferences objectForKey:kMTPreferenceKeyItemDetailsMode] unsignedIntegerValue];
    if (self.itemDetailsMode != kMTItemDetailsModeOff && self.itemDetailsMode != kMTItemDetailsModeImagesOnly &&
        self.itemDetailsMode != kMTItemDetailsModeAll) {
        self.itemDetailsMode = kMTPreferenceKeyItemDetailsModeDefaultValue;
    }
    self.heightInPoints = [[self.preferences objectForKey:kMTPreferenceKeyHeightInPoints] doubleValue];
    self.overlayWindowLevelMode =
        [[self.preferences objectForKey:kMTPreferenceKeyOverlayWindowLevelMode] unsignedIntegerValue];
    if (self.overlayWindowLevelMode != kMTOverlayWindowLevelModeCustom &&
        self.overlayWindowLevelMode != kMTOverlayWindowLevelModeMaximum) {
        self.overlayWindowLevelMode = kMTPreferenceKeyOverlayWindowLevelModeDefaultValue;
    }

    CGFloat customOverlayWindowLevel =
        [[self.preferences objectForKey:kMTPreferenceKeyOverlayWindowLevel] doubleValue];
    if (!isfinite(customOverlayWindowLevel) ||
        customOverlayWindowLevel < kMTPreferenceKeyOverlayWindowLevelMinimumValue ||
        customOverlayWindowLevel > kMTPreferenceKeyOverlayWindowLevelMaximumValue) {
        customOverlayWindowLevel = kMTPreferenceKeyOverlayWindowLevelDefaultValue;
    }
    self.customOverlayWindowLevel = round(customOverlayWindowLevel);

    MTPasteboardManager *pasteboardManager = [MTPasteboardManager sharedInstance];
    if ([pasteboardManager maximumHistoryAmount] != self.maximumHistoryAmount) {
        [pasteboardManager setMaximumHistoryAmount:self.maximumHistoryAmount];
    }
    if ([pasteboardManager saveText] != self.saveText) {
        [pasteboardManager setSaveText:self.saveText];
    }
    if ([pasteboardManager saveImages] != self.saveImages) {
        [pasteboardManager setSaveImages:self.saveImages];
    }
    if ([pasteboardManager automaticallyPaste] != self.automaticallyPaste) {
        [pasteboardManager setAutomaticallyPaste:self.automaticallyPaste];
    }
    if ([pasteboardManager automaticPasteMode] != self.automaticPasteMode) {
        [pasteboardManager setAutomaticPasteMode:self.automaticPasteMode];
    }
    if ([pasteboardManager automaticPromotionMode] != self.automaticPromotionMode) {
        [pasteboardManager setAutomaticPromotionMode:self.automaticPromotionMode];
    }
    if ([pasteboardManager ignoreRemoteReplication] != ignoreRemoteReplication) {
        [pasteboardManager setIgnoreRemoteReplication:ignoreRemoteReplication];
    }
    if (![[pasteboardManager applicationBlacklist] isEqualToSet:applicationBlacklist]) {
        [pasteboardManager setApplicationBlacklist:applicationBlacklist];
    }

    [self applyPreferencesToView];
}

- (void)loadHeightPreference {
    NSUserDefaults *heightPreferences = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
    [heightPreferences registerDefaults:@{
        kMTPreferenceKeyHeightInPoints : @(kMTPreferenceKeyHeightInPointsDefaultValue),
    }];
    self.heightInPoints = [[heightPreferences objectForKey:kMTPreferenceKeyHeightInPoints] doubleValue];
    if (self.pendingHeightPreferenceApply) {
        return;
    }

    self.pendingHeightPreferenceApply = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
      self.pendingHeightPreferenceApply = NO;
      [self applyHeightPreferenceToViewApplyingWhenHidden:NO];
    });
}

#pragma mark - Device State

- (BOOL)readUILocked:(BOOL *)locked {
    Class<MTSBLockScreenManagerClass> managerClass =
        (Class<MTSBLockScreenManagerClass>)NSClassFromString(@"SBLockScreenManager");
    if (![managerClass respondsToSelector:@selector(sharedInstance)]) {
        return NO;
    }

    SBLockScreenManager *manager = [managerClass sharedInstance];
    if (![manager respondsToSelector:@selector(isUILocked)]) {
        return NO;
    }

    if (locked) {
        *locked = [manager isUILocked];
    }
    return YES;
}

- (UIUserInterfaceStyle)userInterfaceStyleFromSceneSettings:(UIApplicationSceneSettings *)settings {
    if (![settings respondsToSelector:@selector(userInterfaceStyle)]) {
        return UIUserInterfaceStyleUnspecified;
    }

    NSInteger style = (NSInteger)[settings userInterfaceStyle];
    if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
        return (UIUserInterfaceStyle)style;
    }
    return UIUserInterfaceStyleUnspecified;
}

- (UIUserInterfaceStyle)userInterfaceStyleFromKeyboardAppearance:(NSInteger)keyboardAppearance {
    switch ((UIKeyboardAppearance)keyboardAppearance) {
    case UIKeyboardAppearanceDark:
        return UIUserInterfaceStyleDark;
    case UIKeyboardAppearanceLight:
        return UIUserInterfaceStyleLight;
    default:
        return UIUserInterfaceStyleUnspecified;
    }
}

- (UIUserInterfaceStyle)userInterfaceStyleFromKeyboardAppearanceProvider:
    (NSObject<MTKeyboardAppearanceProviding> *)provider {
    if (![provider respondsToSelector:@selector(keyboardAppearance)]) {
        return UIUserInterfaceStyleUnspecified;
    }

    return [self userInterfaceStyleFromKeyboardAppearance:[provider keyboardAppearance]];
}

- (UIUserInterfaceStyle)currentSpringBoardKeyboardUserInterfaceStyle {
    Class<MTUIKeyboardImplClass> keyboardImplClass =
        (Class<MTUIKeyboardImplClass>)NSClassFromString(@"UIKeyboardImpl");
    if (![keyboardImplClass respondsToSelector:@selector(activeInstance)]) {
        return UIUserInterfaceStyleUnspecified;
    }

    UIKeyboardImpl *keyboardImpl = [keyboardImplClass activeInstance];
    if ([keyboardImpl respondsToSelector:@selector(textInputTraits)]) {
        UIUserInterfaceStyle style =
            [self userInterfaceStyleFromKeyboardAppearanceProvider:[keyboardImpl textInputTraits]];
        if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
            return style;
        }
    }

    if ([keyboardImpl respondsToSelector:@selector(inputDelegate)]) {
        UIUserInterfaceStyle style =
            [self userInterfaceStyleFromKeyboardAppearanceProvider:[keyboardImpl inputDelegate]];
        if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
            return style;
        }
    }

    return [keyboardImpl respondsToSelector:@selector(delegate)]
               ? [self userInterfaceStyleFromKeyboardAppearanceProvider:[keyboardImpl delegate]]
               : UIUserInterfaceStyleUnspecified;
}

- (UIUserInterfaceStyle)currentKeyboardHostUserInterfaceStyle {
    MTKeyboardHostResolver *resolver = [MTKeyboardHostResolver sharedResolver];
    FBScene *hostScene = [resolver currentKeyboardHostScene];
    if ([resolver sceneIsHostedBySpringBoard:hostScene]) {
        UIUserInterfaceStyle style = [self currentSpringBoardKeyboardUserInterfaceStyle];
        if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
            return style;
        }
    }

    if ([resolver sceneIsSpotlightScene:hostScene]) {
        return UIUserInterfaceStyleDark;
    }

    return [self userInterfaceStyleFromSceneSettings:[resolver settingsForScene:hostScene]];
}

- (void)applyKeyboardHostUserInterfaceStyle:(UIUserInterfaceStyle)style {
    if (!self.mainViewController || (style != UIUserInterfaceStyleLight && style != UIUserInterfaceStyleDark)) {
        return;
    }

    [self.mainViewController applyUserInterfaceStyle:style];
}

- (void)applyCurrentKeyboardHostUserInterfaceStyle {
    [self applyKeyboardHostUserInterfaceStyle:[self currentKeyboardHostUserInterfaceStyle]];
}

- (BOOL)sceneIsCurrentKeyboardHostScene:(FBScene *)scene {
    return [[MTKeyboardHostResolver sharedResolver] sceneIsCurrentKeyboardHostScene:scene];
}

- (void)handleScene:(FBScene *)scene didUpdateSettings:(UIApplicationSceneSettings *)settings {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self handleScene:scene didUpdateSettings:settings];
        });
        return;
    }

    if (![self panelVisible] || ![self sceneIsCurrentKeyboardHostScene:scene]) {
        return;
    }

    MTKeyboardHostResolver *resolver = [MTKeyboardHostResolver sharedResolver];
    UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
    if ([resolver sceneIsHostedBySpringBoard:scene]) {
        style = [self currentSpringBoardKeyboardUserInterfaceStyle];
    }
    if (style != UIUserInterfaceStyleLight && style != UIUserInterfaceStyleDark) {
        style = [resolver sceneIsSpotlightScene:scene] ? UIUserInterfaceStyleDark
                                                       : [self userInterfaceStyleFromSceneSettings:settings];
    }
    [self applyKeyboardHostUserInterfaceStyle:style];
}

- (BOOL)frontmostAppIsLandscape {
    return UIInterfaceOrientationIsLandscape([self frontmostAppInterfaceOrientation]);
}

- (BOOL)deviceUsesCompactLandscapePresentation {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone && [self frontmostAppIsLandscape];
}

- (MTPanelPresentationMode)currentPresentationMode {
    return [self deviceUsesCompactLandscapePresentation] ? MTPanelPresentationModeCompactLandscapeFullscreen
                                                         : MTPanelPresentationModePortraitDrawer;
}


- (void)startLockStateObserver {
    if (self.lockStateToken != 0) {
        return;
    }

    int status = notify_register_dispatch("com.apple.springboard.lockstate", &_lockStateToken,
                                          dispatch_get_main_queue(), ^(int token) {
                                            (void)token;
                                            [self handleLockStateNotification];
                                          });
    if (status != NOTIFY_STATUS_OK) {
        HBLogDebug(@"Mt: Unable to observe SpringBoard lock state: %d", status);
        self.lockStateToken = 0;
    }
}

- (void)handleLockStateNotification {
    BOOL locked = NO;
    if (![self readUILocked:&locked] || !locked) {
        return;
    }

    [self hideImmediately];
}

#pragma mark - Feedback

- (AVAudioPlayer *)audioPlayerForSound:(NSString *)soundName {
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient
                                     withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                           error:&error];
    if (error) {
        HBLogDebug(@"Mt: Failed to configure audio session: %@", error);
    }

    NSString *relativeSoundPath =
        [NSString stringWithFormat:@"/Library/PreferenceBundles/MetisClipboardPrefs.bundle/%@.aiff", soundName];
    NSString *soundPath = jbroot(relativeSoundPath);
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:soundPath]
                                                                   error:&error];
    if (error) {
        HBLogDebug(@"Mt: Failed to load %@ sound: %@", soundName, error);
        return nil;
    }

    [player prepareToPlay];
    return player;
}

- (nullable AVAudioPlayer *)playFeedbackSoundWithPlayer:(nullable AVAudioPlayer *)player
                                              soundName:(NSString *)soundName {
    if (!player) {
        player = [self audioPlayerForSound:soundName];
    }

    [player setCurrentTime:0];
    [player play];
    return player;
}

- (void)playSuccessHapticFeedbackIfNeeded {
    if (self.playHapticFeedback) {
        AudioServicesPlaySystemSound(1519);
    }
}

- (void)playFailureHapticFeedbackIfNeeded {
    if (self.playHapticFeedback) {
        AudioServicesPlaySystemSound(1521);
    }
}

- (void)playPasteFeedback {
    NSTimeInterval now = CACurrentMediaTime();
    if (fabs(now - self.lastPasteFeedbackOccurred) < kMTMinimumFeedbackInterval) {
        return;
    }
    self.lastPasteFeedbackOccurred = now;
    if (self.playSoundEffects) {
        self.pasteFeedbackSoundPlayer = [self playFeedbackSoundWithPlayer:self.pasteFeedbackSoundPlayer
                                                                soundName:@"Paste"];
    }
    [self playSuccessHapticFeedbackIfNeeded];
}

#pragma mark - Pasteboard

- (void)markPasteWillStart {
    [self.pasteSuppressionState beginWithExpirationDelay:kMTPasteSuppressionExpirationDelay];
}

- (void)capturePasteboardChange {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self capturePasteboardChangeNow];
    });
}

- (void)capturePasteboardChangeNow {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[MTPasteboardManager sharedInstance] pullPasteboardChangesWithCompletion:^(BOOL didSaveAnyItem) {
      if ([self.pasteSuppressionState consumeIfActive]) {
          return;
      }
      if (!didSaveAnyItem) {
          return;
      }

      if (self.floatingPreview && self.enabled && self.mainViewController &&
          ![self.mainViewController isEditingAnyContent]) {
          MTPasteboardItem *latestItem = [[MTPasteboardManager sharedInstance] getLatestHistoryItem];
          if (latestItem) {
              [self showFloatingPreviewForItem:latestItem];
          }
      }

      NSTimeInterval now = CACurrentMediaTime();
      if (fabs(now - self.lastCopyFeedbackOccurred) < kMTMinimumFeedbackInterval) {
          return;
      }
      self.lastCopyFeedbackOccurred = now;
      if (self.playSoundEffects) {
          self.clipboardFeedbackSoundPlayer = [self playFeedbackSoundWithPlayer:self.clipboardFeedbackSoundPlayer
                                                                      soundName:@"Copy"];
      }
      [self playSuccessHapticFeedbackIfNeeded];
    }];
}

- (void)showQuickPreviewForItem:(MTPasteboardItem *)item {
    if (!item || [self isPackageMaintenanceMode] || !self.mainViewController || ![self.mainViewController isHidden]) {
        return;
    }

    BOOL locked = NO;
    if ([self readUILocked:&locked] && locked) {
        [self playFailureHapticFeedbackIfNeeded];
        return;
    }

    MTPanelPresentationMode presentationMode = [self currentPresentationMode];
    if (![self preparePanelHostForPresentationMode:presentationMode]) {
        [self playFailureHapticFeedbackIfNeeded];
        return;
    }

    [self applyHeightPreferenceToViewApplyingWhenHidden:YES];
    [self.mainViewController applyUserInterfaceStyle:UIUserInterfaceStyleUnspecified];
    [self applyCurrentKeyboardHostUserInterfaceStyle];
    [self.mainViewController showQuickPreviewForItem:item];
}

#pragma mark - Visibility

- (void)show {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    if (!self.mainViewController || ![self.mainViewController isHidden]) {
        return;
    }

    [self hideFloatingPreviewAnimated:NO];

    BOOL locked = NO;
    if ([self readUILocked:&locked] && locked) {
        [self playFailureHapticFeedbackIfNeeded];
        return;
    }

    MTPanelPresentationMode presentationMode = [self currentPresentationMode];
    if (![self preparePanelHostForPresentationMode:presentationMode]) {
        [self playFailureHapticFeedbackIfNeeded];
        return;
    }


    [self applyHeightPreferenceToViewApplyingWhenHidden:YES];
    [self.mainViewController applyUserInterfaceStyle:UIUserInterfaceStyleUnspecified];
    [self applyCurrentKeyboardHostUserInterfaceStyle];

    [self.mainViewController show];

    if (self.activationMethod & kActivationMethodDictationKey) {
        [self playSuccessHapticFeedbackIfNeeded];
    }
}

- (void)hideWithAnimationStyle:(MTPanelHideAnimationStyle)animationStyle {
    // Panel-level hides are driven by transient system UI hooks (home screen
    // appearance, spotlight dismissal, text-effects window rotation, ...). Those
    // events cluster right after SpringBoard launch and must not dismiss the
    // floating preview; the panel and the preview are never visible together, so
    // a hide only matters when the panel itself is on screen.
    if (self.mainViewController && ![self.mainViewController isHidden]) {
        [self.mainViewController hideWithAnimationStyle:animationStyle completion:nil];
    }
}

- (void)hideForExternalRequest {
    if (!self.mainViewController || [self.mainViewController isHidden]) {
        return;
    }

    [self.mainViewController hideForExternalRequestWithAnimationStyle:MTPanelHideAnimationStyleDefault
                                                           completion:nil];
}

- (void)hide {
    [self hideWithAnimationStyle:MTPanelHideAnimationStyleDefault];
}

- (void)hideWithStandardDismissAnimation {
    if (self.mainViewController && ![self.mainViewController isHidden]) {
        [self.mainViewController hideWithStandardDismissAnimation];
    }
}

- (void)hideForRotation {
    [self hideWithAnimationStyle:MTPanelHideAnimationStyleFade];
}

- (void)hideImmediately {
    [self hideFloatingPreviewAnimated:NO];
    if (self.mainViewController && ![self.mainViewController isHidden]) {
        [self.mainViewController hideImmediately];
    }
}

- (void)reloadHistory {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    if (self.mainViewController) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.mainViewController handleHistoryChanged];
        });
    }
}

- (void)handleApplicationMetadataChanged {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    if (self.mainViewController) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.mainViewController handleApplicationMetadataChanged];
        });
    }
}

- (void)checkpointHistoryDatabase {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[MTPasteboardManager sharedInstance] checkpointHistoryDatabase];
}

- (void)prepareForPackageMaintenance {
    [self setPackageMaintenanceMode:YES];
    [[MTPasteboardManager sharedInstance] enterMaintenanceModeUntilProcessExit];
    [self hideImmediately];
}

- (void)resetThumbnailMemoryCache {
    [[MTPasteboardManager sharedInstance] resetThumbnailMemoryCache];
}

- (void)clearFavorites {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[MTPasteboardManager sharedInstance] removeAllPasteboardItemsFromHistoryWithKey:kMTHistoryKeyFavorites
                                                                      shouldRemoveImages:YES
                                                                              completion:nil];
}

- (void)clearHistory {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[MTPasteboardManager sharedInstance] removeAllPasteboardItemsFromHistoryWithKey:kMTHistoryKeyHistory
                                                                      shouldRemoveImages:YES
                                                                              completion:nil];
}

@end
