// MTPrefsBackupController —— 配置备份页（全局「配置维护」入口）。
// 立即备份全部偏好域 + 共享资源；列表展示已有备份，支持导出分享
// （UIDocumentPicker 导出）与删除。核心逻辑在 MTConfigBackupService。
#import <Preferences/Preferences.h>
#import <UIKit/UIKit.h>

#import "MTPrefsBackupController.h"
#import "MTConfigBackupService.h"

static NSString *MTBackupFormatTime(NSDate *date) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return [formatter stringFromDate:date];
}

static NSString *MTBackupFormatSize(uint64_t bytes) {
    if (bytes >= 1024ULL * 1024ULL) {
        return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    }
    return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
}

static NSString *MTBackupFormatSummary(MTConfigBackupItem *item) {
    NSString *scope = item.includesSharedResources ? @"，含共享资源" : @"";
    return [NSString stringWithFormat:@"%lu 项配置%@ · %@",
            (unsigned long)item.domainCount, scope, MTBackupFormatSize(item.byteSize)];
}

@interface MTPrefsBackupController ()
- (void)mtPresentAlertWithTitle:(NSString *)title message:(NSString *)message;
@end

@implementation MTPrefsBackupController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"配置备份";
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *specs = [NSMutableArray array];

    PSSpecifier *intro = [PSSpecifier groupSpecifierWithName:@"备份内容"];
    [intro setProperty:@"备份包含全部功能配置：键盘、剪切板、截图、快捷启动与共享资源（自定义动作、面板）。文件保存在本机，可导出分享；仅保留最近 10 份，更早的自动淘汰。"
                forKey:@"footerText"];
    [specs addObject:intro];

    PSSpecifier *create = [PSSpecifier preferenceSpecifierNamed:@"立即备份"
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                            cell:PSButtonCell
                                                           edit:nil];
    create.identifier = @"global-config-backup-create";
    create->action = @selector(createBackup:);
    [specs addObject:create];

    NSArray<MTConfigBackupItem *> *backups = [MTConfigBackupService availableBackups];
    PSSpecifier *listGroup = [PSSpecifier groupSpecifierWithName:
        [NSString stringWithFormat:@"已有备份（%lu/%lu）",
         (unsigned long)backups.count, (unsigned long)MTConfigBackupRetentionLimit]];
    [listGroup setProperty:backups.count
        ? @"点按备份可导出或删除。"
        : @"还没有备份。点击上方「立即备份」创建第一份。"
                     forKey:@"footerText"];
    [specs addObject:listGroup];

    for (MTConfigBackupItem *item in backups) {
        PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:MTBackupFormatTime(item.createdAt)
                                                          target:self
                                                             set:nil
                                                             get:@selector(backupSummary:)
                                                          detail:nil
                                                             cell:PSTitleValueCell
                                                            edit:nil];
        row.identifier = [@"backup-" stringByAppendingString:item.path];
        row->action = @selector(showBackupActions:);
        [row setProperty:item.path forKey:@"backupPath"];
        [specs addObject:row];
    }

    _specifiers = specs;
    return _specifiers;
}

#pragma mark - Actions

- (void)createBackup:(PSSpecifier *)specifier {
    NSError *error = nil;
    MTConfigBackupItem *item = [MTConfigBackupService createBackupWithError:&error];
    if (!item) {
        [self mtPresentAlertWithTitle:@"备份失败" message:error.localizedDescription];
        return;
    }
    [self reloadSpecifiers];
    [self mtPresentAlertWithTitle:@"备份成功"
                         message:[NSString stringWithFormat:@"已备份 %lu 项配置（%@）。",
                                  (unsigned long)item.domainCount, MTBackupFormatTime(item.createdAt)]];
}

- (void)showBackupActions:(PSSpecifier *)specifier {
    NSString *path = [specifier propertyForKey:@"backupPath"];
    if (!path.length) return;
    MTConfigBackupItem *item = [self mtItemForPath:path];
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:item ? MTBackupFormatTime(item.createdAt) : path.lastPathComponent
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction
        actionWithTitle:@"导出到文件…"
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) { [self mtExportBackupAtPath:path]; }]];
    [sheet addAction:[UIAlertAction
        actionWithTitle:@"删除备份"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) { [self mtConfirmDeleteBackupAtPath:path]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    // iPad 上 action sheet 必须锚定源视图，否则直接崩溃。
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(0.f, 0.f, 1.f, 1.f);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)mtExportBackupAtPath:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self mtPresentAlertWithTitle:@"导出失败" message:@"备份文件已不存在。"];
        [self reloadSpecifiers];
        return;
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    // iOS 14+ 导出 API（asCopy=YES：交出副本，保留本机备份）。
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)mtConfirmDeleteBackupAtPath:(NSString *)path {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"删除备份？"
                         message:@"删除后该备份文件无法恢复。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction
        actionWithTitle:@"删除"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    NSError *error = nil;
                    if (![MTConfigBackupService deleteBackupAtPath:path error:&error]) {
                        [self mtPresentAlertWithTitle:@"删除失败" message:error.localizedDescription];
                        return;
                    }
                    [self reloadSpecifiers];
                }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Cell getter

- (NSString *)backupSummary:(PSSpecifier *)specifier {
    MTConfigBackupItem *item = [self mtItemForPath:[specifier propertyForKey:@"backupPath"]];
    return item ? MTBackupFormatSummary(item) : @"";
}

#pragma mark - Helpers

- (MTConfigBackupItem *)mtItemForPath:(NSString *)path {
    if (!path.length) return nil;
    for (MTConfigBackupItem *item in [MTConfigBackupService availableBackups]) {
        if ([item.path isEqualToString:path]) return item;
    }
    return nil;
}

- (void)mtPresentAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    // 导出模式：文件已交出去，无需额外处理。
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
}

@end
