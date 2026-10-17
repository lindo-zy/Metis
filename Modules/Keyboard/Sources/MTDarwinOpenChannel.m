#import "MTDarwinOpenChannel.h"
#import <CommonCrypto/CommonDigest.h>
#import <notify.h>

// notifyd owns this state; there is no cfprefsd domain or shared file whose
// identity/permissions depend on the host sandbox. The public doorbell carries
// a random request ID, not a URL. Each request has its own immutable word slots
// and reply slot, so concurrent publishers cannot combine each other's bytes.
// The doorbell is newest-wins (Darwin delivery can coalesce); a displaced sender
// times out without resending. Registrations pin the words until reply/timeout.
static const char *MTOpenDoorbell = "com.lindo.typex.open.v2";
static const NSUInteger MTOpenMaxPacketBytes = 8192;
NSTimeInterval const MTSystemOpenRequestTTL = 8.0;
static const NSTimeInterval MTOpenReplyTimeout = 10.0;
static const NSUInteger MTOpenMaxPending = 4;
static const uint64_t MTOpenWireMagic = 0x5458020000000000ULL;

@interface MTOpenPending : NSObject
@property(nonatomic, strong) NSMutableArray<NSNumber *> *tokens;
@property(nonatomic, copy) MTSystemOpenReply reply;
@end
@implementation MTOpenPending
@end

static dispatch_queue_t MTOpenQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.lindo.typex.open.transport", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static NSMutableDictionary<NSNumber *, MTOpenPending *> *MTOpenPendingRequests(void) {
    static NSMutableDictionary *requests;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ requests = [NSMutableDictionary dictionary]; });
    return requests;
}

static NSString *MTOpenSlot(uint64_t requestID, NSString *suffix) {
    return [NSString stringWithFormat:@"%s.%016llx.%@", MTOpenDoorbell,
            (unsigned long long)requestID, suffix];
}

static void MTOpenComplete(uint64_t requestID, MTSystemOpenResult result) {
    MTOpenPending *pending = MTOpenPendingRequests()[@(requestID)];
    if (!pending) return; // Reply and timeout may both be queued.
    [MTOpenPendingRequests() removeObjectForKey:@(requestID)];
    for (NSNumber *token in pending.tokens) notify_cancel(token.intValue);
    NSLog(@"[TypeXSB] reply id=%016llx result=%llu", (unsigned long long)requestID,
          (unsigned long long)result);
    if (pending.reply) dispatch_async(dispatch_get_main_queue(), ^{ pending.reply(result); });
}

static BOOL MTOpenWriteWord(NSString *name, uint64_t word, MTOpenPending *pending) {
    int token = NOTIFY_TOKEN_INVALID;
    uint32_t status = notify_register_check(name.UTF8String, &token);
    if (status != NOTIFY_STATUS_OK) return NO;
    [pending.tokens addObject:@(token)];
    return notify_set_state(token, word) == NOTIFY_STATUS_OK;
}

static BOOL MTOpenReadWord(NSString *name, uint64_t *word) {
    int token = NOTIFY_TOKEN_INVALID;
    if (notify_register_check(name.UTF8String, &token) != NOTIFY_STATUS_OK) return NO;
    uint32_t status = notify_get_state(token, word);
    notify_cancel(token);
    return status == NOTIFY_STATUS_OK;
}

static void MTOpenSendReply(uint64_t requestID, MTSystemOpenResult result) {
    int token = NOTIFY_TOKEN_INVALID;
    NSString *name = MTOpenSlot(requestID, @"reply");
    uint32_t status = notify_register_check(name.UTF8String, &token);
    if (status == NOTIFY_STATUS_OK) {
        status = notify_set_state(token, result);
        if (status == NOTIFY_STATUS_OK) status = notify_post(name.UTF8String);
        notify_cancel(token);
    }
    NSLog(@"[TypeXSB] outcome id=%016llx result=%llu notify=%u",
          (unsigned long long)requestID, (unsigned long long)result, status);
}

