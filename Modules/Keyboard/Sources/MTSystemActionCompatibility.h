#import "MTSystemActionInvocation.h"
#import "MTDarwinOpenChannel.h"

static inline MTSystemOpenResult MTSystemCall(id target, NSString *selector, NSArray *arguments) {
    id result = nil;
    NSError *error = nil;
    if (!MTSystemInvokeReportingError(target, selector, arguments, &result, &error)) {
        NSLog(@"[MetisKeyboard][SystemAction] unavailable class=%@ selector=%@", target ? NSStringFromClass([target class]) : @"nil", selector);
        return MTSystemOpenUnavailable;
    }
    if ([error isKindOfClass:NSError.class]) {
        NSLog(@"[MetisKeyboard][SystemAction] native error selector=%@ domain=%@ code=%ld", selector, error.domain, (long)error.code);
        return MTSystemOpenFailed;
    }
    return [result isKindOfClass:NSNumber.class] && ![result boolValue] ? MTSystemOpenFailed : MTSystemOpenSucceeded;
}

// Select one supported interface before invoking. An invoked failure never
// falls through to another interface, which could repeat a system operation.
static inline MTSystemOpenResult MTSystemCallFirstAvailable(id target, NSArray<NSArray *> *candidates) {
    for (NSArray *candidate in candidates) {
        if ([target respondsToSelector:NSSelectorFromString(candidate[0])])
            return MTSystemCall(target, candidate[0], candidate[1]);
    }
    NSLog(@"[MetisKeyboard][SystemAction] no compatible interface class=%@", target ? NSStringFromClass([target class]) : @"nil");
    return MTSystemOpenUnavailable;
}

// Classes are supplied by the SpringBoard executor after loading the native
// frameworks; keeping this route Foundation-only permits error-path tests.
static inline MTSystemOpenResult MTSystemToggleDND(Class stateServiceClass, Class toggleManagerClass) {
    // DND daemon checks the caller's client-identifier entitlements even
    // inside SpringBoard. A MetisKeyboard-invented identifier cannot query/assert.
    NSString *client = @"com.apple.donotdisturb.control-center.module";
    id service = nil, state = nil, manager = nil, activeIdentifier = nil;
    NSError *error = nil;
    if (!MTSystemInvoke(stateServiceClass, @"serviceForClientIdentifier:", @[client], &service) || !service ||
        !MTSystemInvokeReportingError(service, @"queryCurrentStateWithError:", @[NSNull.null], &state, &error) || !state || error) {
        if (error) NSLog(@"[MetisKeyboard][SystemAction] DND query error domain=%@ code=%ld", error.domain, (long)error.code);
        return error ? MTSystemOpenFailed : MTSystemOpenUnavailable;
    }
    if (!MTSystemInvoke(toggleManagerClass, @"managerForClientIdentifier:", @[client], &manager) || !manager) return MTSystemOpenUnavailable;
    BOOL active = NO;
    if ([state respondsToSelector:NSSelectorFromString(@"activeModeIdentifier")]) {
        if (!MTSystemInvoke(state, @"activeModeIdentifier", @[], &activeIdentifier)) return MTSystemOpenUnavailable;
        active = [activeIdentifier isEqual:@"com.apple.donotdisturb.mode.default"];
    } else {
        id isActive = nil;
        if (!MTSystemInvoke(state, @"isActive", @[], &isActive) || ![isActive isKindOfClass:NSNumber.class]) return MTSystemOpenUnavailable;
        active = [isActive boolValue];
    }
    return MTSystemCall(manager, active ? @"_toggleDNDOffReturningError:" : @"_toggleDNDOnReturningError:", @[NSNull.null]);
}
