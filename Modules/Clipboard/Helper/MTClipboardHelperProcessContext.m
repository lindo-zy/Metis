//
//  MTClipboardHelperProcessContext.m
//  Mt
//

#import "MTClipboardHelperProcessContext.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTClipboardHelperProcessContext ()
@property(nonatomic, assign, readwrite) MTClipboardHelperProcessKind kind;
@end

NS_ASSUME_NONNULL_END

@implementation MTClipboardHelperProcessContext

+ (instancetype)currentContext {
    if ([self isKeyboardExtensionProcess]) {
        return [[self alloc] initWithKind:MTClipboardHelperProcessKindKeyboardExtension];
    }
    if ([self isSpringBoardProcess]) {
        return [[self alloc] initWithKind:MTClipboardHelperProcessKindSpringBoard];
    }
    if ([self isApplicationProcess]) {
        return [[self alloc] initWithKind:MTClipboardHelperProcessKindApplication];
    }
    return [[self alloc] initWithKind:MTClipboardHelperProcessKindUnsupported];
}

- (instancetype)initWithKind:(MTClipboardHelperProcessKind)kind {
    self = [super init];
    if (self) {
        _kind = kind;
    }
    return self;
}

+ (BOOL)isSpringBoardProcess {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"];
}

+ (BOOL)isKeyboardExtensionProcess {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *bundlePath = [mainBundle bundlePath];
    BOOL isPluginBundle = [[bundlePath pathExtension] isEqualToString:@"appex"] ||
                          [bundlePath rangeOfString:@"/PlugIns/"].location != NSNotFound;
    if (!isPluginBundle) {
        return NO;
    }

    NSDictionary<NSString *, id> *extensionInfo = [[mainBundle infoDictionary] objectForKey:@"NSExtension"];
    NSString *extensionPointIdentifier = [extensionInfo objectForKey:@"NSExtensionPointIdentifier"];
    return [extensionPointIdentifier isEqualToString:@"com.apple.keyboard-service"];
}

+ (BOOL)isApplicationProcess {
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.Spotlight"]) {
        return YES;
    }

    NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
    NSUInteger count = [args count];
    if (count == 0) {
        return NO;
    }

    NSString *executablePath = args[0];
    if (executablePath.length == 0) {
        return NO;
    }

    BOOL isApplication = [executablePath rangeOfString:@"/Application/"].location != NSNotFound ||
                         [executablePath rangeOfString:@"/Applications/"].location != NSNotFound;
    if (!isApplication) {
        return NO;
    }

    NSString *processName = [executablePath lastPathComponent];
    BOOL isFileProvider = [[processName lowercaseString] rangeOfString:@"fileprovider"].location != NSNotFound;
    if (isFileProvider) {
        return NO;
    }

    BOOL isProtectedApplication = [processName isEqualToString:@"AdSheet"] ||
                                  [processName isEqualToString:@"CoreAuthUI"] ||
                                  [processName isEqualToString:@"InCallService"] ||
                                  [processName isEqualToString:@"MessagesNotificationViewService"];
    if (isProtectedApplication) {
        return NO;
    }

    BOOL isApplicationExtension = [executablePath rangeOfString:@".appex/"].location != NSNotFound;
    return !isApplicationExtension;
}

@end
