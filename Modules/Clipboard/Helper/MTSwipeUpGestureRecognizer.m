//
//  MTSwipeUpGestureRecognizer.m
//  Mt
//

#import "MTSwipeUpGestureRecognizer.h"

#include <math.h>

static CGFloat const kMTSwipeUpDefaultMinimumPrimaryMovement = 240.0;
static CGFloat const kMTSwipeUpDefaultMinimumPrimaryMovementRate = 440.0;
static CGFloat const kMTSwipeUpDefaultMinimumSecondaryMovement = 0.0;
static CGFloat const kMTSwipeUpDefaultMaximumPrimaryMovement = CGFLOAT_MAX;
static CGFloat const kMTSwipeUpDefaultMaximumSecondaryMovement = 64.0;
static CGFloat const kMTSwipeUpDefaultMaximumOppositeMovement = 6.0;
static CGFloat const kMTSwipeUpDefaultRateOfMinimumMovementDecay = 0.28;
static CGFloat const kMTSwipeUpDefaultRateOfMaximumMovementDecay = 0.12;
static NSTimeInterval const kMTSwipeUpDefaultMaximumDuration = 0.5;
static NSTimeInterval const kMTSwipeUpMovementDecayDuration = 0.5;
static NSTimeInterval const kMTSwipeUpMinimumTimeDelta = 0.01;

typedef NS_ENUM(NSUInteger, MTSwipeUpCheckResult) {
    MTSwipeUpCheckResultPending = 0,
    MTSwipeUpCheckResultRecognized,
    MTSwipeUpCheckResultFailed,
};

@implementation MTSwipeUpGestureRecognizer {
    UITouch *_trackedTouch;
    CGPoint _startLocation;
    CGPoint _previousLocation;
    NSTimeInterval _startTime;
    NSTimeInterval _previousTime;
    BOOL _failed;
}

- (instancetype)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithTarget:target action:action];
    if (self) {
        _minimumPrimaryMovement = kMTSwipeUpDefaultMinimumPrimaryMovement;
        _minimumPrimaryMovementRate = kMTSwipeUpDefaultMinimumPrimaryMovementRate;
        _minimumSecondaryMovement = kMTSwipeUpDefaultMinimumSecondaryMovement;
        _maximumPrimaryMovement = kMTSwipeUpDefaultMaximumPrimaryMovement;
        _maximumSecondaryMovement = kMTSwipeUpDefaultMaximumSecondaryMovement;
        _maximumOppositeMovement = kMTSwipeUpDefaultMaximumOppositeMovement;
        _maximumDuration = kMTSwipeUpDefaultMaximumDuration;
        _rateOfMinimumMovementDecay = kMTSwipeUpDefaultRateOfMinimumMovementDecay;
        _rateOfMaximumMovementDecay = kMTSwipeUpDefaultRateOfMaximumMovementDecay;
    }
    return self;
}

- (void)reset {
    [super reset];

    _trackedTouch = nil;
    _startLocation = CGPointZero;
    _previousLocation = CGPointZero;
    _startTime = 0;
    _previousTime = 0;
    _failed = NO;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.state != UIGestureRecognizerStatePossible) {
        return;
    }

    if (_trackedTouch || touches.count != 1) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }

    _trackedTouch = [touches anyObject];
    _startLocation = [_trackedTouch locationInView:self.view];
    _previousLocation = _startLocation;
    _startTime = _trackedTouch.timestamp;
    _previousTime = _startTime;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.state != UIGestureRecognizerStatePossible || !_trackedTouch || ![touches containsObject:_trackedTouch]) {
        return;
    }

    CGPoint location = [_trackedTouch locationInView:self.view];
    NSTimeInterval timestamp = _trackedTouch.timestamp;
    NSTimeInterval duration = timestamp - _startTime;

    if (duration > self.maximumDuration) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }

    CGPoint delta = CGPointMake(location.x - _startLocation.x, location.y - _startLocation.y);
    CGPoint currentPositionChange = CGPointMake(location.x - _previousLocation.x, location.y - _previousLocation.y);
    NSTimeInterval currentTimeChange = timestamp - _previousTime;

    MTSwipeUpCheckResult result = [self checkForSwipeWithDelta:delta
                                                              time:duration
                                             currentPositionChange:currentPositionChange
                                                 currentTimeChange:currentTimeChange];
    _previousLocation = location;
    _previousTime = timestamp;

    if (result == MTSwipeUpCheckResultRecognized) {
        self.state = UIGestureRecognizerStateRecognized;
        return;
    }

    if (result == MTSwipeUpCheckResultFailed) {
        self.state = UIGestureRecognizerStateFailed;
    }
}

