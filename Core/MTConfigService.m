#import "MTConfigService.h"
#import "MTModuleGate.h"
#import "MTPathResolver.h"
#import "MTLog.h"
#import <CoreFoundation/CoreFoundation.h>

static void MTPostConfigChanged(void) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)MTConfigChangedNotification,
        NULL,
        NULL,
        TRUE);
}

// 沙盒宿主（app/键盘扩展）读不到权威域也读不到 /var/mobile 偏好文件；
// flush 时把四个门控键镜像成世界可读快照，作为它们唯一的门控来源。
// 写失败不阻断 flush：Darwin 广播照发，非沙盒宿主不受影响，沙盒宿主
// 维持上一次成功快照（首装无快照 = 默认关，安全方向）。
static void MTWriteGateSnapshot(void) {
    NSString *directory = MTPublicConfigDirectory();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) {
        if (![fileManager createDirectoryAtPath:directory
                                 withIntermediateDirectories:YES
                                  attributes:@{NSFilePosixPermissions: @0777}
                                                       error:nil]) {
            MTLogInfo(MTLogModulePrefs, @"state=gate-snapshot-mkdir-failed");
            return;
        }
    }

    NSMutableDictionary<NSString *, NSNumber *> *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in [@[@"enabled"] arrayByAddingObjectsFromArray:MTAllModuleIDs]) {
        NSString *valueKey = [key isEqualToString:@"enabled"] ? key : [NSString stringWithFormat:@"%@Enabled", key];
        CFPropertyListRef raw = CFPreferencesCopyAppValue(
            (__bridge CFStringRef)valueKey, (__bridge CFStringRef)MTConfigDomain);
        id value = raw ? (__bridge_transfer id)raw : nil;
        snapshot[valueKey] = @([value respondsToSelector:@selector(boolValue)] && [value boolValue]);
    }

    NSString *path = MTGateSnapshotPath();
    if (![snapshot writeToFile:path atomically:YES]) {
        MTLogInfo(MTLogModulePrefs, @"state=gate-snapshot-write-failed");
        return;
    }
    // 世界可读 + 无文件保护：沙盒进程与首解锁前的冷启动路径都要能读。
    [fileManager setAttributes:@{
        NSFilePosixPermissions: @0644,
        NSFileProtectionKey: NSFileProtectionNone
    } ofItemAtPath:path error:nil];
}

@implementation MTConfigService

+ (void)setGlobalEnabled:(BOOL)enabled {
    CFPreferencesSetValue(
        (__bridge CFStringRef)@"enabled",
        (enabled ? kCFBooleanTrue : kCFBooleanFalse),
        (__bridge CFStringRef)MTConfigDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    MTLogInfo(MTLogModulePrefs, @"state=global-set enabled=%d", enabled);
}

+ (void)setModule:(NSString *)moduleID enabled:(BOOL)enabled {
    NSString *key = [NSString stringWithFormat:@"%@Enabled", moduleID];
    CFPreferencesSetValue(
        (__bridge CFStringRef)key,
        (enabled ? kCFBooleanTrue : kCFBooleanFalse),
        (__bridge CFStringRef)MTConfigDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    MTLogInfo(MTLogModulePrefs, @"state=module-set module=%@ enabled=%d", moduleID, enabled);
}

+ (void)flush {
    // 触发 MTModuleGate +initialize（填充 MTAllModuleIDs）并刷新进程内快照，
    // 随后快照镜像从这里重读权威域，保持单一事实源。
    [MTModuleGate reload];
    CFPreferencesSynchronize(
        (__bridge CFStringRef)MTConfigDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    MTWriteGateSnapshot();
    MTPostConfigChanged();
}

@end
