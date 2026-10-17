//
//  MTNotificationKeys.h
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import <Foundation/Foundation.h>

static NSString *const kMTNotificationKeyCoreShow = @"com.lindo.kayoko.core.show";
static NSString *const kMTLegacyNotificationKeyCoreShow = @"dev.traurige.mt.core.show";
static NSString *const kMTNotificationKeyCoreHide = @"com.lindo.kayoko.core.hide";
static NSString *const kMTLegacyNotificationKeyCoreHide = @"dev.traurige.mt.core.hide";
static NSString *const kMTNotificationKeyCoreToggle = @"com.lindo.kayoko.core.toggle";
static NSString *const kMTNotificationKeyCoreReload = @"com.lindo.kayoko.core.reload";
static NSString *const kMTNotificationKeyCoreCheckpointHistory = @"com.lindo.kayoko.core.checkpoint-history";
static NSString *const kMTNotificationKeyCorePrepareMaintenance = @"com.lindo.kayoko.core.prepare-maintenance";
static NSString *const kMTNotificationKeyCoreResetThumbnailMemoryCache =
    @"com.lindo.kayoko.core.reset-thumbnail-memory-cache";
static NSString *const kMTNotificationKeyCoreClearFavorites = @"com.lindo.kayoko.core.clear-favorites";
static NSString *const kMTNotificationKeyCoreClearHistory = @"com.lindo.kayoko.core.clear-history";
static NSString *const kMTNotificationKeyHelperPaste = @"com.lindo.kayoko.helper.paste";
static NSString *const kMTNotificationKeyHelperRestoreFocus = @"com.lindo.kayoko.helper.restore-focus";
static NSString *const kMTNotificationKeyPreferencesReload = @"com.lindo.kayoko.preferences.reload";
static NSString *const kMTNotificationKeyPreferencesHeightReload = @"com.lindo.kayoko.preferences.height.reload";
static NSString *const kMTNotificationKeyExternalImportRequiresRestart =
    @"com.lindo.kayoko.preferences.external-import-requires-restart";
static NSString *const kMTNotificationUserInfoKeyExternalImportSucceeded = @"succeeded";
static NSString *const kMTNotificationUserInfoKeyExternalImportSource = @"source";
static NSString *const kMTExternalImportSourceCopyLog = @"CopyLog";
static NSString *const kMTExternalImportSourceCopyVault = @"CopyVault";
static NSString *const kMTNotificationKeyPasteWillStart = @"com.lindo.kayoko.paste.willstart";
static NSString *const kMTNotificationKeyPasteFeedback = @"com.lindo.kayoko.paste.feedback";
