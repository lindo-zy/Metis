//
//  MTPreferenceKeys.h
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, ActivationMethod) {
    kActivationMethodPredictionBar = 1 << 0,
    kActivationMethodDictationKey = 1 << 1,
    kActivationMethodInputSwitcher = 1 << 2,
    kActivationMethodCalloutBar = 1 << 3,
    kActivationMethodSwipeUp = 1 << 4,
    kActivationMethodExternalKeyboard = 1 << 5
};

typedef NS_ENUM(NSUInteger, MTAutomaticPasteMode) {
    kMTAutomaticPasteModeClassic = 0,
    kMTAutomaticPasteModeSimulated = 1,
    kMTAutomaticPasteModeAutomatic = 2
};

typedef NS_ENUM(NSUInteger, MTAutomaticPromotionMode) {
    kMTAutomaticPromotionModeOff = 0,
    kMTAutomaticPromotionModeHistoryOnly = 1,
    kMTAutomaticPromotionModeAlways = 2
};

typedef NS_ENUM(NSUInteger, MTGestureRecognizerMode) {
    kMTGestureRecognizerModeClassic = 0,
    kMTGestureRecognizerModeSystem = 1
};

typedef NS_ENUM(NSUInteger, MTInitialViewMode) {
    kMTInitialViewModeHistory = 0,
    kMTInitialViewModeFavorites = 1,
    kMTInitialViewModePreviousSelection = 2
};

typedef NS_ENUM(NSUInteger, MTClearButtonMode) {
    kMTClearButtonModeOff = 0,
    kMTClearButtonModeHistoryOnly = 1,
    kMTClearButtonModeAlways = 2
};

typedef NS_ENUM(NSUInteger, MTItemDetailsMode) {
    kMTItemDetailsModeOff = 0,
    kMTItemDetailsModeImagesOnly = 1,
    kMTItemDetailsModeAll = 2
};

typedef NS_ENUM(NSUInteger, MTOverlayWindowLevelMode) {
    kMTOverlayWindowLevelModeCustom = 0,
    kMTOverlayWindowLevelModeMaximum = 1
};

// Clipboard（Mt）细节配置域：Metis 自有域，不读取、不迁移 MTX
// 旧插件域（com.lindo.kayoko.preferences）的任何旧值；模块启停权威在
// com.lindo.metis（MTModuleGate），本域只承载细节参数。
static NSString *const kMTClipboardPreferencesIdentifier = @"com.lindo.metis.clipboard";

