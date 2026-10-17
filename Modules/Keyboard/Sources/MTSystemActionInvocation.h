#import <Foundation/Foundation.h>
#include <string.h>
#include <stdbool.h>

static inline const char *MTSystemUnqualifiedType(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

// Validate the runtime ABI instead of trusting historical private headers.
// Only scalar/object returns and explicitly typed arguments are supported.
static inline BOOL MTSystemInvocationRejected(id target, NSString *selector, NSString *stage) {
    NSLog(@"[MetisKeyboard][SystemAction] rejected class=%@ selector=%@ stage=%@", target ? NSStringFromClass([target class]) : @"nil", selector, stage);
    return NO;
}
static inline BOOL MTSystemInvokeReportingError(id target, NSString *name, NSArray *arguments, id *result, NSError **error) {
    if (result) *result = nil;
    if (error) *error = nil;
    NSError *__autoreleasing invocationError = nil;
    if (![name isKindOfClass:NSString.class] || !name.length || ![arguments isKindOfClass:NSArray.class]) return NO;
    SEL selector = NSSelectorFromString(name);
    if (!target || ![target respondsToSelector:selector]) return MTSystemInvocationRejected(target, name, @"missing-method");
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != arguments.count + 2) return MTSystemInvocationRejected(target, name, @"argument-count");
    const char *returned = MTSystemUnqualifiedType(signature.methodReturnType);
    if (!*returned || !strchr("v@BcCsSiIlLqQfd", *returned) || returned[1]) return MTSystemInvocationRejected(target, name, @"return-type");
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = target;
    invocation.selector = selector;
    for (NSUInteger index = 0; index < arguments.count; index++) {
        id argument = arguments[index];
        const char *type = MTSystemUnqualifiedType([signature getArgumentTypeAtIndex:index + 2]);
        if (!strcmp(type, "@") || !strcmp(type, "@?")) {
            id object = argument == NSNull.null ? nil : argument;
            [invocation setArgument:&object atIndex:index + 2];
        } else if (!strcmp(type, "^@") && argument == NSNull.null) {
            // Keep the autoreleasing out storage alive until invoke returns.
            NSError *__autoreleasing *pointer = error ? &invocationError : NULL;
            [invocation setArgument:&pointer atIndex:index + 2];
        } else {
            if (![argument isKindOfClass:NSNumber.class] || type[1]) return MTSystemInvocationRejected(target, name, @"argument-type");
#define MT_SYSTEM_ARGUMENT(CODE, TYPE, ACCESSOR) case CODE: { TYPE value = [argument ACCESSOR]; [invocation setArgument:&value atIndex:index + 2]; break; }
            switch (*type) {
                MT_SYSTEM_ARGUMENT('B', bool, boolValue)
                MT_SYSTEM_ARGUMENT('c', char, charValue)
                MT_SYSTEM_ARGUMENT('C', unsigned char, unsignedCharValue)
                MT_SYSTEM_ARGUMENT('s', short, shortValue)
                MT_SYSTEM_ARGUMENT('S', unsigned short, unsignedShortValue)
                MT_SYSTEM_ARGUMENT('i', int, intValue)
                MT_SYSTEM_ARGUMENT('I', unsigned int, unsignedIntValue)
                MT_SYSTEM_ARGUMENT('l', long, longValue)
                MT_SYSTEM_ARGUMENT('L', unsigned long, unsignedLongValue)
                MT_SYSTEM_ARGUMENT('q', long long, longLongValue)
                MT_SYSTEM_ARGUMENT('Q', unsigned long long, unsignedLongLongValue)
                MT_SYSTEM_ARGUMENT('f', float, floatValue)
                MT_SYSTEM_ARGUMENT('d', double, doubleValue)
                default: return MTSystemInvocationRejected(target, name, @"unsupported-argument");
            }
#undef MT_SYSTEM_ARGUMENT
        }
    }
    [invocation retainArguments];
    @try { [invocation invoke]; }
    @catch (NSException *exception) { NSLog(@"[MetisKeyboard][SystemAction] invocation exception=%@", exception.name); return NO; }
    if (error) *error = invocationError;
    if (*returned == 'v') return YES;
    if (*returned == '@') {
        __unsafe_unretained id object = nil;
        [invocation getReturnValue:&object];
        if (result) *result = object;
        return YES;
    }
#define MT_SYSTEM_RETURN(CODE, TYPE) case CODE: { TYPE value = 0; [invocation getReturnValue:&value]; if (result) *result = @(value); break; }
    switch (*returned) {
        MT_SYSTEM_RETURN('B', bool)
        MT_SYSTEM_RETURN('c', char)
        MT_SYSTEM_RETURN('C', unsigned char)
        MT_SYSTEM_RETURN('s', short)
        MT_SYSTEM_RETURN('S', unsigned short)
        MT_SYSTEM_RETURN('i', int)
        MT_SYSTEM_RETURN('I', unsigned int)
        MT_SYSTEM_RETURN('l', long)
        MT_SYSTEM_RETURN('L', unsigned long)
        MT_SYSTEM_RETURN('q', long long)
        MT_SYSTEM_RETURN('Q', unsigned long long)
        MT_SYSTEM_RETURN('f', float)
        MT_SYSTEM_RETURN('d', double)
        default: return NO;
    }
#undef MT_SYSTEM_RETURN
    return YES;
}

static inline BOOL MTSystemInvoke(id target, NSString *name, NSArray *arguments, id *result) {
    return MTSystemInvokeReportingError(target, name, arguments, result, NULL);
}