void MTSendDarwinOpenRequest(NSString *kind, NSString *payload, MTSystemOpenReply reply) {
    // Copy caller-owned values before crossing queues.
    kind = [kind copy];
    payload = [payload copy];
    dispatch_async(MTOpenQueue(), ^{
        if (!kind.length || !payload.length || MTOpenPendingRequests().count >= MTOpenMaxPending) {
            MTSystemOpenResult result = (!kind.length || !payload.length) ? MTSystemOpenInvalid : MTSystemOpenBusy;
            if (reply) dispatch_async(dispatch_get_main_queue(), ^{ reply(result); });
            return;
        }
        uint64_t requestID;
        do { arc4random_buf(&requestID, sizeof(requestID)); }
        while (!requestID || MTOpenPendingRequests()[@(requestID)]);
        NSDictionary *request = @{@"id": @(requestID), @"created": @([NSDate date].timeIntervalSince1970),
                                  @"kind": kind, @"payload": payload};
        NSData *body = [NSPropertyListSerialization dataWithPropertyList:request
                              format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        if (!body.length || body.length + CC_SHA256_DIGEST_LENGTH > MTOpenMaxPacketBytes) {
            if (reply) dispatch_async(dispatch_get_main_queue(), ^{ reply(MTSystemOpenInvalid); });
            return;
        }
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(body.bytes, (CC_LONG)body.length, digest);
        NSMutableData *packet = [NSMutableData dataWithBytes:digest length:sizeof(digest)];
        [packet appendData:body];

        MTOpenPending *pending = [MTOpenPending new];
        pending.tokens = [NSMutableArray array];
        pending.reply = reply;
        MTOpenPendingRequests()[@(requestID)] = pending;
        int replyToken = NOTIFY_TOKEN_INVALID;
        uint32_t status = notify_register_dispatch(MTOpenSlot(requestID, @"reply").UTF8String,
                                                   &replyToken, MTOpenQueue(), ^(int token) {
            uint64_t result = 0;
            if (notify_get_state(token, &result) == NOTIFY_STATUS_OK &&
                result >= MTSystemOpenSucceeded && result <= MTSystemOpenTimedOut) {
                MTOpenComplete(requestID, (MTSystemOpenResult)result);
            }
        });
        if (status != NOTIFY_STATUS_OK) {
            MTOpenComplete(requestID, MTSystemOpenUnavailable);
            return;
        }
        [pending.tokens addObject:@(replyToken)];
        BOOL written = YES;
        const uint8_t *bytes = packet.bytes;
        for (NSUInteger offset = 0; offset < packet.length && written; offset += sizeof(uint64_t)) {
            uint64_t word = 0;
            memcpy(&word, bytes + offset, MIN(sizeof(word), packet.length - offset));
            written = MTOpenWriteWord(MTOpenSlot(requestID, [NSString stringWithFormat:@"%lu", (unsigned long)(offset / 8)]), word, pending);
        }
        // Publish metadata last, then the doorbell. Every data slot is pinned.
        written = written && MTOpenWriteWord(MTOpenSlot(requestID, @"size"), MTOpenWireMagic | packet.length, pending);
        written = written && MTOpenWriteWord(@(MTOpenDoorbell), requestID, pending);
        status = written ? notify_post(MTOpenDoorbell) : NOTIFY_STATUS_FAILED;
        NSLog(@"[TypeXSB] publish id=%016llx kind=%@ bytes=%lu status=%u",
              (unsigned long long)requestID, kind, (unsigned long)packet.length, status);
        if (status != NOTIFY_STATUS_OK) {
            MTOpenComplete(requestID, MTSystemOpenUnavailable);
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MTOpenReplyTimeout * NSEC_PER_SEC)),
                       MTOpenQueue(), ^{
            if (!MTOpenPendingRequests()[@(requestID)]) return;
            // A suspended host can resume with both the reply and timeout
            // queued. Read the pinned reply state before reporting uncertainty.
            uint64_t result = 0;
            BOOL hasReply = notify_get_state(replyToken, &result) == NOTIFY_STATUS_OK &&
                result >= MTSystemOpenSucceeded && result <= MTSystemOpenTimedOut;
            MTOpenComplete(requestID, hasReply ? (MTSystemOpenResult)result : MTSystemOpenTimedOut);
        });
    });
}