static NSString *const kMTPreferenceKeyEnabled = @"Enabled";
static NSString *const kMTPreferenceKeyMaximumHistoryAmount = @"MaximumHistoryAmount";
static NSString *const kMTPreferenceKeySaveText = @"SaveText";
static NSString *const kMTPreferenceKeySaveImages = @"SaveImages";
static NSString *const kMTPreferenceKeySwipeToSelectWords = @"SwipeToSelectWords";
static NSString *const kMTPreferenceKeyActivationMethod = @"ActivationMethod";
static NSString *const kMTPreferenceKeyPrivacyMode = @"PrivacyMode";
static NSString *const kMTPreferenceKeyFloatingPreview = @"FloatingPreview";
static NSString *const kMTPreferenceKeyFloatingPreviewDoubleTapAction = @"FloatingPreviewDoubleTapAction";
static NSString *const kMTPreferenceKeyFloatingPreviewCountdownRing = @"FloatingPreviewCountdownRing";
static NSString *const kMTPreferenceKeyFloatingPreviewSize = @"FloatingPreviewSize";
static NSString *const kMTPreferenceKeyFloatingPreviewDuration = @"FloatingPreviewDuration";
static NSString *const kMTPreferenceKeyFloatingPreviewColor = @"FloatingPreviewColor";
static NSString *const kMTPreferenceKeyFloatingPreviewDockedRight = @"FloatingPreviewDockedRight";
static NSString *const kMTPreferenceKeyFloatingPreviewVerticalPosition = @"FloatingPreviewVerticalPosition";
static NSString *const kMTPreferenceKeyFloatingPanelScale = @"FloatingPanelScale";
static NSString *const kMTPreferenceKeyFloatingPanelColor = @"FloatingPanelColor";
static NSString *const kMTPreferenceKeyImageDoubleTapActionURL = @"ImageDoubleTapActionURL";
static NSString *const kMTPreferenceKeyGestureRecognizerMode = @"GestureRecognizerMode";
static NSString *const kMTPreferenceKeyAutomaticallyPaste = @"AutomaticallyPaste";
static NSString *const kMTPreferenceKeyAutomaticPasteMode = @"AutomaticPasteMode";
static NSString *const kMTPreferenceKeyAutomaticPromotionMode = @"AutomaticPromotionMode";
static NSString *const kMTPreferenceKeyInitialViewMode = @"InitialViewMode";
static NSString *const kMTPreferenceKeyAlwaysScrollToTop = @"AlwaysScrollToTop";
static NSString *const kMTPreferenceKeyClearButtonMode = @"ClearButtonMode";
static NSString *const kMTPreferenceKeyDismissOnOutsideTouch = @"DismissOnOutsideTouch";
static NSString *const kMTPreferenceKeyDisablePasteTips = @"DisablePasteTips";
static NSString *const kMTPreferenceKeyIgnoreRemoteReplication = @"IgnoreRemoteReplication";
static NSString *const kMTPreferenceKeyApplicationBlacklist = @"ApplicationBlacklist";
static NSString *const kMTPreferenceKeyPlaySoundEffects = @"PlaySoundEffects";
static NSString *const kMTPreferenceKeyPlayHapticFeedback = @"PlayHapticFeedback";
static NSString *const kMTPreferenceKeyPreviewLineCount = @"PreviewLineCount";
static NSString *const kMTPreferenceKeyItemDetailsMode = @"ItemDetailsMode";
static NSString *const kMTPreferenceKeyHeightInPoints = @"HeightInPoints";
static NSString *const kMTPreferenceKeyOverlayWindowLevelMode = @"OverlayWindowLevelMode";
static NSString *const kMTPreferenceKeyOverlayWindowLevel = @"OverlayWindowLevel";
static NSString *const kMTPreferenceKeyFavoritesFilterPanelVisible = @"FavoritesFilterPanelVisible";
static NSString *const kMTPreferenceKeyFavoritesFilterShowsCategories = @"FavoritesFilterShowsCategories";
static NSString *const kMTPreferenceKeyFavoritesFilterShowsTags = @"FavoritesFilterShowsTags";
static NSString *const kMTPreferenceKeyFavoritesFilterShowsApps = @"FavoritesFilterShowsApps";
static NSString *const kMTPreferenceKeyGalleryModeEnabled = @"GalleryModeEnabled";
static NSString *const kMTPreferenceKeyClipboardGalleryModeEnabled = @"ClipboardGalleryModeEnabled";
static NSString *const kMTPreferenceKeyFavoritesGalleryModeEnabled = @"FavoritesGalleryModeEnabled";

static BOOL const kMTPreferenceKeyEnabledDefaultValue = YES;
static NSUInteger const kMTPreferenceKeyMaximumHistoryAmountDefaultValue = 200;
static BOOL const kMTPreferenceKeySaveTextDefaultValue = YES;
static BOOL const kMTPreferenceKeySaveImagesDefaultValue = YES;
static BOOL const kMTPreferenceKeySwipeToSelectWordsDefaultValue = YES;
static ActivationMethod const kMTPreferenceKeyActivationMethodDefaultValue =
    kActivationMethodDictationKey | kActivationMethodInputSwitcher | kActivationMethodExternalKeyboard;
