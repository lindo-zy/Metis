#import "MTSharedResourceMigration.h"
#import "MTSharedResourceStore.h"
#import "MTSharedResourceValidator.h"
#import "MTSharedResourceLegacyBridge.h"
#import "MTSharedResourceIDs.h"
#import "MTPathResolver.h"
#import "MTLog.h"

static BOOL MTMigrationSandboxed(void) {
    // 主机测试钩子：与 MTPrefsManager.isRunningInSandbox 同语义，仅
    // SpringBoard 与 Preferences（设置宿主）非沙盒；沙盒进程不执行初始化写入。
    if (getenv("METIS_HOST_TEST")) return NO;
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    if (arguments.count == 0) return NO;
    NSString *processName = [arguments[0] lastPathComponent];
    return ![processName isEqual:@"SpringBoard"] && ![processName isEqual:@"Preferences"];
}

static BOOL MTMigrationIsSettingsProcess(void) {
    if (getenv("METIS_HOST_TEST")) return YES; // 主机测试按设置端对待。
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    if (arguments.count == 0) return YES;
    return [[arguments[0] lastPathComponent] isEqual:@"Preferences"];
}

@implementation MTSharedResourceMigration

+ (NSString *)preMigrationBackupPath {
    return [MTResolvePath(@"/var/mobile/Library/Metis/Global")
        stringByAppendingPathComponent:@"backup/pre-migration.plist"];
}

+ (BOOL)ensureInstalledWithLegacyPreferences:(NSDictionary *)legacyPreferences {
    if (MTMigrationSandboxed()) return NO;
    NSError *readError = nil;
    NSDictionary *existing = [MTSharedResourceStore readSnapshotError:&readError];
    if (existing) return NO; // 已安装：幂等 no-op（publicationPending 的重试发布在下次提交时自愈）。
    // 读失败 ≠ 空库（05 §1）：权威/快照任一存在却不 readable（损坏或未来
    // schema）时不重建、不覆盖，维持「暂不可用」状态等待人工处理。
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:[MTSharedResourceStore authoritativePath]] ||
        [fileManager fileExistsAtPath:[MTSharedResourceStore snapshotPath]]) {
        MTLogInfo(MTLogModuleCore, @"flow=migration state=unreadable-store-kept reason=%@",
                  readError.localizedDescription);
        return NO;
    }

    // planned → backedUp：旧输入先备份（仅最近一份；不进公共快照）。
    NSDictionary *source = [legacyPreferences isKindOfClass:NSDictionary.class] ? legacyPreferences : @{};
    BOOL hasLegacyResources = NO;
    for (NSString *key in [MTSharedResourceLegacyBridge bridgedResourceKeys]) {
        id value = source[key];
        if ([value isKindOfClass:NSArray.class] && [(NSArray *)value count] > 0) hasLegacyResources = YES;
        if ([value isKindOfClass:NSDictionary.class] && [(NSDictionary *)value count] > 0) hasLegacyResources = YES;
    }
    // 首装空库的落库者只允许设置端：SpringBoard 冷启动（首解锁前）可能读到
    // 空域，此时把空库固化会让升级用户的旧动作永远迁不进来。SB 仅在确实
    // 读到旧资源时迁移；全新安装的用户第一次进设置时再创建合法空库。
    if (!hasLegacyResources && !MTMigrationIsSettingsProcess()) return NO;
    if (hasLegacyResources) {
        NSString *backupPath = [self preMigrationBackupPath];
        [[NSFileManager defaultManager] createDirectoryAtPath:[backupPath stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        [source writeToFile:backupPath atomically:YES];
    }

    // validated → canonicalCommitted → published：离线构建 → 验证 → 原子安装。
    NSDictionary *document = [MTSharedResourceLegacyBridge
        documentByImportingLegacyPreferences:source intoDocument:nil];
    NSError *validation = [MTSharedResourceValidator validateDocument:document];
    if (validation) {
        // 不把半迁移数据当有效库安装：保留现状（读取侧维持不可用），
        // 记录错误日志等待下次触发；绝不回退成空库覆盖用户数据。
        MTLogInfo(MTLogModuleCore, @"flow=migration state=validation-failed");
        return NO;
    }
    BOOL installed = [MTSharedResourceStore installDocument:document error:nil];
    MTLogInfo(MTLogModuleCore, @"flow=migration state=%@ actions=%lu panels=%lu bindings=%lu",
              installed ? @"installed" : @"install-failed",
              (unsigned long)[document[@"actions"] count],
              (unsigned long)[document[@"panels"] count],
              (unsigned long)[document[@"bindings"] count]);
    return installed;
}

@end
