//
//  KayokoPreferenceKeys.h
//  Kayoko
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

typedef NS_ENUM(NSUInteger, KayokoAutomaticPasteMode) {
    kKayokoAutomaticPasteModeClassic = 0,
    kKayokoAutomaticPasteModeSimulated = 1,
    kKayokoAutomaticPasteModeAutomatic = 2
};

typedef NS_ENUM(NSUInteger, KayokoAutomaticPromotionMode) {
    kKayokoAutomaticPromotionModeOff = 0,
    kKayokoAutomaticPromotionModeHistoryOnly = 1,
    kKayokoAutomaticPromotionModeAlways = 2
};

typedef NS_ENUM(NSUInteger, KayokoGestureRecognizerMode) {
    kKayokoGestureRecognizerModeClassic = 0,
    kKayokoGestureRecognizerModeSystem = 1
};

typedef NS_ENUM(NSUInteger, KayokoInitialViewMode) {
    kKayokoInitialViewModeHistory = 0,
    kKayokoInitialViewModeFavorites = 1,
    kKayokoInitialViewModePreviousSelection = 2
};

typedef NS_ENUM(NSUInteger, KayokoClearButtonMode) {
    kKayokoClearButtonModeOff = 0,
    kKayokoClearButtonModeHistoryOnly = 1,
    kKayokoClearButtonModeAlways = 2
};

typedef NS_ENUM(NSUInteger, KayokoItemDetailsMode) {
    kKayokoItemDetailsModeOff = 0,
    kKayokoItemDetailsModeImagesOnly = 1,
    kKayokoItemDetailsModeAll = 2
};

typedef NS_ENUM(NSUInteger, KayokoOverlayWindowLevelMode) {
    kKayokoOverlayWindowLevelModeCustom = 0,
    kKayokoOverlayWindowLevelModeMaximum = 1
};

static NSString *const kKayokoPreferencesIdentifier = @"com.lindo.kayoko.preferences";

