// MTConfigBackupService.m —— 实现见 .h。所有路径经 MTPathResolver 解析
// （roothide 环境 jbroot）；写文件策略与 MTSharedResourceStore 快照一致：
// 原子替换 + 0644 + 无文件保护，保证解锁前冷启动可读、移动端可管理。
#import "MTConfigBackupService.h"
#import "MTConfigService.h"
#import "MTSharedResourceStore.h"
#import "MTSharedResourceValidator.h"
#import "MTLog.h"
#import "MTPathResolver.h"
#import <CoreFoundation/CoreFoundation.h>
#import <pthread/pthread.h>

NSString *const MTConfigBackupFormat = @"com.lindo.metis.config-backup";
NSUInteger const MTConfigBackupCurrentSchemaVersion = 1;
NSUInteger const MTConfigBackupRetentionLimit = 10;
NSString *const MTConfigBackupErrorDomain = @"com.lindo.metis.config-backup";

// 产品域清单（各模块权威域字面量；Core 不反向依赖模块头，键名同值注释）：
//   com.lindo.metis                       门控整体开关（MTModuleGate/MTConfigService）
//   com.lindo.metis.keyboard              键盘细节域（Keyboard common.h kIdentifier）
//   com.lindo.metis.clipboard             剪切板细节域（MTPreferenceKeys kMTClipboardPreferencesIdentifier）
//   com.lindo.metis.capture               截图细节域（Capture MTConstants MTCapturePreferencesDomain）
//   com.lindo.metis.quickactions          键盘快捷启动目录（Keyboard common.h TypeXQuickActionDomain）
//   com.lindo.metis.clipboard.quickactions  剪贴板快捷动作目录（Clipboard MTShortcutCatalog）
static NSArray<NSString *> *MTDefaultPreferenceDomains(void) {
    static NSArray<NSString *> *domains;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        domains = @[
            @"com.lindo.metis",
            @"com.lindo.metis.keyboard",
            @"com.lindo.metis.clipboard",
            @"com.lindo.metis.capture",
            @"com.lindo.metis.quickactions",
            @"com.lindo.metis.clipboard.quickactions",
        ];
    });
    return domains;
}

// 恢复后补发的模块刷新通知（各模块既有监听名；config-changed 与
// shared-resources-changed 分别由 MTConfigService.flush 与
// MTSharedResourceStore.installDocument 内部发出，不在此重复）。
static NSString *const MTKeyboardPrefsChangedName = @"com.lindo.metis.keyboard/prefschanged";
static NSString *const MTClipboardPrefsReloadName = @"com.lindo.metis.clipboard.preferences.reload";
static NSString *const MTKeyboardShortcutRefreshName = @"com.lindo.metis.keyboard/shortcutrefresh";
static NSString *const MTClipboardShortcutChangedName = @"com.lindo.metis.clipboard.shortcut.changed";

static NSString *gBackupDirectoryOverride;
static NSArray<NSString *> *gPreferenceDomainOverride;
static pthread_mutex_t gOverrideLock = PTHREAD_MUTEX_INITIALIZER;

static NSError *MTBackupError(MTConfigBackupErrorCode code, NSString *message) {
    return [NSError errorWithDomain:MTConfigBackupErrorDomain code:code
                            userInfo:@{NSLocalizedDescriptionKey : message ?: @"config backup error"}];
}

static NSArray<NSString *> *MTCurrentPreferenceDomains(void) {
    pthread_mutex_lock(&gOverrideLock);
    NSArray<NSString *> *domains = gPreferenceDomainOverride ?: MTDefaultPreferenceDomains();
    pthread_mutex_unlock(&gOverrideLock);
    return domains;
}

static NSDateFormatter *MTISOFormatter(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return formatter;
}

static NSString *MTAppVersionString(void) {
    NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
    return ([version isKindOfClass:NSString.class] && version.length) ? version : @"unknown";
}

// 读域全量：键清单 + 多键值一次取走，避免逐键往返。
static NSDictionary *MTCopyDomainValues(NSString *domain) {
    CFStringRef appID = (__bridge CFStringRef)domain;
    CFArrayRef keys = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!keys) return nil;
    NSDictionary *values = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(
        keys, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(keys);
    return [values isKindOfClass:NSDictionary.class] ? values : nil;
}

