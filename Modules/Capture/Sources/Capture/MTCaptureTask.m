#import "MTCaptureTask.h"
#import "../Common/MTConstants.h"
#import "../Common/MTClaimSet.h"
#import "../Common/MTCaptureLog.h"
#import "../Output/MTTemporaryFileStore.h"

@interface MTCaptureTask ()
@property (nonatomic, assign, readwrite) MTCaptureState state;
@property (nonatomic, strong, readwrite) MTConfig *configSnapshot;
@property (nonatomic, copy, readwrite) NSString *taskID;
@property (nonatomic, assign, readwrite) MTCaptureMode mode;
@property (nonatomic, assign, readwrite) CGRect capturedScreenBounds;
@property (nonatomic, assign, readwrite) CGFloat capturedScreenScale;
@property (nonatomic, strong) NSLock *stateLock;
@property (nonatomic, strong) MTClaimSet *claimSet;
@end

@implementation MTCaptureTask

- (instancetype)initWithMode:(MTCaptureMode)mode
                      config:(MTConfig *)config
                screenBounds:(CGRect)screenBounds
                 screenScale:(CGFloat)screenScale {
    if (self = [super init]) {
        _taskID = [[NSUUID UUID] UUIDString];
        _mode = mode;
        _configSnapshot = config;
        _capturedScreenBounds = screenBounds;
        _capturedScreenScale = screenScale;
        _state = MTCaptureStateIdle;
        _stateLock = [[NSLock alloc] init];
        _claimSet = [[MTClaimSet alloc] init];
    }
    return self;
}

- (BOOL)transitionToState:(MTCaptureState)target {
    [self.stateLock lock];
    BOOL allowed = MTCaptureStateCanTransition(self.state, target);
    if (allowed) {
        self.state = target;
    }
    [self.stateLock unlock];
    if (!allowed) {
        MTCaptureLogWarn(@"illegal transition %@ -> %@ (task %@)",
                  MTStringFromCaptureState(self.state), MTStringFromCaptureState(target), self.taskID);
    }
    return allowed;
}

- (MTCaptureState)currentState {
    [self.stateLock lock];
    MTCaptureState state = self.state;
    [self.stateLock unlock];
    return state;
}

- (BOOL)claimOutputAction:(MTOutputAction)action {
    BOOL claimed = [self.claimSet claimAction:(NSInteger)action];
    if (!claimed) {
        MTCaptureLogWarn(@"output action %@ already claimed (task %@)", MTStringFromOutputAction(action), self.taskID);
    }
    return claimed;
}

- (BOOL)isOutputActionClaimed:(MTOutputAction)action {
    return [self.claimSet isActionClaimed:(NSInteger)action];
}

- (void)unclaimOutputAction:(MTOutputAction)action {
    [self.claimSet unclaimAction:(NSInteger)action];
}

- (NSString *)ensureTemporaryDirectory {
    return [MTTemporaryFileStore directoryForTaskID:self.taskID create:YES];
}

- (nullable NSString *)existingTemporaryDirectory {
    return [MTTemporaryFileStore directoryForTaskID:self.taskID create:NO];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<MTCaptureTask %@ mode=%@ state=%@>",
            self.taskID, MTStringFromCaptureMode(self.mode), MTStringFromCaptureState(self.state)];
}

- (void)dealloc {
    // 防御性断引用：任务释放时不应再持有大图。
    _baseImage = nil;
    _resultImage = nil;
}

@end