static BOOL const kMTPreferenceKeyPrivacyModeDefaultValue = NO;
static BOOL const kMTPreferenceKeyFloatingPreviewDefaultValue = NO;
static BOOL const kMTPreferenceKeyFloatingPreviewDoubleTapActionDefaultValue = NO;
static BOOL const kMTPreferenceKeyFloatingPreviewCountdownRingDefaultValue = NO;
static CGFloat const kMTPreferenceKeyFloatingPreviewSizeDefaultValue = 40.0;
static CGFloat const kMTPreferenceKeyFloatingPreviewSizeMinimumValue = 25.0;
static CGFloat const kMTPreferenceKeyFloatingPreviewSizeMaximumValue = 100.0;
static CGFloat const kMTPreferenceKeyFloatingPreviewDurationDefaultValue = 5.0;
static CGFloat const kMTPreferenceKeyFloatingPreviewDurationMinimumValue = 3.0;
static CGFloat const kMTPreferenceKeyFloatingPreviewDurationMaximumValue = 10.0;
static NSString *const kMTPreferenceKeyFloatingPreviewColorDefaultValue = @"#7FA6F8FF";
static BOOL const kMTPreferenceKeyFloatingPreviewDockedRightDefaultValue = YES;
static CGFloat const kMTPreferenceKeyFloatingPreviewVerticalPositionDefaultValue = 0.5;
static CGFloat const kMTPreferenceKeyFloatingPanelScaleDefaultValue = 1.0;
static CGFloat const kMTPreferenceKeyFloatingPanelScaleMinimumValue = 0.50;
static CGFloat const kMTPreferenceKeyFloatingPanelScaleMaximumValue = 1.20;
static NSString *const kMTPreferenceKeyFloatingPanelColorDefaultValue = @"#30BFBFFF";
static NSString *const kMTPreferenceKeyImageDoubleTapActionURLDefaultValue = @"";
static MTGestureRecognizerMode const kMTPreferenceKeyGestureRecognizerModeDefaultValue =
    kMTGestureRecognizerModeClassic;
static BOOL const kMTPreferenceKeyAutomaticallyPasteDefaultValue = YES;
static MTAutomaticPasteMode const kMTPreferenceKeyAutomaticPasteModeDefaultValue =
    kMTAutomaticPasteModeClassic;
static MTAutomaticPromotionMode const kMTPreferenceKeyAutomaticPromotionModeDefaultValue =
    kMTAutomaticPromotionModeHistoryOnly;
static MTInitialViewMode const kMTPreferenceKeyInitialViewModeDefaultValue =
    kMTInitialViewModePreviousSelection;
static BOOL const kMTPreferenceKeyAlwaysScrollToTopDefaultValue = NO;
static MTClearButtonMode const kMTPreferenceKeyClearButtonModeDefaultValue = kMTClearButtonModeHistoryOnly;
static BOOL const kMTPreferenceKeyDismissOnOutsideTouchDefaultValue = YES;
static BOOL const kMTPreferenceKeyDisablePasteTipsDefaultValue = NO;
static BOOL const kMTPreferenceKeyIgnoreRemoteReplicationDefaultValue = NO;
static BOOL const kMTPreferenceKeyPlaySoundEffectsDefaultValue = YES;
static BOOL const kMTPreferenceKeyPlayHapticFeedbackDefaultValue = YES;
static NSUInteger const kMTPreferenceKeyPreviewLineCountDefaultValue = 1;
static MTItemDetailsMode const kMTPreferenceKeyItemDetailsModeDefaultValue = kMTItemDetailsModeImagesOnly;
static CGFloat const kMTPreferenceKeyHeightInPointsDefaultValue = 420;
static MTOverlayWindowLevelMode const kMTPreferenceKeyOverlayWindowLevelModeDefaultValue =
    kMTOverlayWindowLevelModeCustom;
static CGFloat const kMTPreferenceKeyOverlayWindowLevelDefaultValue = 998;
static CGFloat const kMTPreferenceKeyOverlayWindowLevelMinimumValue = 10;
static CGFloat const kMTPreferenceKeyOverlayWindowLevelMaximumValue = 2000;

static BOOL const kMTPreferenceKeyFavoritesFilterPanelVisibleDefaultValue = YES;
static BOOL const kMTPreferenceKeyFavoritesFilterShowsCategoriesDefaultValue = YES;
static BOOL const kMTPreferenceKeyFavoritesFilterShowsTagsDefaultValue = NO;
static BOOL const kMTPreferenceKeyFavoritesFilterShowsAppsDefaultValue = NO;
static BOOL const kMTPreferenceKeyGalleryModeEnabledDefaultValue = NO;
static BOOL const kMTPreferenceKeyClipboardGalleryModeEnabledDefaultValue = NO;
static BOOL const kMTPreferenceKeyFavoritesGalleryModeEnabledDefaultValue = NO;
