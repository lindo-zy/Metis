//
//  KayokoNotificationKeys.h
//  Kayoko
//
//  Created by Alexandra Aurora Göttlicher
//

#import <Foundation/Foundation.h>

static NSString *const kKayokoNotificationKeyCoreShow = @"com.lindo.kayoko.core.show";
static NSString *const kKayokoLegacyNotificationKeyCoreShow = @"dev.traurige.kayoko.core.show";
static NSString *const kKayokoNotificationKeyCoreHide = @"com.lindo.kayoko.core.hide";
static NSString *const kKayokoLegacyNotificationKeyCoreHide = @"dev.traurige.kayoko.core.hide";
static NSString *const kKayokoNotificationKeyCoreToggle = @"com.lindo.kayoko.core.toggle";
static NSString *const kKayokoNotificationKeyCoreReload = @"com.lindo.kayoko.core.reload";
static NSString *const kKayokoNotificationKeyCoreCheckpointHistory = @"com.lindo.kayoko.core.checkpoint-history";
static NSString *const kKayokoNotificationKeyCorePrepareMaintenance = @"com.lindo.kayoko.core.prepare-maintenance";
static NSString *const kKayokoNotificationKeyCoreResetThumbnailMemoryCache =
    @"com.lindo.kayoko.core.reset-thumbnail-memory-cache";
static NSString *const kKayokoNotificationKeyCoreClearFavorites = @"com.lindo.kayoko.core.clear-favorites";
static NSString *const kKayokoNotificationKeyCoreClearHistory = @"com.lindo.kayoko.core.clear-history";
static NSString *const kKayokoNotificationKeyHelperPaste = @"com.lindo.kayoko.helper.paste";
static NSString *const kKayokoNotificationKeyHelperRestoreFocus = @"com.lindo.kayoko.helper.restore-focus";
static NSString *const kKayokoNotificationKeyPreferencesReload = @"com.lindo.kayoko.preferences.reload";
static NSString *const kKayokoNotificationKeyPreferencesHeightReload = @"com.lindo.kayoko.preferences.height.reload";
static NSString *const kKayokoNotificationKeyExternalImportRequiresRestart =
    @"com.lindo.kayoko.preferences.external-import-requires-restart";
static NSString *const kKayokoNotificationUserInfoKeyExternalImportSucceeded = @"succeeded";
static NSString *const kKayokoNotificationUserInfoKeyExternalImportSource = @"source";
static NSString *const kKayokoExternalImportSourceCopyLog = @"CopyLog";
static NSString *const kKayokoExternalImportSourceCopyVault = @"CopyVault";
static NSString *const kKayokoNotificationKeyPasteWillStart = @"com.lindo.kayoko.paste.willstart";
static NSString *const kKayokoNotificationKeyPasteFeedback = @"com.lindo.kayoko.paste.feedback";
