#import "MTFloatingAppShelfChannel.h"
#import <notify.h>

const char *MTFloatingShelfChangedName = "com.lindo.typex.floating-shelf.v1";
static const NSUInteger MTFloatingShelfMaxBytes = 8192;
static NSMutableDictionary<NSString *, NSNumber *> *MTShelfPinned;
static uint64_t MTShelfRevision;
static NSString *MTShelfSlot(NSUInteger bank, NSString *suffix) {
    return [NSString stringWithFormat:@"%s.%lu.%@", MTFloatingShelfChangedName, (unsigned long)bank, suffix];
}
static BOOL MTShelfWrite(NSString *name, uint64_t word) {
    NSNumber *existing = MTShelfPinned[name];
    int token = existing ? existing.intValue : NOTIFY_TOKEN_INVALID;
    if (!existing) {
        if (notify_register_check(name.UTF8String, &token) != NOTIFY_STATUS_OK) return NO;
        MTShelfPinned[name] = @(token);
    }
    return notify_set_state(token, word) == NOTIFY_STATUS_OK;
}
static BOOL MTShelfRead(NSString *name, uint64_t *word) {
    int token = NOTIFY_TOKEN_INVALID;
    if (notify_register_check(name.UTF8String, &token) != NOTIFY_STATUS_OK) return NO;
    BOOL read = notify_get_state(token, word) == NOTIFY_STATUS_OK;
    notify_cancel(token);
    return read;
}
BOOL MTPublishFloatingShelf(NSDictionary *snapshot) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"] ||
        !MTFloatingShelfSnapshotValid(snapshot)) return NO;
    if (!MTShelfPinned) {
        MTShelfPinned = [NSMutableDictionary dictionary];
        arc4random_buf(&MTShelfRevision, sizeof(MTShelfRevision));
        MTShelfRevision = (MTShelfRevision & 0x1fffffffffffffffULL) + 1;
    }
    // Random initial revision distinguishes a new SpringBoard lifetime.
    uint64_t revision = MTShelfRevision + 1;
    NSUInteger bank = revision & 1;
    // 发布运行在 SpringBoard 主线程的清理与通知路径上：序列化遇到异常值必须
    // 就地失败，绝不能把未捕获异常抛进主线程。
    NSData *data = nil;
    @try {
        data = [NSPropertyListSerialization dataWithPropertyList:snapshot format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    } @catch (NSException *exception) {
        NSLog(@"[MetisKeyboard][FloatingShelf] snapshot serialization exception=%@", exception.name);
        return NO;
    }
    if (!data.length || data.length > MTFloatingShelfMaxBytes) return NO;
    for (NSUInteger offset = 0; offset < data.length; offset += 8) {
        uint64_t word = 0;
        memcpy(&word, (const uint8_t *)data.bytes + offset, MIN((NSUInteger)8, data.length - offset));
        if (!MTShelfWrite(MTShelfSlot(bank, [NSString stringWithFormat:@"%lu", (unsigned long)(offset / 8)]), word)) return NO;
    }
    if (!MTShelfWrite(MTShelfSlot(bank, @"size"), data.length) ||
        !MTShelfWrite(@(MTFloatingShelfChangedName), revision)) return NO;
    MTShelfRevision = revision;
    return notify_post(MTFloatingShelfChangedName) == NOTIFY_STATUS_OK;
}
NSDictionary *MTReadFloatingShelf(void) {
    for (NSUInteger attempt = 0; attempt < 3; attempt++) {
        uint64_t revision = 0, length = 0, after = 0;
        if (!MTShelfRead(@(MTFloatingShelfChangedName), &revision) || !revision ||
            !MTShelfRead(MTShelfSlot(revision & 1, @"size"), &length) || !length || length > MTFloatingShelfMaxBytes) return nil;
        NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)length];
        for (NSUInteger offset = 0; offset < length; offset += 8) {
            uint64_t word = 0;
            if (!MTShelfRead(MTShelfSlot(revision & 1, [NSString stringWithFormat:@"%lu", (unsigned long)(offset / 8)]), &word)) return nil;
            memcpy((uint8_t *)data.mutableBytes + offset, &word, MIN((NSUInteger)8, (NSUInteger)length - offset));
        }
        if (!MTShelfRead(@(MTFloatingShelfChangedName), &after)) return nil;
        if (after != revision) continue;
        id snapshot = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil];
        if (!MTFloatingShelfSnapshotValid(snapshot)) return nil;
        NSMutableDictionary *result = [snapshot mutableCopy];
        result[@"revision"] = @(revision);
        return result;
    }
    return nil;
}