static NSString *const kKayokoPreferenceKeyEnabled = @"Enabled";
static NSString *const kKayokoPreferenceKeyMaximumHistoryAmount = @"MaximumHistoryAmount";
static NSString *const kKayokoPreferenceKeySaveText = @"SaveText";
static NSString *const kKayokoPreferenceKeySaveImages = @"SaveImages";
static NSString *const kKayokoPreferenceKeySwipeToSelectWords = @"SwipeToSelectWords";
static NSString *const kKayokoPreferenceKeyActivationMethod = @"ActivationMethod";
static NSString *const kKayokoPreferenceKeyPrivacyMode = @"PrivacyMode";
static NSString *const kKayokoPreferenceKeyFloatingPreview = @"FloatingPreview";
static NSString *const kKayokoPreferenceKeyFloatingPreviewDoubleTapAction = @"FloatingPreviewDoubleTapAction";
static NSString *const kKayokoPreferenceKeyFloatingPreviewCountdownRing = @"FloatingPreviewCountdownRing";
static NSString *const kKayokoPreferenceKeyFloatingPreviewSize = @"FloatingPreviewSize";
static NSString *const kKayokoPreferenceKeyFloatingPreviewDuration = @"FloatingPreviewDuration";
static NSString *const kKayokoPreferenceKeyFloatingPreviewColor = @"FloatingPreviewColor";
static NSString *const kKayokoPreferenceKeyFloatingPreviewDockedRight = @"FloatingPreviewDockedRight";
static NSString *const kKayokoPreferenceKeyFloatingPreviewVerticalPosition = @"FloatingPreviewVerticalPosition";
static NSString *const kKayokoPreferenceKeyFloatingPanelScale = @"FloatingPanelScale";
static NSString *const kKayokoPreferenceKeyFloatingPanelColor = @"FloatingPanelColor";
static NSString *const kKayokoPreferenceKeyImageDoubleTapActionURL = @"ImageDoubleTapActionURL";
static NSString *const kKayokoPreferenceKeyGestureRecognizerMode = @"GestureRecognizerMode";
static NSString *const kKayokoPreferenceKeyAutomaticallyPaste = @"AutomaticallyPaste";
static NSString *const kKayokoPreferenceKeyAutomaticPasteMode = @"AutomaticPasteMode";
static NSString *const kKayokoPreferenceKeyAutomaticPromotionMode = @"AutomaticPromotionMode";
static NSString *const kKayokoPreferenceKeyInitialViewMode = @"InitialViewMode";
static NSString *const kKayokoPreferenceKeyAlwaysScrollToTop = @"AlwaysScrollToTop";
static NSString *const kKayokoPreferenceKeyClearButtonMode = @"ClearButtonMode";
static NSString *const kKayokoPreferenceKeyDismissOnOutsideTouch = @"DismissOnOutsideTouch";
static NSString *const kKayokoPreferenceKeyDisablePasteTips = @"DisablePasteTips";
static NSString *const kKayokoPreferenceKeyIgnoreRemoteReplication = @"IgnoreRemoteReplication";
static NSString *const kKayokoPreferenceKeyApplicationBlacklist = @"ApplicationBlacklist";
static NSString *const kKayokoPreferenceKeyPlaySoundEffects = @"PlaySoundEffects";
static NSString *const kKayokoPreferenceKeyPlayHapticFeedback = @"PlayHapticFeedback";
static NSString *const kKayokoPreferenceKeyPreviewLineCount = @"PreviewLineCount";
static NSString *const kKayokoPreferenceKeyItemDetailsMode = @"ItemDetailsMode";
static NSString *const kKayokoPreferenceKeyHeightInPoints = @"HeightInPoints";
static NSString *const kKayokoPreferenceKeyOverlayWindowLevelMode = @"OverlayWindowLevelMode";
static NSString *const kKayokoPreferenceKeyOverlayWindowLevel = @"OverlayWindowLevel";
static NSString *const kKayokoPreferenceKeyFavoritesFilterPanelVisible = @"FavoritesFilterPanelVisible";
static NSString *const kKayokoPreferenceKeyFavoritesFilterShowsCategories = @"FavoritesFilterShowsCategories";
static NSString *const kKayokoPreferenceKeyFavoritesFilterShowsTags = @"FavoritesFilterShowsTags";
static NSString *const kKayokoPreferenceKeyFavoritesFilterShowsApps = @"FavoritesFilterShowsApps";
static NSString *const kKayokoPreferenceKeyGalleryModeEnabled = @"GalleryModeEnabled";
static NSString *const kKayokoPreferenceKeyClipboardGalleryModeEnabled = @"ClipboardGalleryModeEnabled";
static NSString *const kKayokoPreferenceKeyFavoritesGalleryModeEnabled = @"FavoritesGalleryModeEnabled";

static BOOL const kKayokoPreferenceKeyEnabledDefaultValue = YES;
static NSUInteger const kKayokoPreferenceKeyMaximumHistoryAmountDefaultValue = 200;
static BOOL const kKayokoPreferenceKeySaveTextDefaultValue = YES;
static BOOL const kKayokoPreferenceKeySaveImagesDefaultValue = YES;
static BOOL const kKayokoPreferenceKeySwipeToSelectWordsDefaultValue = YES;
static ActivationMethod const kKayokoPreferenceKeyActivationMethodDefaultValue =
    kActivationMethodDictationKey | kActivationMethodInputSwitcher | kActivationMethodExternalKeyboard;