- (MTSwipeUpCheckResult)checkForSwipeWithDelta:(CGPoint)delta
                                              time:(NSTimeInterval)time
                             currentPositionChange:(CGPoint)currentPositionChange
                                 currentTimeChange:(NSTimeInterval)currentTimeChange {
    if (_failed) {
        return MTSwipeUpCheckResultFailed;
    }

    CGFloat effectiveMinimumPrimaryMovement = [self decayedMovementThreshold:self.minimumPrimaryMovement
                                                                        time:time
                                                                        rate:self.rateOfMinimumMovementDecay];
    CGFloat effectiveMaximumPrimaryMovement = [self decayedMovementThreshold:self.maximumPrimaryMovement
                                                                        time:time
                                                                        rate:self.rateOfMaximumMovementDecay];
    CGFloat effectiveMinimumSecondaryMovement = [self decayedMovementThreshold:self.minimumSecondaryMovement
                                                                          time:time
                                                                          rate:self.rateOfMinimumMovementDecay];
    CGFloat effectiveMaximumSecondaryMovement = [self decayedMovementThreshold:self.maximumSecondaryMovement
                                                                          time:time
                                                                          rate:self.rateOfMaximumMovementDecay];

    if (delta.y > self.maximumOppositeMovement) {
        _failed = YES;
        return MTSwipeUpCheckResultFailed;
    }

    CGFloat primaryMovement = fabs(delta.y);
    CGFloat secondaryMovement = fabs(delta.x);
    if (primaryMovement > effectiveMaximumPrimaryMovement || secondaryMovement > effectiveMaximumSecondaryMovement) {
        _failed = YES;
        return MTSwipeUpCheckResultFailed;
    }

    if (primaryMovement < effectiveMinimumPrimaryMovement || secondaryMovement < effectiveMinimumSecondaryMovement) {
        return MTSwipeUpCheckResultPending;
    }

    NSTimeInterval averageDuration = MAX(time, kMTSwipeUpMinimumTimeDelta);
    CGFloat averagePrimaryMovementRate = primaryMovement / averageDuration;
    NSTimeInterval movementDuration = MAX(currentTimeChange, kMTSwipeUpMinimumTimeDelta);
    CGFloat currentPrimaryMovementRate = fabs(currentPositionChange.y / movementDuration);
    if (averagePrimaryMovementRate < self.minimumPrimaryMovementRate ||
        currentPrimaryMovementRate < self.minimumPrimaryMovementRate) {
        return MTSwipeUpCheckResultPending;
    }

    return MTSwipeUpCheckResultRecognized;
}

- (CGFloat)decayedMovementThreshold:(CGFloat)threshold time:(NSTimeInterval)time rate:(CGFloat)rate {
    if (threshold == 0.0 || threshold == CGFLOAT_MAX) {
        return threshold;
    }

    NSTimeInterval cappedTime = MIN(time, kMTSwipeUpMovementDecayDuration);
    return threshold * (1.0 - cappedTime * (1.0 - rate));
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_trackedTouch && [touches containsObject:_trackedTouch] && self.state == UIGestureRecognizerStatePossible) {
        self.state = UIGestureRecognizerStateFailed;
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_trackedTouch && [touches containsObject:_trackedTouch] && self.state == UIGestureRecognizerStatePossible) {
        self.state = UIGestureRecognizerStateCancelled;
    }
}

@end
