#import "MTLongShotTarget.h"
#import <objc/message.h>
#import <string.h>

static id MTTargetObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        NSMethodSignature *signature = [object methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@' ||
            signature.methodReturnLength != sizeof(id)) return nil;
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    }
    @catch (__unused NSException *exception) { return nil; }
}
NSString *MTLongShotFrontmostIdentifier(id application) {
    id app = MTTargetObject(application, @"_accessibilityFrontMostApplication");
    id identifier = MTTargetObject(app, @"bundleIdentifier");
    return [identifier isKindOfClass:NSString.class] && [identifier length] > 0 ? [identifier copy] : nil;
}
id MTLongShotLockManager(void) {
    return MTTargetObject(NSClassFromString(@"SBLockScreenManager"), @"sharedInstance");
}
BOOL MTLongShotTargetIsCurrent(id application, id lockManager, NSString *identifier) {
    SEL selector = NSSelectorFromString(@"isUILocked");
    if (!identifier.length || !lockManager || ![lockManager respondsToSelector:selector]) return NO;
    @try {
        NSMethodSignature *signature = [lockManager methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != 2 || signature.methodReturnLength != sizeof(BOOL) ||
            (strcmp(signature.methodReturnType, "B") && strcmp(signature.methodReturnType, "c"))) return NO;
        if (((BOOL (*)(id, SEL))objc_msgSend)(lockManager, selector)) return NO;
    } @catch (__unused NSException *exception) { return NO; }
    return [MTLongShotFrontmostIdentifier(application) isEqualToString:identifier];
}
