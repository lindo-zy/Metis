#import "MTSharedResourceIDs.h"
#import <CommonCrypto/CommonDigest.h>

NSString *const MTSharedResourceFormat = @"com.lindo.metis.shared-resources";
NSNumber *const MTSharedResourceCurrentSchemaVersion = @1;
NSString *const MTSharedResourceChangedNotification = @"com.lindo.metis/shared-resources-changed";

NSString *const MTSharedResourceSourceKeyboard = @"keyboard";
NSString *const MTSharedResourceSourceGesture = @"gesture";
NSString *const MTSharedResourceSourceClipboard = @"clipboard";
NSString *const MTSharedResourceSourceCapture = @"capture";
NSString *const MTSharedResourceSourceOther = @"other";

NSString *const MTSharedTargetKindAction = @"action";
NSString *const MTSharedTargetKindPanel = @"panel";
NSString *const MTSharedTargetKindBuiltin = @"builtin";
NSString *const MTSharedTargetKindNone = @"none";

NSString *const MTSharedCompatibilityPlaceholderDialectClipboardV1 = @"clipboard-v1";

BOOL MTSharedIsValidUUIDString(NSString *string) {
    if (![string isKindOfClass:NSString.class] || string.length != 36) return NO;
    static NSCharacterSet *hex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *set = [NSMutableCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
        [set removeCharactersInString:@"-"];
        hex = set;
    });
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c == '-' && (i == 8 || i == 13 || i == 18 || i == 23)) continue;
        if (c == '-') return NO;
        if (![hex characterIsMember:c]) return NO;
    }
    return YES;
}

NSString *MTSharedDeterministicUUID(NSString *legacyKey) {
    if (![legacyKey isKindOfClass:NSString.class] || legacyKey.length == 0) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if (CC_SHA256(legacyKey.UTF8String, (CC_LONG)legacyKey.length, digest) == NULL) return nil;
    // 取前 16 字节并固定 version(5)/variant 位，保证是合法 UUID 形状。
    digest[6] = (digest[6] & 0x0F) | 0x50;
    digest[8] = (digest[8] & 0x3F) | 0x80;
    return [NSString stringWithFormat:
        @"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
        digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]];
}
