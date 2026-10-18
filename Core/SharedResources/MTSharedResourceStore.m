#import "MTSharedResourceStore.h"
#import "MTSharedResourceIDs.h"
#import "MTSharedResourceValidator.h"
#import "MTPathResolver.h"
#import "MTLog.h"
#import <pthread/pthread.h>

NSString *const MTSharedResourceStoreErrorDomain = @"com.lindo.metis.shared-resources.store";

static NSString *gAuthoritativeOverride;
static NSString *gSnapshotOverride;

static NSString *MTStoreAuthoritativePath(void) {
    return gAuthoritativeOverride ?: MTResolvePath(@"/var/mobile/Library/Metis/Global/resources-v1.plist");
}
static NSString *MTStoreSnapshotPath(void) {
    return gSnapshotOverride ?: [MTPublicConfigDirectory() stringByAppendingPathComponent:@"global-shared.plist"];
}
static NSString *MTStoreJournalPath(void) {
    NSString *root = [MTStoreAuthoritativePath() stringByDeletingLastPathComponent];
    return [root stringByAppendingPathComponent:@"journal-v1.plist"];
}

static NSError *MTStoreError(MTSharedResourceStoreCode code, NSString *message) {
    return [NSError errorWithDomain:MTSharedResourceStoreErrorDomain code:code
                            userInfo:@{NSLocalizedDescriptionKey : message ?: @"shared resource store error"}];
}

static NSDictionary *MTStoreReadFile(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    id document = [NSPropertyListSerialization propertyListWithData:data
                                                             options:NSPropertyListImmutable
                                                              format:nil
                                                               error:nil];
    return [document isKindOfClass:NSDictionary.class] ? document : nil;
}

static BOOL MTStoreAtomicWrite(NSDictionary *document, NSString *path, NSError **error) {
    (void)error;
    NSString *directory = [path stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) {
        if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES
                                     attributes:@{NSFilePosixPermissions: @0755} error:nil]) return NO;
    }
    // writeToFile:atomically: 先落临时文件再 rename，进程崩溃不会留下半份文档。
    return [document writeToFile:path atomically:YES];
}

// 进程内缓存：不可变文档 + 锁内替换；Darwin 失效通知触发重读。
static pthread_mutex_t gStoreLock = PTHREAD_MUTEX_INITIALIZER;
static NSDictionary *gCachedDocument;
static uint64_t gCachedRevision;
static dispatch_once_t gStoreObserverOnce;

static NSDictionary *MTStoreLoadLatest(NSError **error) {
    NSDictionary *document = MTStoreReadFile(MTStoreAuthoritativePath());
    if (!document) document = MTStoreReadFile(MTStoreSnapshotPath());
    if (!document) {
        if (error) *error = MTStoreError(MTSharedResourceStoreUnavailable, @"no readable shared resource document");
        return nil;
    }
    // 未来 schema：返回只读标记错误，不降级、不覆盖。
    NSNumber *schema = [document[@"schemaVersion"] isKindOfClass:NSNumber.class] ? document[@"schemaVersion"] : nil;
    if (schema && schema.unsignedIntegerValue > MTSharedResourceCurrentSchemaVersion.unsignedIntegerValue) {
        if (error) *error = MTStoreError(MTSharedResourceStoreFutureSchema, @"future schema is read-only");
        return nil;
    }
    if (schema && [document[@"format"] isKindOfClass:NSString.class] &&
        ![document[@"format"] isEqual:MTSharedResourceFormat]) {
        if (error) *error = MTStoreError(MTSharedResourceStoreUnavailable, @"unknown document format");
        return nil;
    }
    return document;
}

static void MTStoreDarwinCallback(CFNotificationCenterRef center, void *observer,
                                  CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    NSDictionary *latest = MTStoreLoadLatest(NULL);
    pthread_mutex_lock(&gStoreLock);
    gCachedDocument = latest;
    gCachedRevision = latest ? ((NSNumber *)latest[@"revision"]).unsignedLongLongValue : 0;
    pthread_mutex_unlock(&gStoreLock);
}

static NSDictionary *MTStoreCurrent(void) {
    dispatch_once(&gStoreObserverOnce, ^{
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL, &MTStoreDarwinCallback,
            (__bridge CFStringRef)MTSharedResourceChangedNotification, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    });
    pthread_mutex_lock(&gStoreLock);
    NSDictionary *cached = gCachedDocument;
    pthread_mutex_unlock(&gStoreLock);
    if (cached) return cached;
    NSDictionary *latest = MTStoreLoadLatest(NULL);
    if (latest) {
        pthread_mutex_lock(&gStoreLock);
        gCachedDocument = latest;
        gCachedRevision = ((NSNumber *)latest[@"revision"]).unsignedLongLongValue;
        pthread_mutex_unlock(&gStoreLock);
    }
    return latest;
}

static BOOL MTStoreWriteJournal(NSDictionary *journal) {
    return MTStoreAtomicWrite(journal, MTStoreJournalPath(), nil);
}

// 快照发布：世界可读 + 无文件保护（与 gate.plist 同策略，沙盒宿主唯一来源）。
static BOOL MTStorePublish(NSDictionary *document) {
    if (!MTStoreAtomicWrite(document, MTStoreSnapshotPath(), nil)) return NO;
    [[NSFileManager defaultManager] setAttributes:@{
        NSFilePosixPermissions: @0644,
        NSFileProtectionKey: NSFileProtectionNone
    } ofItemAtPath:MTStoreSnapshotPath() error:nil];
    return YES;
}

