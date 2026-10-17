#import "MTProcessContext.h"

@implementation MTProcessContext {
    MTProcessKind _kind;
    NSString *_bundleIdentifier;
    NSString *_processName;
}

+ (instancetype)currentContext {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *bundleID = mainBundle.bundleIdentifier;

    if ([bundleID isEqualToString:@"com.apple.springboard"]) {
        return [[self alloc] initWithKind:MTProcessKindSpringBoard bundleID:bundleID];
    }

    NSString *processName = [[NSProcessInfo processInfo] processName];
    NSString *executablePath = [[NSProcessInfo processInfo] arguments].firstObject;
    BOOL isSystemExecutable =
        [executablePath hasPrefix:@"/System/Library/"] || [executablePath hasPrefix:@"/usr/libexec/"];
    BOOL isPasteTipProcess = [processName isEqualToString:@"druid"] || [processName isEqualToString:@"pasted"];
    if (isSystemExecutable && isPasteTipProcess) {
        return [[self alloc] initWithKind:MTProcessKindPasteServices bundleID:bundleID];
    }

    // 键盘扩展：主包路径落在 .appex 内，或 Info.plist 声明键盘扩展点。
    BOOL isKeyboardExtension = NO;
    NSString *bundlePath = mainBundle.bundlePath ?: @"";
    if ([bundlePath containsString:@".appex/"] || [bundlePath hasSuffix:@".appex"]) {
        NSDictionary *extensionInfo = [mainBundle infoDictionary][@"NSExtension"];
        NSString *extensionPoint = extensionInfo[@"NSExtensionPointIdentifier"];
        isKeyboardExtension =
            extensionPoint ? [extensionPoint isEqualToString:@"com.apple.keyboard-extension-service"] : YES;
    }
    if (isKeyboardExtension) {
        return [[self alloc] initWithKind:MTProcessKindKeyboardExtension bundleID:bundleID];
    }

    // 剩余普通 UIKit 宿主：以 UIKit 是否已链接进本进程为准。
    if (NSClassFromString(@"UIApplication") != nil) {
        return [[self alloc] initWithKind:MTProcessKindUIKitApplication bundleID:bundleID];
    }

    return [[self alloc] initWithKind:MTProcessKindUnsupported bundleID:bundleID];
}

- (instancetype)initWithKind:(MTProcessKind)kind bundleID:(NSString *)bundleID {
    self = [super init];
    if (self) {
        _kind = kind;
        _bundleIdentifier = [bundleID copy];
        _processName = [[[NSProcessInfo processInfo] processName] copy];
    }
    return self;
}

- (NSString *)processName {
    if (!_processName) return @"";
    return _processName;
}

- (BOOL)isSpringBoard {
    return _kind == MTProcessKindSpringBoard;
}

- (BOOL)isPasteTipProcess {
    return _kind == MTProcessKindPasteServices;
}

- (BOOL)isUIKitHost {
    return _kind == MTProcessKindUIKitApplication || _kind == MTProcessKindKeyboardExtension;
}

@end