static BOOL const kKayokoPreferenceKeyPrivacyModeDefaultValue = NO;
static BOOL const kKayokoPreferenceKeyFloatingPreviewDefaultValue = NO;
static BOOL const kKayokoPreferenceKeyFloatingPreviewDoubleTapActionDefaultValue = NO;
static BOOL const kKayokoPreferenceKeyFloatingPreviewCountdownRingDefaultValue = NO;
static CGFloat const kKayokoPreferenceKeyFloatingPreviewSizeDefaultValue = 40.0;
static CGFloat const kKayokoPreferenceKeyFloatingPreviewSizeMinimumValue = 25.0;
static CGFloat const kKayokoPreferenceKeyFloatingPreviewSizeMaximumValue = 100.0;
static CGFloat const kKayokoPreferenceKeyFloatingPreviewDurationDefaultValue = 5.0;
static CGFloat const kKayokoPreferenceKeyFloatingPreviewDurationMinimumValue = 3.0;
static CGFloat const kKayokoPreferenceKeyFloatingPreviewDurationMaximumValue = 10.0;
static NSString *const kKayokoPreferenceKeyFloatingPreviewColorDefaultValue = @"#7FA6F8FF";
static BOOL const kKayokoPreferenceKeyFloatingPreviewDockedRightDefaultValue = YES;
static CGFloat const kKayokoPreferenceKeyFloatingPreviewVerticalPositionDefaultValue = 0.5;
static CGFloat const kKayokoPreferenceKeyFloatingPanelScaleDefaultValue = 1.0;
static CGFloat const kKayokoPreferenceKeyFloatingPanelScaleMinimumValue = 0.50;
static CGFloat const kKayokoPreferenceKeyFloatingPanelScaleMaximumValue = 1.20;
static NSString *const kKayokoPreferenceKeyFloatingPanelColorDefaultValue = @"#30BFBFFF";
static NSString *const kKayokoPreferenceKeyImageDoubleTapActionURLDefaultValue = @"";
static KayokoGestureRecognizerMode const kKayokoPreferenceKeyGestureRecognizerModeDefaultValue =
    kKayokoGestureRecognizerModeClassic;
static BOOL const kKayokoPreferenceKeyAutomaticallyPasteDefaultValue = YES;
static KayokoAutomaticPasteMode const kKayokoPreferenceKeyAutomaticPasteModeDefaultValue =
    kKayokoAutomaticPasteModeClassic;
static KayokoAutomaticPromotionMode const kKayokoPreferenceKeyAutomaticPromotionModeDefaultValue =
    kKayokoAutomaticPromotionModeHistoryOnly;
static KayokoInitialViewMode const kKayokoPreferenceKeyInitialViewModeDefaultValue =
    kKayokoInitialViewModePreviousSelection;
static BOOL const kKayokoPreferenceKeyAlwaysScrollToTopDefaultValue = NO;
static KayokoClearButtonMode const kKayokoPreferenceKeyClearButtonModeDefaultValue = kKayokoClearButtonModeHistoryOnly;
static BOOL const kKayokoPreferenceKeyDismissOnOutsideTouchDefaultValue = YES;
static BOOL const kKayokoPreferenceKeyDisablePasteTipsDefaultValue = NO;
static BOOL const kKayokoPreferenceKeyIgnoreRemoteReplicationDefaultValue = NO;
static BOOL const kKayokoPreferenceKeyPlaySoundEffectsDefaultValue = YES;
static BOOL const kKayokoPreferenceKeyPlayHapticFeedbackDefaultValue = YES;
static NSUInteger const kKayokoPreferenceKeyPreviewLineCountDefaultValue = 1;
static KayokoItemDetailsMode const kKayokoPreferenceKeyItemDetailsModeDefaultValue = kKayokoItemDetailsModeImagesOnly;
static CGFloat const kKayokoPreferenceKeyHeightInPointsDefaultValue = 420;
static KayokoOverlayWindowLevelMode const kKayokoPreferenceKeyOverlayWindowLevelModeDefaultValue =
    kKayokoOverlayWindowLevelModeCustom;
static CGFloat const kKayokoPreferenceKeyOverlayWindowLevelDefaultValue = 998;
static CGFloat const kKayokoPreferenceKeyOverlayWindowLevelMinimumValue = 10;
static CGFloat const kKayokoPreferenceKeyOverlayWindowLevelMaximumValue = 2000;

static BOOL const kKayokoPreferenceKeyFavoritesFilterPanelVisibleDefaultValue = YES;
static BOOL const kKayokoPreferenceKeyFavoritesFilterShowsCategoriesDefaultValue = YES;
static BOOL const kKayokoPreferenceKeyFavoritesFilterShowsTagsDefaultValue = NO;
static BOOL const kKayokoPreferenceKeyFavoritesFilterShowsAppsDefaultValue = NO;
static BOOL const kKayokoPreferenceKeyGalleryModeEnabledDefaultValue = NO;
static BOOL const kKayokoPreferenceKeyClipboardGalleryModeEnabledDefaultValue = NO;
static BOOL const kKayokoPreferenceKeyFavoritesGalleryModeEnabledDefaultValue = NO;