@implementation MTSharedResourceStore

+ (NSString *)authoritativePath { return MTStoreAuthoritativePath(); }
+ (NSString *)snapshotPath { return MTStoreSnapshotPath(); }

+ (NSDictionary *)readSnapshot {
    return [self readSnapshotError:NULL];
}

+ (NSDictionary *)readSnapshotError:(NSError **)error {
    NSDictionary *document = MTStoreCurrent();
    if (!document && error) {
        *error = MTStoreError(MTSharedResourceStoreUnavailable, @"shared resources unavailable");
    }
    return document;
}

+ (uint64_t)currentRevision {
    NSDictionary *document = MTStoreCurrent();
    if (!document) return 0;
    NSNumber *revision = [document[@"revision"] isKindOfClass:NSNumber.class] ? document[@"revision"] : nil;
    return revision ? revision.unsignedLongLongValue : 0;
}

+ (NSDictionary *)emptyDocument {
    return @{
        @"format": MTSharedResourceFormat,
        @"schemaVersion": MTSharedResourceCurrentSchemaVersion,
        @"revision": @1,
        @"actions": @[],
        @"panels": @[],
        @"bindings": @[],
        @"groups": @[],
        @"migration": @{@"version": @1, @"state": @"complete", @"mapping": @{}},
    };
}

+ (BOOL)installDocument:(NSDictionary *)document error:(NSError **)error {
    if (!document) return NO;
    NSError *validation = [MTSharedResourceValidator validateDocument:document];
    if (validation) {
        if (error) *error = validation;
        return NO;
    }
    if (!MTStoreWriteJournal(@{@"state": @"canonicalCommitted", @"revision": document[@"revision"], @"publicationPending": @YES})) {
        MTLogInfo(MTLogModuleCore, @"flow=store state=journal-write-failed");
    }
    if (!MTStoreAtomicWrite(document, MTStoreAuthoritativePath(), error)) return NO;
    if (!MTStorePublish(document)) {
        // 权威已提交、发布失败：记录 publicationPending，保留并重试旧快照，
        // 不再次分配 revision（05 §5）。
        MTStoreWriteJournal(@{@"state": @"publicationPending", @"revision": document[@"revision"], @"publicationPending": @YES});
        MTLogInfo(MTLogModuleCore, @"flow=store state=publication-pending revision=%@", document[@"revision"]);
        if (error) *error = MTStoreError(MTSharedResourceStoreIOFailed, @"published snapshot write failed");
        return NO;
    }
    MTStoreWriteJournal(@{@"state": @"complete", @"revision": document[@"revision"], @"publicationPending": @NO});
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)MTSharedResourceChangedNotification, NULL, NULL, TRUE);
    pthread_mutex_lock(&gStoreLock);
    gCachedDocument = document;
    gCachedRevision = ((NSNumber *)document[@"revision"]).unsignedLongLongValue;
    pthread_mutex_unlock(&gStoreLock);
    MTLogInfo(MTLogModuleCore, @"flow=config state=published revision=%@", document[@"revision"]);
    return YES;
}

+ (BOOL)commitSnapshot:(NSDictionary *)draft expectedRevision:(uint64_t)revision error:(NSError **)error {
    NSDictionary *current = MTStoreCurrent();
    uint64_t currentRevision = current ? ((NSNumber *)current[@"revision"]).unsignedLongLongValue : 0;
    if (currentRevision != revision) {
        if (error) *error = MTStoreError(MTSharedResourceStoreConflict,
            [NSString stringWithFormat:@"expected revision %llu but store is at %llu", revision, currentRevision]);
        return NO;
    }
    NSMutableDictionary *document = [(current ?: [MTSharedResourceStore emptyDocument]) mutableCopy];
    for (NSString *key in @[@"actions", @"panels", @"bindings", @"groups", @"ungroupedCollapsed", @"migration"])
        if (draft[key] != nil) document[key] = draft[key];
    if (!document[@"migration"]) {
        document[@"migration"] = @{@"version": @1, @"state": @"complete", @"mapping": @{}};
    }
    document[@"revision"] = @(revision + 1);
    NSError *validation = [MTSharedResourceValidator validateDocument:document];
    if (validation) {
        if (error) *error = validation;
        return NO;
    }
    // 提交前一次性备份（保留上一有效版本；仅保留最近一份，规则见 05 §3）。
    if (current) {
        NSString *backup = [[MTStoreAuthoritativePath() stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"backup-pre-commit.plist"];
        if (!MTStoreAtomicWrite(current, backup, nil)) {
            MTLogInfo(MTLogModuleCore, @"flow=store state=backup-write-failed");
        }
    }
    return [self installDocument:document error:error];
}

+ (void)setAuthoritativePathOverride:(NSString *)path snapshotOverride:(NSString *)path2 {
    pthread_mutex_lock(&gStoreLock);
    gAuthoritativeOverride = [path copy];
    gSnapshotOverride = [path2 copy];
    gCachedDocument = nil;
    gCachedRevision = 0;
    pthread_mutex_unlock(&gStoreLock);
}

@end
