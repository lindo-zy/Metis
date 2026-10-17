#import "MTLegacyKayokoImporter.h"
#import "MTLog.h"
#import "MTPathResolver.h"

// 路径与域（逻辑路径，统一经 MTResolvePath 解析；roothide 环境换算 jbroot）。
// 与 MTHistoryStore/MTQuickAction/MTPreferenceKeys 内的 static 常量同值，
// 那些不外露，这里集中复述并保持同步。
static NSString *const MTLegacyKayokoSourceDirectory = @"/var/mobile/Library/com.lindo.kayoko/";
static NSString *const MTLegacyKayokoPreferencesPlist = @"/var/mobile/Library/Preferences/com.lindo.kayoko.preferences.plist";
static NSString *const MTLegacyMetisDataDirectory = @"/var/mobile/Library/com.lindo.metis.clipboard/";
static NSString *const MTLegacyMetisPreferencesDomain = @"com.lindo.metis.clipboard";

// marker 是小 plist：format=1 固定格式；attachments=0 表示附件合并未完成，
// 下次启动续跑（合并按同名跳过，续跑幂等且廉价）。
static NSString *const MTLegacyMarkerName = @"kayoko-import-v1.marker";
static NSString *const MTLegacyBackupSuffix = @".pre-kayoko.bak";
static NSString *const MTLegacyIncomingSuffix = @".incoming";
static NSString *const MTLegacyDatabaseName = @"history-v4.sqlite";

// 附件目录：数据库按文件名引用其中内容，逐文件合并、同名跳过。
static NSArray<NSString *> *MTLegacyAttachmentDirectories(void) {
    return @[@"images", @"rich-text"];
}

// 接管文件：目标已存在时备份为 *.pre-kayoko.bak 后替换——旧插件积累的用户
// 数据优先（本迁移的存在意义），Metis 侧冲突内容保留在备份里。
static NSArray<NSString *> *MTLegacyTakeoverFileNames(void) {
    return @[MTLegacyDatabaseName, @"custom-jumps-v1.plist", @"image-actions-v1.plist"];
}

#pragma mark - 文件操作辅助

static BOOL MTFileExists(NSFileManager *fm, NSString *path, BOOL *isDirectory) {
    return [fm fileExistsAtPath:path isDirectory:isDirectory];
}

// 单文件落位：先拷到 *.incoming 再原子改名，中断不会留下半份目标文件。
// replaceExisting 时先备份旧目标（备份只保留最新一份）。
static BOOL MTCopyFileToPath(NSString *source, NSString *destination, BOOL replaceExisting,
                             NSFileManager *fm, NSError **error) {
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:source isDirectory:&isDirectory] || isDirectory) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.lindo.metis.clipboard.kayoko-import"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey : @"source missing"}];
        }
        return NO;
    }

    BOOL destinationExists = [fm fileExistsAtPath:destination];
    if (destinationExists && !replaceExisting) return YES;

    if (destinationExists) {
        NSString *backup = [destination stringByAppendingString:MTLegacyBackupSuffix];
        [fm removeItemAtPath:backup error:nil];
        if (![fm moveItemAtPath:destination toPath:backup error:error]) return NO;
    }

    NSString *incoming = [destination stringByAppendingString:MTLegacyIncomingSuffix];
    [fm removeItemAtPath:incoming error:nil];
    if (![fm copyItemAtPath:source toPath:incoming error:error]) return NO;
    if (![fm moveItemAtPath:incoming toPath:destination error:error]) {
        [fm removeItemAtPath:incoming error:nil];
        return NO;
    }
    return YES;
}

// 目录递归合并：目标同名文件一律保留目标（附件由数据库按文件名引用，
// 同名即同内容；跳过让续跑/重复执行天然幂等）。返回新复制文件数。
static NSUInteger MTMergeDirectoryContents(NSString *source, NSString *destination,
                                           NSFileManager *fm, NSError **error) {
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:source isDirectory:&isDirectory] || !isDirectory) return 0;
    if (![fm fileExistsAtPath:destination isDirectory:&isDirectory] || !isDirectory) {
        if (![fm createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:error]) {
            return NSUIntegerMax;
        }
    }

    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:source error:error];
    if (!entries) return NSUIntegerMax;

    NSUInteger copied = 0;
    for (NSString *entry in entries) {
        NSString *from = [source stringByAppendingPathComponent:entry];
        NSString *to = [destination stringByAppendingPathComponent:entry];
        BOOL entryIsDirectory = NO;
        if (![fm fileExistsAtPath:from isDirectory:&entryIsDirectory]) continue;
        if (entryIsDirectory) {
            NSUInteger subCopied = MTMergeDirectoryContents(from, to, fm, error);
            if (subCopied == NSUIntegerMax) return NSUIntegerMax;
            copied += subCopied;
            continue;
        }
        if ([fm fileExistsAtPath:to]) continue;
        if (![fm copyItemAtPath:from toPath:to error:error]) return NSUIntegerMax;
        copied++;
    }
    return copied;
}