static NSDictionary *MTOpenReadRequest(uint64_t requestID) {
    uint64_t sizeWord = 0;
    if (!MTOpenReadWord(MTOpenSlot(requestID, @"size"), &sizeWord) ||
        (sizeWord & 0xffffffff00000000ULL) != MTOpenWireMagic) return nil;
    NSUInteger length = (NSUInteger)(sizeWord & 0xffffffffULL);
    if (length <= CC_SHA256_DIGEST_LENGTH || length > MTOpenMaxPacketBytes) return nil;
    NSMutableData *packet = [NSMutableData dataWithLength:length];
    uint8_t *bytes = packet.mutableBytes;
    for (NSUInteger offset = 0; offset < length; offset += sizeof(uint64_t)) {
        uint64_t word = 0;
        if (!MTOpenReadWord(MTOpenSlot(requestID, [NSString stringWithFormat:@"%lu", (unsigned long)(offset / 8)]), &word)) return nil;
        memcpy(bytes + offset, &word, MIN(sizeof(word), length - offset));
    }
    // This checksum detects missing/corrupted words; it is not authentication.
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes + sizeof(digest), (CC_LONG)(length - sizeof(digest)), digest);
    if (memcmp(bytes, digest, sizeof(digest)) != 0) return nil;
    NSData *body = [packet subdataWithRange:NSMakeRange(sizeof(digest), length - sizeof(digest))];
    id request = [NSPropertyListSerialization propertyListWithData:body options:NSPropertyListImmutable format:nil error:nil];
    if (![request isKindOfClass:[NSDictionary class]] ||
        ![request[@"id"] isKindOfClass:[NSNumber class]] || [request[@"id"] unsignedLongLongValue] != requestID ||
        ![request[@"created"] isKindOfClass:[NSNumber class]] ||
        ![request[@"kind"] isKindOfClass:[NSString class]] ||
        ![request[@"payload"] isKindOfClass:[NSString class]]) return nil;
    return request;
}

BOOL MTStartDarwinOpenServer(MTSystemOpenHandler handler) {
    static int serverToken = NOTIFY_TOKEN_INVALID;
    if (serverToken != NOTIFY_TOKEN_INVALID) return YES;
    if (!handler) return NO;
    NSMutableDictionary<NSNumber *, NSNumber *> *seen = [NSMutableDictionary dictionary];
    uint32_t status = notify_register_dispatch(MTOpenDoorbell, &serverToken, MTOpenQueue(), ^(int token) {
        uint64_t requestID = 0;
        if (notify_get_state(token, &requestID) != NOTIFY_STATUS_OK || !requestID) return;
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        for (NSNumber *oldID in [seen.allKeys copy]) {
            if (now - seen[oldID].doubleValue > MTOpenReplyTimeout) [seen removeObjectForKey:oldID];
        }
        if (seen[@(requestID)]) return;
        if (seen.count >= 64) { MTOpenSendReply(requestID, MTSystemOpenBusy); return; }
        seen[@(requestID)] = @(now);
        NSDictionary *request = MTOpenReadRequest(requestID);
        if (!request) { MTOpenSendReply(requestID, MTSystemOpenInvalid); return; }
        NSTimeInterval created = [request[@"created"] doubleValue];
        NSTimeInterval age = now - created;
        if (!(age >= 0 && age <= MTSystemOpenRequestTTL)) { MTOpenSendReply(requestID, MTSystemOpenExpired); return; }
        NSLog(@"[TypeXSB] consumed id=%016llx kind=%@", (unsigned long long)requestID, request[@"kind"]);
        dispatch_async(dispatch_get_main_queue(), ^{
            // Main-queue congestion must not turn a timed-out action into a
            // surprise launch later. Validate freshness at the execution point.
            NSTimeInterval executionAge = [NSDate date].timeIntervalSince1970 - created;
            if (!(executionAge >= 0 && executionAge <= MTSystemOpenRequestTTL)) {
                MTOpenSendReply(requestID, MTSystemOpenExpired);
                return;
            }
            __block BOOL replied = NO; // Confined to the transport queue.
            MTSystemOpenReply finish = ^(MTSystemOpenResult result) {
                dispatch_async(MTOpenQueue(), ^{
                    if (replied) return;
                    replied = YES;
                    MTOpenSendReply(requestID, result);
                });
            };
            @try { handler(request, finish); }
            @catch (NSException *exception) {
                NSLog(@"[TypeXSB] executor exception=%@", exception.name);
                finish(MTSystemOpenFailed);
            }
        });
    });
    if (status != NOTIFY_STATUS_OK) serverToken = NOTIFY_TOKEN_INVALID;
    NSLog(@"[TypeXSB] notify-state server ready=%d status=%u", status == NOTIFY_STATUS_OK, status);
    return status == NOTIFY_STATUS_OK;
}
