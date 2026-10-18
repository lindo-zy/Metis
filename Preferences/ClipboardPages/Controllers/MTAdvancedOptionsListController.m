//
//  MTAdvancedOptionsListController.m
//  Mt
//

#import "MTAdvancedOptionsListController.h"
#import "MTNotificationKeys.h"
#import "MTPreferenceKeys.h"
#import "MTRespringControllerSupport.h"

#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <roothide.h>

static NSString *const kMTDataDirectoryPath = @"/var/mobile/Library/com.lindo.metis.clipboard";

@interface NSTask : NSObject
- (void)setLaunchPath:(NSString *)launchPath;
- (void)setArguments:(NSArray<NSString *> *)arguments;
- (void)setStandardOutput:(id)standardOutput;
- (void)setStandardError:(id)standardError;
- (void)launch;
- (void)waitUntilExit;
- (int)terminationStatus;
@end

@implementation MTAdvancedOptionsListController

- (NSArray<PSSpecifier *> *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"AdvancedOptions" target:self];
    }

    return _specifiers;
}

#pragma mark - Preference Writing

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:kMTPreferenceKeyGestureRecognizerMode]) {
        [self promptToRespring];
    }
}

#pragma mark - Prompts

- (void)resetPrompt {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];

    UIAlertController *resetAlert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"Metis" value:nil table:@"Root"]
                         message:[bundle localizedStringForKey:@"Are you sure you want to reset your "
                                                               @"preferences?"
                                                         value:nil
                                                         table:@"AdvancedOptions"]
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *resetAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Reset"
                                                                                        value:nil
                                                                                        table:@"AdvancedOptions"]
                                                          style:UIAlertActionStyleDestructive
                                                        handler:^(UIAlertAction *action) {
                                                          [self resetPreferences];
                                                        }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"AdvancedOptions"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [resetAlert addAction:resetAction];
    [resetAlert addAction:cancelAction];

    [self presentViewController:resetAlert animated:YES completion:nil];
}

- (void)clearFavoritesPrompt {
    [self presentClearConfirmationWithMessageKey:
              @"Are you sure you want to clear all favorite items? This action cannot be undone."
                                  actionTitleKey:@"Clear Favorites"
                                notificationName:kMTNotificationKeyCoreClearFavorites];
}

- (void)clearHistoryPrompt {
    [self presentClearConfirmationWithMessageKey:
              @"Are you sure you want to clear all history items? This action cannot be undone."
                                  actionTitleKey:@"Clear History"
                                notificationName:kMTNotificationKeyCoreClearHistory];
}

- (void)resetThumbnailCachePrompt {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"Metis" value:nil table:@"Root"]
                         message:[bundle localizedStringForKey:
                                             @"Are you sure you want to reset the thumbnail cache? Thumbnails will "
                                             @"be regenerated as needed."
                                                         value:nil
                                                         table:@"AdvancedOptions"]
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *resetAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Reset Thumbnail Cache"
                                                                                        value:nil
                                                                                        table:@"AdvancedOptions"]
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
                                                          (void)action;
                                                          [self resetThumbnailCache];
                                                        }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"AdvancedOptions"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alert addAction:resetAction];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentClearConfirmationWithMessageKey:(NSString *)messageKey
                                actionTitleKey:(NSString *)actionTitleKey
                              notificationName:(NSString *)notificationName {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];

    UIAlertController *clearAlert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"Metis" value:nil table:@"Root"]
                         message:[bundle localizedStringForKey:messageKey value:nil table:@"AdvancedOptions"]
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *clearAction =
        [UIAlertAction actionWithTitle:[bundle localizedStringForKey:actionTitleKey value:nil table:@"AdvancedOptions"]
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *action) {
                                 CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                                      (CFStringRef)notificationName, nil, nil, YES);
                               }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"AdvancedOptions"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [clearAlert addAction:clearAction];
    [clearAlert addAction:cancelAction];

    [self presentViewController:clearAlert animated:YES completion:nil];
}

#pragma mark - Data Directory

- (void)checkDataDirectory {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kMTNotificationKeyCoreCheckpointHistory, nil, nil, YES);

    NSURL *filzaURL = [self filzaURLForDataDirectoryPath:[self dataDirectoryPath]];
    if (!filzaURL) {
        [self presentDataDirectoryPathAlert];
        return;
    }

    [[UIApplication sharedApplication] openURL:filzaURL
                                       options:@{}
                             completionHandler:^(BOOL success) {
                               if (!success) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                     [self presentDataDirectoryPathAlert];
                                   });
                               }
                             }];
}

- (NSString *)dataDirectoryPath {
    return jbroot(kMTDataDirectoryPath);
}

- (NSURL *)filzaURLForDataDirectoryPath:(NSString *)dataDirectoryPath {
    NSString *encodedPath = [dataDirectoryPath
        stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    NSString *pathComponent = encodedPath ?: dataDirectoryPath;
    NSString *URLString = [@"filza://view" stringByAppendingString:pathComponent];
    return [NSURL URLWithString:URLString];
}

- (void)presentDataDirectoryPathAlert {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *dataDirectoryPath = [self dataDirectoryPath];
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:@"Unable to Open Filza"
                                                                            value:nil
                                                                            table:@"AdvancedOptions"]
                                            message:dataDirectoryPath
                                     preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"AdvancedOptions"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Copy Path"
                                                                                       value:nil
                                                                                       table:@"AdvancedOptions"]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
                                                         [UIPasteboard generalPasteboard].string = dataDirectoryPath;
                                                       }];

    [alert addAction:cancelAction];
    [alert addAction:copyAction];
    [self presentViewController:alert animated:YES completion:nil];
}


#pragma mark - Maintenance Actions

- (void)resetThumbnailCache {
    NSString *updaterPath = [self mtUpdaterPath];
    if ([updaterPath length] == 0) {
        NSLog(@"Mt: Unable to reset thumbnail cache because mt_updater is unavailable");
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      @try {
          NSTask *task = [[NSTask alloc] init];
          [task setLaunchPath:updaterPath];
          [task setArguments:@[ @"reset-thumbnail-cache" ]];
          [task setStandardOutput:[NSPipe pipe]];
          [task setStandardError:[NSPipe pipe]];
          [task launch];
          [task waitUntilExit];
      } @catch (NSException *exception) {
          NSLog(@"Mt: Unable to launch thumbnail cache reset: %@", exception);
      }
    });
}

- (NSString *)mtUpdaterPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *candidatePaths = @[
        jbroot(@"/usr/local/libexec/mt_updater"), @"/var/jb/usr/local/libexec/mt_updater",
        @"/usr/local/libexec/mt_updater"
    ];
    for (NSString *path in candidatePaths) {
        if ([fileManager isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

- (void)resetPreferences {
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
    for (NSString *key in [userDefaults dictionaryRepresentation]) {
        [userDefaults removeObjectForKey:key];
    }

    [self reloadSpecifiers];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kMTNotificationKeyPreferencesReload, nil, nil, YES);
}

#pragma mark - UITableViewDataSource

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *key = [specifier propertyForKey:@"cell"];
    if ([key isEqualToString:@"PSButtonCell"]) {
        UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
        NSNumber *isDestructiveValue = [specifier propertyForKey:@"isDestructive"];
        BOOL isDestructive = [isDestructiveValue boolValue];
        cell.textLabel.textColor = isDestructive ? [UIColor systemRedColor] : [UIColor systemBlueColor];
        cell.textLabel.highlightedTextColor = isDestructive ? [UIColor systemRedColor] : [UIColor systemBlueColor];
        return cell;
    }

    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

@end
