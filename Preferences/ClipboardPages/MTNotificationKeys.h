//
//  MTNotificationKeys.h
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import <Foundation/Foundation.h>

static NSString *const kMTNotificationKeyCoreShow = @"com.lindo.metis.clipboard.core.show";
static NSString *const kMTLegacyNotificationKeyCoreShow = @"dev.traurige.mt.core.show";
static NSString *const kMTNotificationKeyCoreHide = @"com.lindo.metis.clipboard.core.hide";
static NSString *const kMTLegacyNotificationKeyCoreHide = @"dev.traurige.mt.core.hide";
static NSString *const kMTNotificationKeyCoreToggle = @"com.lindo.metis.clipboard.core.toggle";
static NSString *const kMTNotificationKeyCoreReload = @"com.lindo.metis.clipboard.core.reload";
static NSString *const kMTNotificationKeyCoreCheckpointHistory = @"com.lindo.metis.clipboard.core.checkpoint-history";
static NSString *const kMTNotificationKeyCorePrepareMaintenance = @"com.lindo.metis.clipboard.core.prepare-maintenance";
static NSString *const kMTNotificationKeyCoreResetThumbnailMemoryCache =
    @"com.lindo.metis.clipboard.core.reset-thumbnail-memory-cache";
static NSString *const kMTNotificationKeyCoreClearFavorites = @"com.lindo.metis.clipboard.core.clear-favorites";
static NSString *const kMTNotificationKeyCoreClearHistory = @"com.lindo.metis.clipboard.core.clear-history";
static NSString *const kMTNotificationKeyHelperPaste = @"com.lindo.metis.clipboard.helper.paste";
static NSString *const kMTNotificationKeyHelperRestoreFocus = @"com.lindo.metis.clipboard.helper.restore-focus";
static NSString *const kMTNotificationKeyPreferencesReload = @"com.lindo.metis.clipboard.preferences.reload";
static NSString *const kMTNotificationKeyPreferencesHeightReload = @"com.lindo.metis.clipboard.preferences.height.reload";
static NSString *const kMTNotificationKeyExternalImportRequiresRestart =
    @"com.lindo.metis.clipboard.preferences.external-import-requires-restart";
static NSString *const kMTNotificationUserInfoKeyExternalImportSucceeded = @"succeeded";
static NSString *const kMTNotificationUserInfoKeyExternalImportSource = @"source";
static NSString *const kMTExternalImportSourceCopyLog = @"CopyLog";
static NSString *const kMTExternalImportSourceCopyVault = @"CopyVault";
static NSString *const kMTNotificationKeyPasteWillStart = @"com.lindo.metis.clipboard.paste.willstart";
static NSString *const kMTNotificationKeyPasteFeedback = @"com.lindo.metis.clipboard.paste.feedback";