// 写域（替换语义）：先清空现存键，保证恢复是「精确回到备份态」而非合并；
// 随后逐域 AppSynchronize，让 cfprefsd 立即对其它进程可见。
static BOOL MTReplaceDomainValues(NSString *domain, NSDictionary *values, NSError **error) {
    CFStringRef appID = (__bridge CFStringRef)domain;
    CFArrayRef existing = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (existing) {
        CFPreferencesSetMultiple(NULL, existing, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFRelease(existing);
    }
    if (values.count) {
        CFPreferencesSetMultiple((__bridge CFDictionaryRef)values, NULL, appID,
                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    if (!CFPreferencesAppSynchronize(appID)) {
        if (error) {
            *error = MTBackupError(MTConfigBackupErrorRestoreFailed,
                                   [NSString stringWithFormat:@"偏好域同步失败：%@", domain]);
        }
        return NO;
    }
    return YES;
}

static BOOL MTWriteBackupDocument(NSDictionary *document, NSString *path, NSError **error) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *directory = [path stringByDeletingLastPathComponent];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) {
        if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES
                                     attributes:@{NSFilePosixPermissions : @0755}
                                          error:error]) {
            return NO;
        }
    }
    // writeToFile:atomically: 先落临时文件再 rename，崩溃不会留下半份备份。
    if (![document writeToFile:path atomically:YES]) {
        if (error) *error = MTBackupError(MTConfigBackupErrorIOFailed, @"备份文件写入失败");
        return NO;
    }
    // 与 store 快照/门控快照同策略：世界可读 + 无文件保护（解锁前可读、可管理）。
    [fileManager setAttributes:@{
        NSFilePosixPermissions : @0644,
        NSFileProtectionKey : NSFileProtectionNone
    } ofItemAtPath:path error:nil];
    return YES;
}

static NSString *MTBackupFilePathForDate(NSDate *date) {
    NSDateFormatter *stamp = [NSDateFormatter new];
    stamp.dateFormat = @"yyyyMMdd-HHmmss";
    stamp.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *base = [NSString stringWithFormat:@"metis-config-%@", [stamp stringFromDate:date]];
    NSString *directory = [MTConfigBackupService backupDirectory];
    NSString *path = [directory stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"plist"]];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSUInteger collision = 1;
    while ([fileManager fileExistsAtPath:path]) {
        path = [directory stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@-%lu.plist", base, (unsigned long)collision]];
        collision++;
    }
    return path;
}

static MTConfigBackupItem *MTBackupItemForFile(NSString *path) {
    NSDictionary *document = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![document isKindOfClass:NSDictionary.class]) return nil;
    NSDate *createdAt = [MTISOFormatter() dateFromString:
        [document[@"createdAt"] isKindOfClass:NSString.class] ? document[@"createdAt"] : @""];
    NSDictionary *preferences = [document[@"preferences"] isKindOfClass:NSDictionary.class]
        ? document[@"preferences"] : @{};
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    MTConfigBackupItem *item = [MTConfigBackupItem new];
    item.path = path;
    item.createdAt = createdAt ?: [attributes fileModificationDate] ?: [NSDate dateWithTimeIntervalSince1970:0];
    item.appVersion = [document[@"appVersion"] isKindOfClass:NSString.class] ? document[@"appVersion"] : @"unknown";
    item.byteSize = attributes.fileSize;
    item.domainCount = preferences.count;
    item.includesSharedResources = [document[@"sharedResources"] isKindOfClass:NSDictionary.class];
    return item;
}

static void MTApplyRetention(void) {
    NSArray<MTConfigBackupItem *> *items = [MTConfigBackupService availableBackups];
    if (items.count <= MTConfigBackupRetentionLimit) return;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSUInteger index = MTConfigBackupRetentionLimit; index < items.count; index++) {
        [fileManager removeItemAtPath:items[index].path error:nil];
    }
}

static void MTPostDarwinNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)name, NULL, NULL, TRUE);
}

@implementation MTConfigBackupItem
@end

@implementation MTConfigBackupService

+ (NSString *)backupDirectory {
    pthread_mutex_lock(&gOverrideLock);
    NSString *override = gBackupDirectoryOverride;
    pthread_mutex_unlock(&gOverrideLock);
    return override ?: MTResolvePath(@"/var/mobile/Library/Metis/Backups");
}

