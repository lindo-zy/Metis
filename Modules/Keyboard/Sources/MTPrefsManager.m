#import "common.h"
#import "MTPrefsManager.h"
#import "MTModuleGate.h"
#import "MTPanelRegistry.h"
#import "MTSharedResourceStore.h"
#import "MTSharedResourceMigration.h"
#import "MTSharedResourceLegacyBridge.h"

static NSString *const MTSharedPrefsFormatKey = @"_typexSnapshotFormat";
static NSString *const MTSharedPrefsPayloadKey = @"preferences";
static const NSInteger MTSharedPrefsFormatVersion = 1;

@interface MTPrefsManager ()
@property(nonatomic, assign, readwrite) BOOL preferencesAvailable;
@end

static void reloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name,
                        const void *object, CFDictionaryRef userInfo) {
    [(__bridge MTPrefsManager *)observer reload];
}

@implementation MTPrefsManager

+ (void)load {
    @autoreleasepool {
        NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
        if (args.count == 0) return;

        // This class is linked only into MetisKeyboard targets.  Initialise it in every
        // host that loads MetisKeyboard so app extensions follow the same non-SpringBoard
        // sandbox policy as +isRunningInSandbox.
        [MTPrefsManager sharedInstance];
    }
}

+ (instancetype)sharedInstance {
    static dispatch_once_t predicate;
    static MTPrefsManager *manager;
    dispatch_once(&predicate, ^{ manager = [[self alloc] init]; });
    return manager;
}

+ (BOOL)isRunningInSandbox {
    NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
    if (args.count == 0) return NO;

    // Only SpringBoard and the Settings host (Preferences) can reach the
    // authoritative cfprefsd domain and the preference plist.  Apps and
    // keyboard extensions are sandboxed away from /var/mobile/Library and from
    // cross-process messaging; they read and write through the shared snapshot
    // that the unsandboxed hosts seed and mirror.  Settings MUST be classified
    // as unsandboxed or its writes would never reach the domain SpringBoard
    // reads.
    NSString *executablePath = args[0];
    NSString *processName = executablePath.lastPathComponent;
    BOOL isSpringBoardProcess = [processName isEqualToString:@"SpringBoard"];
    BOOL isSettingsProcess = [processName isEqualToString:@"Preferences"];
    return !(isSpringBoardProcess || isSettingsProcess);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge const void *)self, &reloadPrefs,
                                         (CFStringRef)kPrefsChangedIdentifier, NULL, 0);
        [self reload];
        [self healSharedPrefsIfNeeded];
    }
    return self;
}

#pragma mark - Shared snapshot for sandboxed processes

static NSString *MTSharedPrefsPath(void) {
    return TypeXSharedPrefsPath;
}

- (void)writeSharedPrefs:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return;
    NSString *path = MTSharedPrefsPath();
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        // World-writable and NOT sticky: mobile writers atomically replace the
        // root-owned seed file staged by the package, which sticky would forbid.
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0777} error:nil];
    }
    // 资源键（动作/面板/绑定）不再镜像进键盘快照：沙盒宿主从
    // /Library/Metis/Config/global-shared.plist 读取共享资源（世界可读），
    // 键盘快照只承载宿主细节参数，避免双权威。
    NSMutableDictionary *payload = [dictionary mutableCopy];
    for (NSString *key in [MTSharedResourceLegacyBridge bridgedResourceKeys]) [payload removeObjectForKey:key];
    // The envelope makes an intentionally empty preference set distinguishable
    // from a missing/unreadable file.  Without that distinction an app could
    // render the six defaults while the real user configuration was simply
    // unavailable.
    NSDictionary *snapshot = @{
        MTSharedPrefsFormatKey: @(MTSharedPrefsFormatVersion),
        MTSharedPrefsPayloadKey: [payload copy]
    };
    [snapshot writeToFile:path atomically:YES];
    // Sandboxed app hosts read this snapshot; keep it world-readable whatever
    // the writing process' umask is.
    NSDictionary *attrs = @{
        NSFilePosixPermissions: @0644,
        NSFileProtectionKey: NSFileProtectionNone
    };
    [fm setAttributes:attrs ofItemAtPath:path error:nil];
}

