// MTPrefsRestoreController —— 配置恢复页（全局「配置维护」入口）。
// 列出全部备份（含从文件导入的），点按后二次确认并全量恢复；
// 恢复前由 MTConfigBackupService 自动创建安全网备份。
#import <Preferences/Preferences.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "MTPrefsRestoreController.h"
#import "MTConfigBackupService.h"

static NSString *MTRestoreFormatTime(NSDate *date) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return [formatter stringFromDate:date];
}

static NSString *MTRestoreFormatSummary(MTConfigBackupItem *item) {
    NSString *scope = item.includesSharedResources ? @"，含共享资源" : @"";
    return [NSString stringWithFormat:@"%lu 项配置%@",
            (unsigned long)item.domainCount, scope];
}

@interface MTPrefsRestoreController ()
- (void)mtPresentAlertWithTitle:(NSString *)title message:(NSString *)message;
@end

@implementation MTPrefsRestoreController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"配置恢复";
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *specs = [NSMutableArray array];

    PSSpecifier *intro = [PSSpecifier groupSpecifierWithName:@"恢复说明"];
    [intro setProperty:@"恢复会用所选备份覆盖当前全部配置（含共享资源），恢复前会自动为当前配置创建一份安全网备份。恢复后各功能立即生效，无需重启。"
                forKey:@"footerText"];
    [specs addObject:intro];

    PSSpecifier *importRow = [PSSpecifier preferenceSpecifierNamed:@"从文件导入备份…"
                                                            target:self
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                               cell:PSButtonCell
                                                              edit:nil];
    importRow.identifier = @"global-config-restore-import";
    importRow->action = @selector(importBackup:);
    [specs addObject:importRow];

    NSArray<MTConfigBackupItem *> *backups = [MTConfigBackupService availableBackups];
    PSSpecifier *listGroup = [PSSpecifier groupSpecifierWithName:
        [NSString stringWithFormat:@"选择备份恢复（%lu）", (unsigned long)backups.count]];
    if (!backups.count) {
        [listGroup setProperty:@"还没有可恢复的备份。请先在「配置备份」中创建，或从文件导入。"
                       forKey:@"footerText"];
    }
    [specs addObject:listGroup];

    for (MTConfigBackupItem *item in backups) {
        PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:MTRestoreFormatTime(item.createdAt)
                                                          target:self
                                                             set:nil
                                                             get:@selector(backupSummary:)
                                                          detail:nil
                                                             cell:PSTitleValueCell
                                                            edit:nil];
        row.identifier = [@"backup-" stringByAppendingString:item.path];
        row->action = @selector(confirmRestore:);
        [row setProperty:item.path forKey:@"backupPath"];
        [specs addObject:row];
    }

    _specifiers = specs;
    return _specifiers;
}

#pragma mark - Actions

- (void)importBackup:(PSSpecifier *)specifier {
    // iOS 14+ 打开内容 API（asCopy=YES 即导入语义：拷贝副本到本进程可读位置）。
    UTType *dataType = [UTType typeWithIdentifier:@"public.data"];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[dataType]
                                                                    asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)confirmRestore:(PSSpecifier *)specifier {
    NSString *path = [specifier propertyForKey:@"backupPath"];
    if (!path.length) return;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"恢复配置？"
                         message:@"将用所选备份覆盖当前全部配置。当前配置会先自动备份为安全网。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction
        actionWithTitle:@"恢复"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) { [self mtRestoreBackupAtPath:path]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)mtRestoreBackupAtPath:(NSString *)path {
    NSError *error = nil;
    if (![MTConfigBackupService restoreBackupAtPath:path error:&error]) {
        [self mtPresentAlertWithTitle:@"恢复失败" message:error.localizedDescription];
        return;
    }
    [self reloadSpecifiers];
    [self mtPresentAlertWithTitle:@"恢复完成"
                         message:@"全部配置已恢复到备份时的状态；恢复前的配置已自动保存为安全网备份。"];
}

#pragma mark - Cell getter

- (NSString *)backupSummary:(PSSpecifier *)specifier {
    MTConfigBackupItem *item = [self mtItemForPath:[specifier propertyForKey:@"backupPath"]];
    return item ? MTRestoreFormatSummary(item) : @"";
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *source = urls.firstObject;
    if (!source) return;
    // 导入文件在沙盒外临时副本：需显式申请安全作用域访问后再读取。
    [source startAccessingSecurityScopedResource];
    NSError *error = nil;
    NSString *imported = [MTConfigBackupService importBackupFromPath:source.path error:&error];
    [source stopAccessingSecurityScopedResource];
    if (!imported) {
        [self mtPresentAlertWithTitle:@"导入失败" message:error.localizedDescription];
        return;
    }
    [self reloadSpecifiers];
    [self mtPresentAlertWithTitle:@"导入成功"
                         message:@"备份已加入列表，点按即可恢复。"];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
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

@end