+ (NSArray<MTConfigBackupItem *> *)availableBackups {
    NSString *directory = [self backupDirectory];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) return @[];
    NSArray *names = [fileManager contentsOfDirectoryAtPath:directory error:nil] ?: @[];
    NSMutableArray<MTConfigBackupItem *> *items = [NSMutableArray array];
    for (NSString *name in names) {
        if (![name hasPrefix:@"metis-config-"] || ![name.pathExtension isEqualToString:@"plist"]) continue;
        MTConfigBackupItem *item = MTBackupItemForFile([directory stringByAppendingPathComponent:name]);
        if (item) [items addObject:item];
    }
    [items sortUsingComparator:^NSComparisonResult(MTConfigBackupItem *lhs, MTConfigBackupItem *rhs) {
        return [rhs.createdAt compare:lhs.createdAt];
    }];
    return items;
}

+ (MTConfigBackupItem *)createBackupWithError:(NSError **)error {
    NSDate *now = [NSDate date];
    NSMutableDictionary<NSString *, NSDictionary *> *preferences = [NSMutableDictionary dictionary];
    for (NSString *domain in MTCurrentPreferenceDomains()) {
        NSDictionary *values = MTCopyDomainValues(domain);
        if (values.count) preferences[domain] = values;
    }
    // 共享资源读不到（未初始化/损坏）时不阻断偏好域备份，仅不带该节。
    NSDictionary *sharedResources = [MTSharedResourceStore readSnapshot];
    NSMutableDictionary *document = [@{
        @"format" : MTConfigBackupFormat,
        @"schemaVersion" : @(MTConfigBackupCurrentSchemaVersion),
        @"createdAt" : [MTISOFormatter() stringFromDate:now],
        @"appVersion" : MTAppVersionString(),
        @"preferences" : preferences,
    } mutableCopy];
    if (sharedResources) document[@"sharedResources"] = sharedResources;

    NSString *path = MTBackupFilePathForDate(now);
    if (!MTWriteBackupDocument(document, path, error)) return nil;
    MTApplyRetention();
    MTLogInfo(MTLogModulePrefs, @"flow=config-backup state=created domains=%lu shared=%d",
              (unsigned long)preferences.count, sharedResources != nil);
    return MTBackupItemForFile(path);
}

+ (NSDictionary *)readBackupAtPath:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        if (error) *error = MTBackupError(MTConfigBackupErrorUnreadable, @"备份文件不存在或不可读");
        return nil;
    }
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:nil
                                                           error:nil];
    if (![plist isKindOfClass:NSDictionary.class]) {
        if (error) *error = MTBackupError(MTConfigBackupErrorUnreadable, @"备份文件不是合法的 plist");
        return nil;
    }
    NSDictionary *document = plist;
    if (![document[@"format"] isKindOfClass:NSString.class] ||
        ![document[@"format"] isEqualToString:MTConfigBackupFormat]) {
        if (error) *error = MTBackupError(MTConfigBackupErrorInvalidFile, @"不是 Metis 配置备份文件");
        return nil;
    }
    NSNumber *schema = [document[@"schemaVersion"] isKindOfClass:NSNumber.class] ? document[@"schemaVersion"] : nil;
    if (!schema) {
        if (error) *error = MTBackupError(MTConfigBackupErrorInvalidFile, @"备份缺少 schemaVersion");
        return nil;
    }
    if (schema.unsignedIntegerValue > MTConfigBackupCurrentSchemaVersion) {
        if (error) *error = MTBackupError(MTConfigBackupErrorFutureSchema,
            [NSString stringWithFormat:@"备份版本过新（schema %lu），请升级 Metis 后再恢复",
             (unsigned long)schema.unsignedIntegerValue]);
        return nil;
    }
    NSDictionary *preferences = document[@"preferences"];
    if (![preferences isKindOfClass:NSDictionary.class]) {
        if (error) *error = MTBackupError(MTConfigBackupErrorInvalidFile, @"备份缺少 preferences 节");
        return nil;
    }
    for (NSString *domain in preferences) {
        if (![preferences[domain] isKindOfClass:NSDictionary.class]) {
            if (error) *error = MTBackupError(MTConfigBackupErrorInvalidFile,
                [NSString stringWithFormat:@"备份中域 %@ 内容不合法", domain]);
            return nil;
        }
    }
    NSDictionary *sharedResources = document[@"sharedResources"];
    if ([sharedResources isKindOfClass:NSDictionary.class]) {
        // 提前过 store 校验：避免偏好域写一半才发现共享资源不可恢复。
        NSError *validation = [MTSharedResourceValidator validateDocument:sharedResources];
        if (validation) {
            if (error) *error = validation;
            return nil;
        }
    } else if (sharedResources != nil) {
        if (error) *error = MTBackupError(MTConfigBackupErrorInvalidFile, @"备份中共享资源节不合法");
        return nil;
    }
    return document;
}