- (NSDictionary *)readSharedPrefs {
    // 一次性诊断：沙盒进程偏好不可用时，先确认快照文件的路径与可读性。
    static dispatch_once_t onceDiagToken;
    dispatch_once(&onceDiagToken, ^{
        NSString *path = MTSharedPrefsPath();
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        NSLog(@"[MetisKeyboard] diag: snapshot path=%@ exists=%d readable=%d size=%lu sandbox=%d",
              path, [fm fileExistsAtPath:path], [fm isReadableFileAtPath:path],
              (unsigned long)attrs.fileSize, [MTPrefsManager isRunningInSandbox]);
    });
    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:MTSharedPrefsPath()];
    if (![snapshot isKindOfClass:[NSDictionary class]]) return nil;

    NSNumber *format = snapshot[MTSharedPrefsFormatKey];
    NSDictionary *payload = snapshot[MTSharedPrefsPayloadKey];
    if ([format isKindOfClass:[NSNumber class]] &&
        format.integerValue == MTSharedPrefsFormatVersion &&
        [payload isKindOfClass:[NSDictionary class]]) {
        // 沙盒宿主的共享资源来源是 global-shared.plist 快照；与键盘细节
        // 参数合并后返回完整 legacy 视图（04 §2：不在绑定页复制资源定义）。
        NSMutableDictionary *merged = [MTPanelMigratePreferences(payload) mutableCopy];
        [MTSharedResourceLegacyBridge applyStoreSnapshot:[MTSharedResourceStore readSnapshot]
                                    toLegacyPreferences:merged];
        return merged;
    }

    // 只接受当前信封格式：旧插件（2.7.44-2.7.65）的无信封快照一律视为
    // 不存在（Metis 不读取其他插件写下的旧值），由 heal 重建。
    return nil;
}

// Seed the shared snapshot from the authoritative domain when it is missing or
// carries no payload (first launch after install, an erased cache, or a
// snapshot poisoned as "intentionally empty" by an early-boot read).  Never
// overwrite a live snapshot: every writer that can reach the domain also
// mirrors its full result into the snapshot, so the snapshot is never behind
// the domain, while sandboxed writers (dock toggle) reach ONLY the snapshot --
// replacing it from the domain would silently revert their writes.
//
// Deliberately NO retry timers and NO change notification from here: both
// were tried and could self-amplify on SpringBoard's main runloop (hard hang,
// no safe mode).  This method keeps the original shape -- one synchronous
// pass per invocation, converging on the first successful write.
- (void)healSharedPrefsIfNeeded {
    if ([MTPrefsManager isRunningInSandbox]) return;

    NSDictionary *snapshotFile = [NSDictionary dictionaryWithContentsOfFile:MTSharedPrefsPath()];
    BOOL snapshotIsCurrentFormat = [snapshotFile[MTSharedPrefsFormatKey] isKindOfClass:[NSNumber class]] &&
        [snapshotFile[MTSharedPrefsFormatKey] integerValue] == MTSharedPrefsFormatVersion &&
        [snapshotFile[MTSharedPrefsPayloadKey] isKindOfClass:[NSDictionary class]];
    // Live = current format WITH payload.  An empty-payload snapshot is not
    // live: right after install/respring the preferences daemon may briefly
    // report an empty domain, and freezing that as the "intentionally empty"
    // snapshot poisoned every later heal (the install-needs-a-Settings-visit
    // bug).  It stays healable instead.
    if (snapshotIsCurrentFormat && [snapshotFile[MTSharedPrefsPayloadKey] count] > 0) return;

    // Also replaces a legacy (pre-format) snapshot once: older sandboxed
    // hosts could leave it readable but incomplete.  Seed only from a
    // successful non-empty domain read — an empty read is much more likely a
    // cold daemon than a real "never configured", and the next heal trigger
    // (any preferences change reloads this manager) retries naturally.
    NSDictionary *authoritative = [self readPrefs];
    if ([authoritative isKindOfClass:[NSDictionary class]] && authoritative.count > 0) {
        [self writeSharedPrefs:authoritative];
    }
}

#pragma mark - Read

// The legacy plist is SpringBoard's cold-boot fallback when cfprefsd has not
// materialized the domain yet (ctor runs before first unlock after a reboot).
// A protection class locked until first unlock would make that fallback -- and
// the heal seeding that depends on it -- read empty exactly when it is needed;
// match the shared snapshot's None class.
static void MTWritePrefsPlist(NSDictionary *dictionary) {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return;
    if (![dictionary writeToFile:kPrefsPath atomically:YES]) return;
    [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey: NSFileProtectionNone}
                                      ofItemAtPath:kPrefsPath
                                             error:nil];
}