static BOOL MTWriteMarker(NSString *markerPath, BOOL attachmentsMerged, NSFileManager *fm) {
    NSDictionary *marker = @{
        @"format" : @1,
        @"date" : [NSDate date],
        @"attachments" : @(attachmentsMerged),
    };
    if (![marker writeToFile:markerPath atomically:YES]) return NO;
    [fm setAttributes:@{NSFilePosixPermissions : @0644} ofItemAtPath:markerPath error:nil];
    return YES;
}

#pragma mark - 偏好合并

// 逐键 only-if-absent 合入目标域：用户已在 Metis 改过的键不动，其余继承旧值。
// 排除 Enabled（模块启停权威在 MTModuleGate，v3 P03 退役）；只接受 plist 可序列化值。
static NSUInteger MTMergePreferencesFromDictionary(NSDictionary *legacy, CFStringRef domain) {
    if (![legacy isKindOfClass:NSDictionary.class] || legacy.count == 0) return 0;

    NSUInteger merged = 0;
    for (NSString *key in legacy.allKeys) {
        if (![key isKindOfClass:NSString.class] || [key isEqualToString:@"Enabled"]) continue;
        id value = legacy[key];
        if (![value isKindOfClass:NSString.class] && ![value isKindOfClass:NSNumber.class] &&
            ![value isKindOfClass:NSArray.class] && ![value isKindOfClass:NSDictionary.class] &&
            ![value isKindOfClass:NSData.class] && ![value isKindOfClass:NSDate.class]) {
            continue;
        }
        CFPropertyListRef existing = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
        if (existing != NULL) {
            CFRelease(existing);
            continue;
        }
        CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                              domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        merged++;
    }
    if (merged > 0) {
        CFPreferencesAppSynchronize(domain);
    }
    return merged;
}

#pragma mark - 附件阶段（可独立续跑）

@implementation MTLegacyKayokoImporter

+ (NSString *)markerPathForDataDirectory:(NSString *)dataDirectory {
    return [dataDirectory stringByAppendingPathComponent:MTLegacyMarkerName];
}

+ (BOOL)mergeAttachmentsFromDataDirectory:(NSString *)sourceDirectory
                        intoDataDirectory:(NSString *)targetDirectory
                                     error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger copied = 0;
    for (NSString *name in MTLegacyAttachmentDirectories()) {
        NSString *from = [sourceDirectory stringByAppendingPathComponent:name];
        NSString *to = [targetDirectory stringByAppendingPathComponent:name];
        NSUInteger subCopied = MTMergeDirectoryContents(from, to, fm, error);
        if (subCopied == NSUIntegerMax) return NO;
        copied += subCopied;
    }
    NSString *markerPath = [self markerPathForDataDirectory:targetDirectory];
    if (!MTWriteMarker(markerPath, YES, fm)) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.lindo.metis.clipboard.kayoko-import"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey : @"marker write failed"}];
        }
        return NO;
    }
    MTLogInfo(MTLogModuleClipboard, @"state=kayoko-attachments-merged copied=%lu",
              (unsigned long)copied);
    return YES;
}