+ (BOOL)restoreBackupAtPath:(NSString *)path error:(NSError **)error {
    NSDictionary *document = [self readBackupAtPath:path error:error];
    if (!document) return NO;

    // 1) 安全网：先把当前配置整体备份一份。失败不阻断恢复（恢复是用户明确
    //    意图，且备份目录故障通常也意味着本地无历史可回退），仅留日志。
    NSError *safetyError = nil;
    if (![self createBackupWithError:&safetyError]) {
        MTLogInfo(MTLogModulePrefs, @"flow=config-restore state=safety-backup-failed error=%@",
                  safetyError.localizedDescription);
    }

    // 2) 偏好域替换（含「备份中没有的域」→ 清空，精确回到备份态）。
    NSDictionary *preferences = document[@"preferences"];
    for (NSString *domain in MTCurrentPreferenceDomains()) {
        NSDictionary *values = [preferences[domain] isKindOfClass:NSDictionary.class] ? preferences[domain] : nil;
        if (!MTReplaceDomainValues(domain, values, error)) {
            MTLogInfo(MTLogModulePrefs, @"flow=config-restore state=domain-write-failed domain=%@", domain);
            return NO;
        }
    }

    // 3) 共享资源：走 store 低层安装（校验 + 原子替换 + 快照发布 + 失效通知）。
    NSDictionary *sharedResources = document[@"sharedResources"];
    if ([sharedResources isKindOfClass:NSDictionary.class]) {
        NSError *storeError = nil;
        if (![MTSharedResourceStore installDocument:sharedResources error:&storeError]) {
            if (error) *error = storeError;
            MTLogInfo(MTLogModulePrefs, @"flow=config-restore state=shared-install-failed");
            return NO;
        }
    }

    // 4) 热加载：flush 重发门控快照与 config-changed（capture/clipboard 适配器
    //    与 MTModuleGate 监听它），再补发键盘/剪切板既有刷新通知。
    [MTConfigService flush];
    MTPostDarwinNotification(MTKeyboardPrefsChangedName);
    MTPostDarwinNotification(MTClipboardPrefsReloadName);
    MTPostDarwinNotification(MTKeyboardShortcutRefreshName);
    MTPostDarwinNotification(MTClipboardShortcutChangedName);
    MTLogInfo(MTLogModulePrefs, @"flow=config-restore state=restored domains=%lu shared=%d",
              (unsigned long)preferences.count, sharedResources != nil);
    return YES;
}

+ (BOOL)deleteBackupAtPath:(NSString *)path error:(NSError **)error {
    NSString *directory = [self backupDirectory];
    if (![path.stringByDeletingLastPathComponent isEqualToString:directory]) {
        if (error) *error = MTBackupError(MTConfigBackupErrorInvalidFile, @"只能删除备份目录内的文件");
        return NO;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:path]) return YES; // 幂等：已不在即成功
    if (![fileManager removeItemAtPath:path error:error]) return NO;
    MTLogInfo(MTLogModulePrefs, @"flow=config-backup state=deleted");
    return YES;
}

+ (NSString *)importBackupFromPath:(NSString *)sourcePath error:(NSError **)error {
    // 导入前完整校验：format/schema/preferences/共享资源，不合法的文件不入库。
    NSDictionary *document = [self readBackupAtPath:sourcePath error:error];
    if (!document) return nil;
    NSString *path = MTBackupFilePathForDate([NSDate date]);
    if (!MTWriteBackupDocument(document, path, error)) return nil;
    MTApplyRetention();
    MTLogInfo(MTLogModulePrefs, @"flow=config-backup state=imported");
    return path;
}

+ (void)setBackupDirectoryOverride:(NSString *)path {
    pthread_mutex_lock(&gOverrideLock);
    gBackupDirectoryOverride = [path copy];
    pthread_mutex_unlock(&gOverrideLock);
}

+ (void)setPreferenceDomainOverride:(NSArray<NSString *> *)domains {
    pthread_mutex_lock(&gOverrideLock);
    gPreferenceDomainOverride = [domains copy];
    pthread_mutex_unlock(&gOverrideLock);
}

@end