// No IPC: CPDistributedMessagingCenter between an app sandbox and SpringBoard
// needs RocketBootstrap, which this package deliberately does not depend on.
// Sandboxed hosts use only the shared snapshot.  A sandbox's CFPreferences call
// addresses that app's own container and can return a non-empty but unrelated
// dictionary; accepting it used to make the toolbar fall back to six defaults.
- (NSDictionary *)readPrefsFromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        NSDictionary *shared = [self readSharedPrefs];
        if ([shared isKindOfClass:[NSDictionary class]]) return shared;

        // An atomic replacement can still be momentarily unavailable on a few
        // filesystems.  Preserve the last complete snapshot rather than
        // replacing configured buttons with defaults.
        return self.preferencesAvailable ? self.prefs : nil;
    }
    return [self readPrefs];
}

- (NSDictionary *)readPrefs {
    CFStringRef appID = (CFStringRef)kIdentifier;
    CFPreferencesAppSynchronize(appID);

    CFArrayRef keyList = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *preferences = nil;
    if (keyList) {
        preferences = CFBridgingRelease(CFPreferencesCopyMultiple(keyList, appID,
                                                                   kCFPreferencesCurrentUser,
                                                                   kCFPreferencesAnyHost));
        CFRelease(keyList);
    }

    // PreferenceLoader/cfprefsd is the source of truth on iOS 17.  Keep the
    // plist fallback for old installs and for the short window before the
    // preferences daemon has materialized the domain.
    NSMutableDictionary *dictionary;
    if ([preferences isKindOfClass:[NSDictionary class]] && preferences.count > 0) {
        dictionary = [MTPanelMigratePreferences(preferences) mutableCopy];
    } else {
        dictionary = [MTPanelMigratePreferences([NSDictionary dictionaryWithContentsOfFile:kPrefsPath] ?: @{}) mutableCopy];
    }
    if (!dictionary) dictionary = [NSMutableDictionary dictionary];
    // Metis 门控桥接：唯一整体开关权威是 com.lindo.metis（MTModuleGate）；
    // 旧模块键已退役，旧域 enabledBOOL 仅保存细节配置，运行端读取一律被
    // 总开关覆盖（04-module-integration §2）。
    [MTModuleGate reload];
    dictionary[kEnabledkey] = @([MTModuleGate globalEnabled]);
    // 共享资源（动作/面板/分组/绑定）：非沙盒读取端惰性初始化共享库
    // （首装或旧数据迁移，幂等），随后以 store 导出的 legacy 视图覆盖
    // 键盘域中的同名键——键盘域不再承载资源定义（04 §6 单一配置源）。
    [MTSharedResourceMigration ensureInstalledWithLegacyPreferences:dictionary];
    [MTSharedResourceLegacyBridge applyStoreSnapshot:[MTSharedResourceStore readSnapshot]
                                toLegacyPreferences:dictionary];
    return dictionary;
}

#pragma mark - Write

