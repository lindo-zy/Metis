#import "DXPanelControlSession.h"
#import "DXPanelControlState.h"

@interface DXPanelControlSession ()
@property(nonatomic, copy) DXPanelControlRequester requester;
@property(nonatomic, copy) BOOL (^validity)(void);
@property(nonatomic, copy) void (^update)(DXSystemOpenResult, NSDictionary *, BOOL, NSString *);
@property(nonatomic, strong) NSMutableArray<NSString *> *order;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *values;
@property(nonatomic, strong) NSProgress *operation;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL invalid;
@property(nonatomic) BOOL pumpScheduled;
@property(nonatomic, strong) NSDictionary *lastState;
@property(nonatomic) NSUInteger serial;
@property(nonatomic) NSTimeInterval nextWrite;
@end
@implementation DXPanelControlSession
- (instancetype)initWithRequester:(DXPanelControlRequester)requester validity:(BOOL (^)(void))validity
                           update:(void (^)(DXSystemOpenResult, NSDictionary *, BOOL, NSString *))update {
    if ((self = [super init])) {
        _requester = [requester copy]; _validity = [validity copy]; _update = [update copy];
        _order = [NSMutableArray array]; _values = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)enqueueAction:(NSString *)action value:(NSNumber *)value {
    if (self.invalid || !NSThread.isMainThread || ![action isKindOfClass:NSString.class] ||
        !([DXPanelToggleIdentifiers() containsObject:action] || [@[@"state", @"brightness", @"volume"] containsObject:action])) return;
    if (!self.validity || !self.validity()) { [self invalidate]; return; }
    if ([action isEqual:@"state"] && (self.busy || self.order.count)) return;
    // Coalesce only unsent values. A request already submitted is never retried.
    if (!self.values[action]) [self.order addObject:action];
    self.values[action] = value ?: NSNull.null;
    [self pump];
}
- (void)pump {
    if (self.invalid || self.busy || !self.order.count) return;
    if (!self.validity || !self.validity()) { [self invalidate]; return; }
    NSTimeInterval delay = self.nextWrite - NSProcessInfo.processInfo.systemUptime;
    if (delay > 0) {
        if (!self.pumpScheduled) {
            self.pumpScheduled = YES;
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                weakSelf.pumpScheduled = NO; [weakSelf pump];
            });
        }
        return;
    }
    NSString *action = self.order.firstObject;
    id value = self.values[action];
    [self.order removeObjectAtIndex:0]; [self.values removeObjectForKey:action];
    self.busy = YES;
    NSUInteger serial = ++self.serial;
    self.nextWrite = NSProcessInfo.processInfo.systemUptime + 0.1;
    // Background reads share the transport flight guard, but must not put the
    // UI into its disabled state every second. Only writes block further taps.
    if (self.update && ![action isEqual:@"state"]) self.update(DXSystemOpenSucceeded, nil, YES, @"state");
    __weak typeof(self) weakSelf = self;
    NSProgress *operation = self.requester(action, value == NSNull.null ? nil : value, ^(DXSystemOpenResult result, NSDictionary *state) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DXPanelControlSession *self = weakSelf;
            if (!self || self.invalid || self.serial != serial || !self.busy) return;
            if (!self.validity || !self.validity()) { [self invalidate]; return; }
            self.busy = NO; self.operation = nil;
            if (result == DXSystemOpenTimedOut || result == DXSystemOpenExpired || result == DXSystemOpenUnavailable) {
                [self.order removeAllObjects]; [self.values removeAllObjects];
            }
            // Pending/dragged values must not jump back to an older reply.
            NSMutableDictionary *visible = [state mutableCopy];
            if (state) {
                for (NSString *key in self.order) {
                    id queued = self.values[key];
                    id preserved = queued != NSNull.null ? queued : self.lastState[key];
                    if (preserved) visible[key] = preserved;
                }
                self.lastState = [state copy];
            } else if (result != DXSystemOpenSucceeded) visible = [NSMutableDictionary dictionary];
            if (self.update) self.update(result, visible, self.order.count > 0, action);
            [self pump];
            if (!self.busy && !self.order.count && result == DXSystemOpenSucceeded) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    DXPanelControlSession *current = weakSelf;
                    if (!current || current.invalid || current.serial != serial) return;
                    [current enqueueAction:@"state" value:nil];
                });
            }
        });
    });
    if (self.busy && self.serial == serial && !self.invalid) self.operation = operation;
    else [operation cancel];
}
- (void)invalidate {
    if (self.invalid) return;
    self.invalid = YES; self.serial++;
    [self.operation cancel]; self.operation = nil;
    [self.order removeAllObjects]; [self.values removeAllObjects];
    self.busy = NO;
    self.requester = nil; self.validity = nil; self.update = nil;
}
- (void)dealloc { [_operation cancel]; }
@end