+ (BOOL)importFromDataDirectory:(NSString *)sourceDirectory
      legacyPreferencesPlist:(NSString *)legacyPlistPath
           intoDataDirectory:(NSString *)targetDirectory
         preferencesDomain:(NSString *)domain
                      error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *markerPath = [self markerPathForDataDirectory:targetDirectory];

    NSDictionary *marker = [NSDictionary dictionaryWithContentsOfFile:markerPath];
    if ([marker isKindOfClass:NSDictionary.class] && [marker[@"format"] isEqual:@1]) {
        // 已迁移过：同步阶段是 no-op，避免重装备份链反复推挤 *.bak。
        return YES;
    }

    BOOL sourceIsDirectory = NO;
    BOOL sourceExists = [fm fileExistsAtPath:sourceDirectory isDirectory:&sourceIsDirectory];
    if (!sourceExists || !sourceIsDirectory) {
        // 没有旧数据：直接落完成标记，此后每次启动零成本跳过。
        if (![fm fileExistsAtPath:targetDirectory isDirectory:&sourceIsDirectory] || !sourceIsDirectory) {
            if (![fm createDirectoryAtPath:targetDirectory
                        withIntermediateDirectories:YES attributes:nil error:error]) {
                return NO;
            }
        }
        if (!MTWriteMarker(markerPath, YES, fm)) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.lindo.metis.clipboard.kayoko-import"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey : @"marker write failed"}];
            }
            return NO;
        }
        MTLogInfo(MTLogModuleClipboard, @"state=kayoko-import-skipped reason=no-legacy-data");
        return YES;
    }

    if (![fm fileExistsAtPath:targetDirectory isDirectory:&sourceIsDirectory] || !sourceIsDirectory) {
        if (![fm createDirectoryAtPath:targetDirectory
                    withIntermediateDirectories:YES attributes:nil error:error]) {
            return NO;
        }
    }

    // —— 同步阶段：小体积核心数据（数据库/动作定义/v3 遗留 json），失败不写
    // marker，下次启动整阶段重试（各步幂等）。
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:sourceDirectory error:error];
    if (!entries) return NO;

    NSArray<NSString *> *takeover = MTLegacyTakeoverFileNames();
    NSArray<NSString *> *attachments = MTLegacyAttachmentDirectories();
    NSUInteger takenOver = 0, copiedIfAbsent = 0, skippedExisting = 0;
    for (NSString *entry in entries) {
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:[sourceDirectory stringByAppendingPathComponent:entry]
                       isDirectory:&isDirectory]) {
            continue;
        }
        NSString *from = [sourceDirectory stringByAppendingPathComponent:entry];
        NSString *to = [targetDirectory stringByAppendingPathComponent:entry];

        if (isDirectory) {
            // 附件目录不在同步阶段处理（可能很大，走后台续跑）；未知目录跳过并记录。
            if (![attachments containsObject:entry]) {
                MTLogInfo(MTLogModuleClipboard, @"state=kayoko-import-skip-entry entry=%@ kind=unknown-dir", entry);
            }
            continue;
        }

        // 数据库 WAL 伴生文件（-wal/-shm）随库一起接管，保证最近事务不丢。
        BOOL isDatabaseSidecar = [entry hasPrefix:[MTLegacyDatabaseName stringByAppendingString:@"-"]];
        if ([takeover containsObject:entry] || isDatabaseSidecar) {
            if (!MTCopyFileToPath(from, to, YES, fm, error)) return NO;
            takenOver++;
            continue;
        }
        if ([fm fileExistsAtPath:to]) {
            skippedExisting++;
            continue;
        }
        if (!MTCopyFileToPath(from, to, NO, fm, error)) return NO;
        copiedIfAbsent++;
    }

    // —— 偏好合并：失败只记日志（only-if-absent 幂等，缺同步可下次补）。
    NSDictionary *legacyPreferences = [NSDictionary dictionaryWithContentsOfFile:legacyPlistPath];
    NSUInteger mergedPreferences = MTMergePreferencesFromDictionary(
        legacyPreferences, (__bridge CFStringRef)domain);

    // marker 先按 attachments=0 落盘：即使随后崩溃，下次启动也只续跑附件合并。
    if (!MTWriteMarker(markerPath, NO, fm)) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.lindo.metis.clipboard.kayoko-import"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey : @"marker write failed"}];
        }
        return NO;
    }

    MTLogInfo(MTLogModuleClipboard,
              @"state=kayoko-import-sync-done takeover=%lu copied=%lu skipped=%lu prefs=%lu",
              (unsigned long)takenOver, (unsigned long)copiedIfAbsent,
              (unsigned long)skippedExisting, (unsigned long)mergedPreferences);
    return YES;
}

+ (void)importLegacyDataIfNeeded {
    NSString *source = MTResolvePath(MTLegacyKayokoSourceDirectory);
    NSString *preferencesPlist = MTResolvePath(MTLegacyKayokoPreferencesPlist);
    NSString *target = MTResolvePath(MTLegacyMetisDataDirectory);
    NSString *markerPath = [self markerPathForDataDirectory:target];

    BOOL syncPhaseNeeded = YES;
    NSDictionary *marker = [NSDictionary dictionaryWithContentsOfFile:markerPath];
    if ([marker isKindOfClass:NSDictionary.class] && [marker[@"format"] isEqual:@1]) {
        syncPhaseNeeded = NO;
    }

    if (syncPhaseNeeded) {
        NSError *error = nil;
        if (![self importFromDataDirectory:source
                    legacyPreferencesPlist:preferencesPlist
                        intoDataDirectory:target
                      preferencesDomain:MTLegacyMetisPreferencesDomain
                                   error:&error]) {
            // 失败不阻断安装流程；不写 marker，下次启动整阶段重试。
            MTLogError(MTLogModuleClipboard, @"state=kayoko-import-failed reason=%@",
                       error.localizedDescription ?: @"unknown");
            return;
        }
    }

    if ([marker isKindOfClass:NSDictionary.class] && [marker[@"attachments"] boolValue]) {
        return;
    }

    // 附件可能数百 MB：utility 队列后台合并，不拖慢 dyld 安装期；同名跳过
    // 保证与随后到达的剪切板事件互不干扰。
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *attachmentError = nil;
        if (![self mergeAttachmentsFromDataDirectory:source intoDataDirectory:target
                                                error:&attachmentError]) {
            MTLogWarn(MTLogModuleClipboard, @"state=kayoko-attachments-pending reason=%@",
                      attachmentError.localizedDescription ?: @"unknown");
        }
    });
}

@end