// Writers converge on every channel they can reach.  An unsandboxed host
// (Settings, SpringBoard) replaces the authoritative domain -- replacing, not
// merging, so removed keys do not survive -- and mirrors the result into the
// snapshot.  A sandboxed host can only reach the snapshot: it MERGES there,
// because its readPrefs is empty and a blind replace would erase every other
// preference (e.g. a dock toggle writing only toggledOnBOOL).
// 资源键（动作/面板/分组/绑定）在非沙盒端改走共享 store 提交；键盘域与
// 键盘快照都不再持久化这些键。沙盒端只写宿主参数，资源键不会出现在其
// 写入路径上（沙盒无法成为资源写端）。
- (void)writePrefs:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return;

    BOOL isSandbox = [MTPrefsManager isRunningInSandbox];
    NSDictionary *snapshot = dictionary;
    if (isSandbox) {
        NSMutableDictionary *merged = [[self readSharedPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
        [merged addEntriesFromDictionary:dictionary];
        snapshot = merged;
    } else {
        NSMutableDictionary *domainPart = [dictionary mutableCopy];
        BOOL touchedResources = NO;
        for (NSString *key in [MTSharedResourceLegacyBridge bridgedResourceKeys]) {
            if (domainPart[key] != nil) {
                [domainPart removeObjectForKey:key];
                touchedResources = YES;
            }
        }
        if (touchedResources) {
            NSError *resourceError = nil;
            if (![MTSharedResourceLegacyBridge applyLegacyPreferences:dictionary error:&resourceError]) {
                // 资源提交失败（冲突/校验）不阻断宿主参数写入；下次整份
                // 写入会重试。失败已由 store 层记录日志。
                (void)resourceError;
            }
        }
        CFStringRef appID = (CFStringRef)kIdentifier;
        CFPreferencesAppSynchronize(appID);

        // Replace the domain, rather than only setting keys.  This matters for
        // removed shortcuts: stale keys must not survive an iOS 17 cfprefsd write.
        CFArrayRef existingKeys = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSMutableArray *keysToRemove = [NSMutableArray array];
        if (existingKeys) {
            for (NSString *existingKey in (__bridge NSArray *)existingKeys) {
                if (!domainPart[existingKey]) [keysToRemove addObject:existingKey];
            }
            CFRelease(existingKeys);
        }
        // 旧安装域里残留的资源键也一并清除（store 已是唯一权威）。
        [keysToRemove addObjectsFromArray:[MTSharedResourceLegacyBridge bridgedResourceKeys]];
        CFPreferencesSetMultiple((__bridge CFDictionaryRef)domainPart,
                                 (__bridge CFArrayRef)keysToRemove,
                                 appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize(appID);

        // Keep the on-disk representation available to legacy preference cells.
        MTWritePrefsPlist(domainPart);
        snapshot = domainPart;
    }

    self.prefs = [snapshot copy];
    self.preferencesAvailable = YES;
    [self writeSharedPrefs:snapshot];
    [self postChangedNotification];
}

#pragma mark - Set / Get / Remove

- (void)setValue:(id)value forKey:(NSString *)key fromSandbox:(BOOL)isSandbox {
    [self setValue:value forKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key {
    if (key.length == 0) return;
    BOOL isSandbox = [MTPrefsManager isRunningInSandbox];
    NSDictionary *base = [self readPrefsFromSandbox:isSandbox];
    // Never turn a failed sandbox read into a new one-key snapshot: that would
    // erase the shortcut order for every other process.
    if (isSandbox && ![base isKindOfClass:[NSDictionary class]]) return;
    NSMutableDictionary *dictionary = [base mutableCopy] ?: [NSMutableDictionary dictionary];
    if (value) dictionary[key] = value;
    else [dictionary removeObjectForKey:key];
    [self writePrefs:dictionary];
}

- (id)getValueForKey:(NSString *)key fromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        return [self readPrefsFromSandbox:YES][key];
    }
    return [self getValueForKey:key];
}

- (id)getValueForKey:(NSString *)key {
    return [self readPrefs][key];
}

- (void)removeKey:(NSString *)key fromSandbox:(BOOL)isSandbox {
    [self removeKey:key];
}

- (void)removeKey:(NSString *)key {
    [self removeKey:key notify:YES];
}

- (void)removeKey:(NSString *)key notify:(BOOL)notify {
    if (key.length == 0) return;

    // The snapshot is a sandboxed process' only persistent channel; removing
    // the key there must not carry the empty readPrefs result over it.
    if ([MTPrefsManager isRunningInSandbox]) {
        NSDictionary *base = [self readPrefsFromSandbox:YES];
        if (![base isKindOfClass:[NSDictionary class]]) return;
        NSMutableDictionary *snapshot = [base mutableCopy];
        [snapshot removeObjectForKey:key];
        self.prefs = [snapshot copy];
        self.preferencesAvailable = YES;
        [self writeSharedPrefs:snapshot];
        if (notify) [self postChangedNotification];
        return;
    }

    CFStringRef appID = (CFStringRef)kIdentifier;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, appID);
    CFPreferencesAppSynchronize(appID);

    NSMutableDictionary *dictionary = [[self readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    [dictionary removeObjectForKey:key];
    MTWritePrefsPlist(dictionary);
    self.prefs = [dictionary copy];
    self.preferencesAvailable = YES;
    [self writeSharedPrefs:dictionary];
    if (notify) [self postChangedNotification];
}

- (void)postChangedNotification {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          (CFStringRef)kPrefsChangedIdentifier, NULL, NULL, YES);
}

- (void)reload {
    NSDictionary *loaded = [self readPrefsFromSandbox:[MTPrefsManager isRunningInSandbox]];
    if ([loaded isKindOfClass:[NSDictionary class]]) {
        self.prefs = [loaded copy];
        self.preferencesAvailable = YES;
    }
    [self healSharedPrefsIfNeeded];
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        (CFStringRef)kPrefsChangedIdentifier, NULL);
}

@end
