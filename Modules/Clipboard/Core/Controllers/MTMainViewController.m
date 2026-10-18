//
//  MTMainViewController.m
//  Mt
//

#import "MTMainViewController.h"
#import "MTClearConfirmationView.h"
#import "MTClearConfirmationViewController.h"
#import "MTEmptyStateView.h"
#import "MTExternalHideCoordinator.h"
#import "MTHeaderButtonStyle.h"
#import "MTHeaderView.h"
#import "MTHistoryController.h"
#import "MTHistoryListView.h"
#import "MTHistoryListViewController.h"
#import "MTMainView.h"
#import "MTNoteEditorView.h"
#import "MTNoteEditorViewController.h"
#import "MTPanelPresentationController.h"
#import "MTPasteboardItem.h"
#import "MTPasteboardManager.h"
#import "MTPreviewView.h"
#import "MTPreviewViewController.h"
#import "MTTextEditorView.h"
#import "MTTextEditorViewController.h"
#import "MTSearchController.h"
#import "MTTableViewCell.h"
#import "MTWordSelectionView.h"
#import "MTWordSelectionViewController.h"

#import <QuartzCore/QuartzCore.h>


static CGFloat const kMTTransientEdgeBackHorizontalDominance = 1.2;
static CGFloat const kMTTransientEdgeBackCompletionProgress = 0.35;
static CGFloat const kMTTransientEdgeBackCompletionVelocity = 650;
static NSTimeInterval const kMTTransientEdgeBackMinimumAnimationDuration = 0.08;
static NSTimeInterval const kMTTransientEdgeBackMaximumAnimationDuration = 0.22;
static NSTimeInterval const kMTSearchInputExternalHideSuppressionDuration = 0.75;

typedef NS_ENUM(NSUInteger, MTNoteEditingOrigin) {
    MTNoteEditingOriginNone = 0,
    MTNoteEditingOriginList,
    MTNoteEditingOriginPreview,
    MTNoteEditingOriginWordSelection,
};

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(NSDictionary *)options error:(NSError **)error;
@end

NS_ASSUME_NONNULL_BEGIN

@interface MTMainViewController () <MTClearConfirmationViewControllerDelegate, MTHistoryControllerDelegate,
                                        MTPanelPresentationControllerDelegate, MTSearchControllerDelegate,
                                        MTHistoryListViewControllerDelegate, MTNoteEditorViewControllerDelegate,
                                        MTPreviewViewControllerDelegate, MTTextEditorViewControllerDelegate,
                                        MTWordSelectionViewControllerDelegate,
                                        UIGestureRecognizerDelegate>
#pragma mark - Views

@property(nonatomic, strong) MTMainView *mainView;
@property(nonatomic, strong) MTEmptyStateView *historyEmptyStateView;
@property(nonatomic, strong) MTEmptyStateView *favoritesEmptyStateView;
@property(nonatomic, strong) MTEmptyStateView *storageErrorView;

#pragma mark - Child Controllers

@property(nonatomic, strong) MTHistoryListViewController *historyListViewController;
@property(nonatomic, strong) MTHistoryListViewController *favoritesListViewController;
@property(nonatomic, strong) MTClearConfirmationViewController *clearConfirmationViewController;
@property(nonatomic, strong) MTPreviewViewController *previewViewController;
@property(nonatomic, strong) MTTextEditorViewController *textEditorViewController;
@property(nonatomic, strong) MTWordSelectionViewController *wordSelectionViewController;
@property(nonatomic, strong) MTNoteEditorViewController *noteEditorViewController;

#pragma mark - Coordinators

@property(nonatomic, strong) MTHistoryController *historyController;
@property(nonatomic, strong) MTPanelPresentationController *panelPresentationController;
@property(nonatomic, strong) MTSearchController *searchController;

#pragma mark - State

@property(nonatomic, copy, nullable) NSString *clearConfirmationHistoryKey;
@property(nonatomic, strong, nullable) NSError *storageError;
@property(nonatomic, assign) BOOL preparingToShow;
@property(nonatomic, assign) NSUInteger showRequestIdentifier;
@property(nonatomic, assign, getter=isDismissingPanel) BOOL dismissingPanel;
@property(nonatomic, strong) MTExternalHideCoordinator *externalHideCoordinator;
@property(nonatomic, assign, getter=isClipboardGalleryModeEnabled) BOOL clipboardGalleryModeEnabled;
@property(nonatomic, assign, getter=isFavoritesGalleryModeEnabled) BOOL favoritesGalleryModeEnabled;

#pragma mark - Transient Content

@property(nonatomic, assign) BOOL restoresSearchFirstResponderAfterTransientContent;
@property(nonatomic, assign) BOOL hasSearchContentOffsetBeforeTransientContent;
@property(nonatomic, assign) CGPoint searchContentOffsetBeforeTransientContent;
@property(nonatomic, weak, nullable) UIView *activeSourceContentView;
@property(nonatomic, strong) UIScreenEdgePanGestureRecognizer *transientEdgeBackGestureRecognizer;
@property(nonatomic, weak, nullable) UIView *interactiveTransientReturnSourceView;
@property(nonatomic, weak, nullable) UIView *interactiveTransientReturnContentView;
@property(nonatomic, assign) BOOL interactiveTransientReturnWasPreview;
@property(nonatomic, assign) BOOL didRestoreSearchDuringInteractiveTransientReturn;

#pragma mark - Note Editing

@property(nonatomic, strong, nullable) MTPasteboardItem *noteEditingItem;
@property(nonatomic, copy, nullable) NSString *noteEditingHistoryKey;
@property(nonatomic, weak, nullable) MTHistoryListViewController *noteEditingSourceListViewController;
@property(nonatomic, assign) NSUInteger noteEditingRequestIdentifier;
@property(nonatomic, assign) BOOL noteEditingBeganFromSearch;
@property(nonatomic, assign) BOOL noteEditingKeepsSearchHeaderHidden;
@property(nonatomic, assign, getter=isFinishingNoteEditing) BOOL finishingNoteEditing;
@property(nonatomic, assign) CGRect noteEditingOriginalPanelFrame;
@property(nonatomic, assign) NSTimeInterval noteEditingKeyboardAnimationDuration;
@property(nonatomic, assign) UIViewAnimationOptions noteEditingKeyboardAnimationOptions;
@property(nonatomic, assign) MTNoteEditingOrigin noteEditingOrigin;
@property(nonatomic, assign) BOOL previewTextEditingBeganFromWordSelection;
@property(nonatomic, assign) CGRect previewTextEditingOriginalPanelFrame;
@property(nonatomic, assign, getter=isPreviewTextEditingFinishing) BOOL previewTextEditingFinishing;
@property(nonatomic, assign) NSUInteger previewTextEditingRequestIdentifier;

- (void)showContentForItem:(MTPasteboardItem *)item completion:(nullable void (^)(void))completion;
- (void)showContentForItem:(MTPasteboardItem *)item
    forceWordSelection:(BOOL)forceWordSelection
            completion:(nullable void (^)(void))completion;
- (void)showContentForItem:(MTPasteboardItem *)item
    forceWordSelection:(BOOL)forceWordSelection
               animated:(BOOL)animated
            completion:(nullable void (^)(void))completion;
- (void)showWithInitialContentItem:(nullable MTPasteboardItem *)contentItem
                        completion:(nullable void (^)(void))completion;
@end

NS_ASSUME_NONNULL_END

@implementation MTMainViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _itemDetailsMode = kMTPreferenceKeyItemDetailsModeDefaultValue;
        _privacyMode = kMTPreferenceKeyPrivacyModeDefaultValue;
        _clearButtonMode = kMTPreferenceKeyClearButtonModeDefaultValue;
        NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
        id legacyGalleryModeValue = [preferences objectForKey:kMTPreferenceKeyGalleryModeEnabled];
        id clipboardGalleryModeValue =
            [preferences objectForKey:kMTPreferenceKeyClipboardGalleryModeEnabled];
        id favoritesGalleryModeValue =
            [preferences objectForKey:kMTPreferenceKeyFavoritesGalleryModeEnabled];
        _clipboardGalleryModeEnabled = clipboardGalleryModeValue
                                           ? [clipboardGalleryModeValue boolValue]
                                           : (legacyGalleryModeValue
                                                  ? [legacyGalleryModeValue boolValue]
                                                  : kMTPreferenceKeyClipboardGalleryModeEnabledDefaultValue);
        _favoritesGalleryModeEnabled = favoritesGalleryModeValue
                                           ? [favoritesGalleryModeValue boolValue]
                                           : (legacyGalleryModeValue
                                                  ? [legacyGalleryModeValue boolValue]
                                                  : kMTPreferenceKeyFavoritesGalleryModeEnabledDefaultValue);
        _mtSupportedInterfaceOrientations = UIInterfaceOrientationMaskAll;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handlePreviewTextEditingKeyboardWillChangeFrameNotification:)
                                                     name:UIKeyboardWillChangeFrameNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handlePreviewTextEditingKeyboardWillHideNotification:)
                                                     name:UIKeyboardWillHideNotification
                                                   object:nil];
        _presentationMode = MTPanelPresentationModePortraitDrawer;
        _externalHideCoordinator = [[MTExternalHideCoordinator alloc] init];
        _mainView = [[MTMainView alloc] initWithFrame:frame];
        [self setView:_mainView];
        _historyListViewController = [[MTHistoryListViewController alloc]
            initWithName:[[MTPasteboardManager localizationBundle] localizedStringForKey:@"History"
                                                                                       value:nil
                                                                                       table:@"Tweak"]
              historyKey:kMTHistoryKeyHistory];
        [_historyListViewController setDelegate:self];
        [_historyListViewController setGalleryModeEnabled:_clipboardGalleryModeEnabled];
        [self addChildViewController:_historyListViewController];
        [_mainView installContentView:[_historyListViewController tableView] hidden:NO];
        [_historyListViewController didMoveToParentViewController:self];

        _favoritesListViewController = [[MTHistoryListViewController alloc]
            initWithName:[[MTPasteboardManager localizationBundle] localizedStringForKey:@"Favorites"
                                                                                       value:nil
                                                                                       table:@"Tweak"]
              historyKey:kMTHistoryKeyFavorites];
        [_favoritesListViewController setDelegate:self];
        [_favoritesListViewController setGalleryModeEnabled:_favoritesGalleryModeEnabled];
        [self addChildViewController:_favoritesListViewController];
        [_mainView installContentView:[_favoritesListViewController tableView] hidden:YES];
        [_favoritesListViewController didMoveToParentViewController:self];

        _historyController =
            [[MTHistoryController alloc] initWithHistoryListViewController:_historyListViewController
                                                   favoritesListViewController:_favoritesListViewController];
        [_historyController setDelegate:self];

        __weak typeof(self) weakSelf = self;
        [[[_mainView headerView] historySegmentedControl]
            addTarget:self
               action:@selector(handleHistorySegmentedControlChanged:)
     forControlEvents:UIControlEventValueChanged];
        [[[_mainView headerView] leadingButton] setHidden:NO];
        [[[_mainView headerView] leadingButton] setShowsMenuAsPrimaryAction:YES];
        [[[_mainView headerView] trailingButton] addTarget:self
                                                    action:@selector(handleClearButtonPressed)
                                          forControlEvents:UIControlEventTouchUpInside];
        [[[_mainView headerView] titleTapControl] addTarget:self
                                                     action:@selector(handleTitleTapControlPressed)
                                           forControlEvents:UIControlEventTouchUpInside];

        _panelPresentationController = [[MTPanelPresentationController alloc] initWithPanelView:_mainView];
        [_panelPresentationController setDelegate:self];

        _clearConfirmationViewController = [[MTClearConfirmationViewController alloc] init];
        [_clearConfirmationViewController setDelegate:self];
        [self addChildViewController:_clearConfirmationViewController];
        [_mainView installContentView:[_clearConfirmationViewController confirmationView] hidden:YES];
        [_clearConfirmationViewController didMoveToParentViewController:self];

        _historyEmptyStateView = [[MTEmptyStateView alloc] init];
        [_historyEmptyStateView updateWithHistoryKey:kMTHistoryKeyHistory];
        [_mainView installContentView:_historyEmptyStateView hidden:YES];

        _favoritesEmptyStateView = [[MTEmptyStateView alloc] init];
        [_favoritesEmptyStateView updateWithHistoryKey:kMTHistoryKeyFavorites];
        [_mainView installContentView:_favoritesEmptyStateView hidden:YES];

        _storageErrorView = [[MTEmptyStateView alloc] init];
        [_mainView installContentView:_storageErrorView hidden:YES];

        _previewViewController = [[MTPreviewViewController alloc] init];
        [_previewViewController setDelegate:self];
        [_previewViewController setHapticFeedbackHandler:^(UIImpactFeedbackStyle style) {
          [[weakSelf panelPresentationController] triggerHapticFeedbackWithStyle:style];
        }];
        [self addChildViewController:_previewViewController];
        MTHeaderView *previewHeaderView = [[_previewViewController previewView] headerView];
        [_mainView installFullContentView:[_previewViewController previewView] headerView:previewHeaderView hidden:YES];
        [_panelPresentationController registerHeaderView:previewHeaderView];
        [_previewViewController didMoveToParentViewController:self];
        [[previewHeaderView leadingButton] addTarget:self
                                              action:@selector(handleTransientBackButtonPressed)
                                    forControlEvents:UIControlEventTouchUpInside];
        [[previewHeaderView trailingButton] addTarget:self
                                               action:@selector(handlePreviewActionButtonPressed)
                                     forControlEvents:UIControlEventTouchUpInside];
        [[previewHeaderView titleTapControl] addTarget:self
                                                action:@selector(handleTitleTapControlPressed)
                                      forControlEvents:UIControlEventTouchUpInside];

        _textEditorViewController = [[MTTextEditorViewController alloc] init];
        [_textEditorViewController setDelegate:self];
        [self addChildViewController:_textEditorViewController];
        MTHeaderView *textEditorHeaderView = [[_textEditorViewController textEditorView] headerView];
        [_mainView installFullContentView:[_textEditorViewController textEditorView]
                               headerView:textEditorHeaderView
                                   hidden:YES];
        [_panelPresentationController registerHeaderView:textEditorHeaderView];
        [_textEditorViewController didMoveToParentViewController:self];
        [[textEditorHeaderView leadingButton] addTarget:self
                                                 action:@selector(handleTransientBackButtonPressed)
                                       forControlEvents:UIControlEventTouchUpInside];

        _wordSelectionViewController = [[MTWordSelectionViewController alloc]
            initWithName:[[MTPasteboardManager localizationBundle] localizedStringForKey:@"Preview"
                                                                                       value:nil
                                                                                       table:@"Tweak"]];
        [_wordSelectionViewController setDelegate:self];
        [self addChildViewController:_wordSelectionViewController];
        MTHeaderView *wordSelectionHeaderView = [[_wordSelectionViewController wordSelectionView] headerView];
        [_mainView installFullContentView:[_wordSelectionViewController view]
                               headerView:wordSelectionHeaderView
                                   hidden:YES];
        [_panelPresentationController registerHeaderView:wordSelectionHeaderView];
        [_wordSelectionViewController didMoveToParentViewController:self];
        [[wordSelectionHeaderView leadingButton] addTarget:self
                                                    action:@selector(handleTransientBackButtonPressed)
                                          forControlEvents:UIControlEventTouchUpInside];
        [[wordSelectionHeaderView trailingButton] addTarget:self
                                                     action:@selector(handlePreviewActionButtonPressed)
                                           forControlEvents:UIControlEventTouchUpInside];
        [[wordSelectionHeaderView titleTapControl] addTarget:self
                                                      action:@selector(handleTitleTapControlPressed)
                                            forControlEvents:UIControlEventTouchUpInside];

        _searchController =
            [[MTSearchController alloc] initWithContainerView:_mainView
                                                       headerView:[_mainView headerView]
                                        historyListViewController:_historyListViewController
                                      favoritesListViewController:_favoritesListViewController
                                             panGestureRecognizer:[_panelPresentationController panGestureRecognizer]];
        [_searchController setDelegate:self];

        _noteEditorViewController = [[MTNoteEditorViewController alloc] init];
        [_noteEditorViewController setDelegate:self];
        [self addChildViewController:_noteEditorViewController];
        MTNoteEditorView *noteEditorView = (MTNoteEditorView *)[_noteEditorViewController view];
        [noteEditorView setHidden:YES];
        [[_mainView chromeClipView] addSubview:noteEditorView];
        [noteEditorView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[noteEditorView topAnchor] constraintEqualToAnchor:[[_mainView chromeClipView] topAnchor]],
            [[noteEditorView leadingAnchor] constraintEqualToAnchor:[[_mainView chromeClipView] leadingAnchor]],
            [[noteEditorView trailingAnchor] constraintEqualToAnchor:[[_mainView chromeClipView] trailingAnchor]],
            [[noteEditorView bottomAnchor] constraintEqualToAnchor:[[_mainView chromeClipView] bottomAnchor]]
        ]];
        [_noteEditorViewController didMoveToParentViewController:self];

        _transientEdgeBackGestureRecognizer = [[UIScreenEdgePanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(handleTransientEdgeBackGestureRecognizer:)];
        [_transientEdgeBackGestureRecognizer setEdges:UIRectEdgeLeft];
        [_transientEdgeBackGestureRecognizer setDelegate:self];
        [_mainView addGestureRecognizer:_transientEdgeBackGestureRecognizer];

        [[_previewViewController previewView]
            requireImagePanGestureRecognizerToFailGestureRecognizer:_transientEdgeBackGestureRecognizer];
        [[_wordSelectionViewController wordSelectionView]
            requireSelectionGestureRecognizerToFailGestureRecognizer:_transientEdgeBackGestureRecognizer];
    }
    return self;
}

#pragma mark - Configuration

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [self mtSupportedInterfaceOrientations];
}

- (BOOL)isHidden {
    return [[self mainView] isHidden];
}

- (void)setOutsideDismissOverlayView:(UIControl *)outsideDismissOverlayView {
    [[self panelPresentationController] setOutsideDismissOverlayView:outsideDismissOverlayView];
}

- (void)applyUserInterfaceStyle:(UIUserInterfaceStyle)style {
    [self setOverrideUserInterfaceStyle:style];
    [[self view] setOverrideUserInterfaceStyle:style];

    for (UIViewController *childViewController in [self childViewControllers]) {
        [childViewController setOverrideUserInterfaceStyle:style];
        [[childViewController view] setOverrideUserInterfaceStyle:style];
    }

    [[self historyEmptyStateView] setOverrideUserInterfaceStyle:style];
    [[self favoritesEmptyStateView] setOverrideUserInterfaceStyle:style];
    [[self storageErrorView] setOverrideUserInterfaceStyle:style];
}

- (void)setDismissOnOutsideTouch:(BOOL)dismissOnOutsideTouch {
    _dismissOnOutsideTouch = dismissOnOutsideTouch;
    [[self panelPresentationController] setDismissOnOutsideTouch:dismissOnOutsideTouch];
}

- (void)setPreviewLineCount:(NSUInteger)previewLineCount {
    _previewLineCount = previewLineCount;
    [[self historyListViewController] setPreviewLineCount:previewLineCount];
    [[self favoritesListViewController] setPreviewLineCount:previewLineCount];
}

- (void)setPrivacyMode:(BOOL)privacyMode {
    _privacyMode = privacyMode;
    [[self historyListViewController] setPrivacyMode:privacyMode];
    [[self favoritesListViewController] setPrivacyMode:privacyMode];
}

- (void)setItemDetailsMode:(MTItemDetailsMode)itemDetailsMode {
    if (itemDetailsMode != kMTItemDetailsModeOff && itemDetailsMode != kMTItemDetailsModeImagesOnly &&
        itemDetailsMode != kMTItemDetailsModeAll) {
        itemDetailsMode = kMTPreferenceKeyItemDetailsModeDefaultValue;
    }
    _itemDetailsMode = itemDetailsMode;
    [[self historyListViewController] setItemDetailsMode:itemDetailsMode];
    [[self favoritesListViewController] setItemDetailsMode:itemDetailsMode];
}

- (void)setClearButtonMode:(MTClearButtonMode)clearButtonMode {
    if (clearButtonMode != kMTClearButtonModeOff && clearButtonMode != kMTClearButtonModeHistoryOnly &&
        clearButtonMode != kMTClearButtonModeAlways) {
        clearButtonMode = kMTPreferenceKeyClearButtonModeDefaultValue;
    }
    _clearButtonMode = clearButtonMode;
    [self updateClearButtonState];
}

- (void)setShouldPlayFeedback:(BOOL)shouldPlayFeedback {
    _shouldPlayFeedback = shouldPlayFeedback;
    [[self panelPresentationController] setShouldPlayFeedback:shouldPlayFeedback];
}


- (void)setPresentationMode:(MTPanelPresentationMode)presentationMode {
    _presentationMode = presentationMode;
    [[self panelPresentationController] setPresentationMode:presentationMode];
    [[self searchController] setPresentationMode:presentationMode];
    [[[self noteEditorViewController] noteEditorView]
        setCompactLayout:presentationMode == MTPanelPresentationModeCompactLandscapeFullscreen];
    [self applyBasePresentationLayout];
}

- (void)applyBasePresentationLayout {
    if ([self presentationMode] == MTPanelPresentationModeCompactLandscapeFullscreen) {
        [[self mainView] setContentSafeAreaAdditionalInsets:UIEdgeInsetsZero];
        [[self mainView] setContentRespectsSafeArea:YES];
        return;
    }

    if (![[self searchController] isSearchActive]) {
        [[self mainView] setContentRespectsSafeArea:NO];
        [[self mainView] setContentSafeAreaAdditionalInsets:UIEdgeInsetsZero];
    }
}


#pragma mark - Layout and Lookup

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self handleViewLayout];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self handleViewLayout];
}

- (void)handleViewLayout {
    [[self searchController] layout];
}

- (NSString *)effectiveActiveHistoryKey {
    return [[self historyController]
        effectiveActiveHistoryKeyWithClearConfirmationHistoryKey:[self clearConfirmationHistoryKey]];
}

- (MTHistoryListView *)activeTableView {
    return [[self historyController] activeTableViewWithClearConfirmationHistoryKey:[self clearConfirmationHistoryKey]];
}

- (MTHistoryListViewController *)activeListViewController {
    return [[self historyController] listViewControllerForHistoryKey:[self effectiveActiveHistoryKey]];
}

- (MTHistoryListViewController *)listViewControllerForHistoryKey:(NSString *)historyKey {
    return [[self historyController] listViewControllerForHistoryKey:historyKey];
}

- (MTHistoryListViewController *)activeListViewControllerForSearchController:
    (MTSearchController *)searchController {
    (void)searchController;
    return [self activeListViewController];
}

#pragma mark - External Hide Coordinator

- (BOOL)externalHideRequestShouldWaitForAnimations {
    return [self preparingToShow] || [[self mainView] isAnimating] || [[self panelPresentationController] isAnimating];
}

- (void)executePendingExternalHideRequestIfReady {
    if ([[self externalHideCoordinator] shouldSuppressExternalHide] ||
        [self externalHideRequestShouldWaitForAnimations]) {
        return;
    }

    if (([[self searchController] isSearchActive] && [[self searchController] isActiveSearchFirstResponder]) ||
        [self isPreviewTextEditing]) {
        return;
    }

    MTExternalHideRequest *request = [[self externalHideCoordinator] takePendingExternalHideRequest];
    if (!request || [self isHidden]) {
        return;
    }

    [self hideWithAnimationStyle:[request animationStyle] completion:[request completion]];
}

- (void)beginSearchInputExternalHideSuppression {
    __weak typeof(self) weakSelf = self;
    [[self externalHideCoordinator]
        beginSearchInputTransitionSuppressionWithDuration:kMTSearchInputExternalHideSuppressionDuration
                                        expirationHandler:^{
                                          [weakSelf executePendingExternalHideRequestIfReady];
                                        }];
}

- (void)endSearchInputExternalHideSuppression {
    if (![[self externalHideCoordinator] shouldSuppressExternalHide]) {
        return;
    }

    [[self externalHideCoordinator] endSearchInputTransitionSuppression];
    [self executePendingExternalHideRequestIfReady];
}

- (void)clearExternalHideCoordinator {
    [[self externalHideCoordinator] clear];
}

#pragma mark - MTSearchControllerDelegate

- (void)searchControllerWillBeginSearchInputTransition:(MTSearchController *)searchController {
    (void)searchController;
    [self beginSearchInputExternalHideSuppression];
}

- (void)searchControllerWillAnimateSearchState:(MTSearchController *)searchController {
    (void)searchController;
    [[self mainView] setAnimating:YES];
    [[self panelPresentationController] finishOutsideDismissOverlayShow];
}

- (void)searchControllerDidFinishAnimatingSearchState:(MTSearchController *)searchController {
    [[self mainView] setAnimating:NO];
    [[self panelPresentationController] finishOutsideDismissOverlayShow];
    if (![searchController isSearchActive]) {
        [self endSearchInputExternalHideSuppression];
    }
    [self executePendingExternalHideRequestIfReady];
}

- (void)searchController:(MTSearchController *)searchController
    didUpdateKeyboardBottomInset:(CGFloat)keyboardBottomInset {
    [[[self clearConfirmationViewController] confirmationView] setKeyboardBottomInset:keyboardBottomInset];
    [[self historyEmptyStateView] setKeyboardBottomInset:keyboardBottomInset];
    [[self favoritesEmptyStateView] setKeyboardBottomInset:keyboardBottomInset];
    [[self storageErrorView] setKeyboardBottomInset:keyboardBottomInset];
    if (![self isPreviewTextEditing]) {
        [[[self previewViewController] previewView] setKeyboardBottomInset:keyboardBottomInset];
    }
    [[[self wordSelectionViewController] wordSelectionView] setKeyboardBottomInset:keyboardBottomInset];
    [self updatePreviewTextEditingPanelForKeyboardBottomInset:keyboardBottomInset];
}

- (CGRect)previewTextEditingPanelFrameForKeyboardBottomInset:(CGFloat)keyboardBottomInset {
    UIView *mainView = [self mainView];
    UIView *superview = [mainView superview];
    if (!superview) {
        return [mainView frame];
    }

    CGRect bounds = [superview bounds];
    CGFloat inset = kMTPanelFloatingInset;
    CGRect referenceFrame = CGRectIsEmpty([self previewTextEditingOriginalPanelFrame])
                                ? [mainView frame]
                                : [self previewTextEditingOriginalPanelFrame];

    CGFloat width = CGRectGetWidth(referenceFrame);
    CGFloat x = CGRectGetMinX(referenceFrame);
    if (width <= 0.0 || width >= CGRectGetWidth(bounds) - 1.0) {
        width = MIN(kMTPanelFloatingMaxWidth, CGRectGetWidth(bounds) - inset * 2.0);
        width = MAX(width, 280.0);
        x = CGRectGetMidX(bounds) - width * 0.5;
    }

    CGFloat preferredHeight = CGRectGetHeight(referenceFrame);
    if (preferredHeight <= 0.0) {
        preferredHeight = MIN(420.0, CGRectGetHeight(bounds) - inset * 2.0);
        preferredHeight = MAX(preferredHeight, 220.0);
    }

    CGFloat availableBottom = CGRectGetMaxY(bounds) - MAX(keyboardBottomInset, 0.0) - inset;
    CGFloat maxHeight = MAX(availableBottom - inset, 220.0);
    CGFloat height = MIN(preferredHeight, maxHeight);
    CGFloat y = availableBottom - height;
    if (y < inset) {
        y = inset;
        height = MIN(height, MAX(availableBottom - y, 220.0));
    }
    return CGRectMake(x, y, width, height);
}

- (BOOL)shouldLiftPreviewTextEditingCard {
    return [self presentationMode] != MTPanelPresentationModeCompactLandscapeFullscreen;
}

- (void)updatePreviewTextEditingPanelForKeyboardBottomInset:(CGFloat)keyboardBottomInset
                                          animationDuration:(NSTimeInterval)duration
                                                    options:(UIViewAnimationOptions)options {
    BOOL liftsCard = [self shouldLiftPreviewTextEditingCard];
    [[[self textEditorViewController] textEditorView] setKeyboardBottomInset:liftsCard ? 0 : keyboardBottomInset];
    if ([self isDismissingPanel] || !liftsCard) {
        return;
    }
    if (![self isPreviewTextEditing] && ![self isPreviewTextEditingFinishing]) {
        return;
    }

    UIView *mainView = [self mainView];
    if (![mainView superview]) {
        return;
    }

    if (CGRectIsEmpty([self previewTextEditingOriginalPanelFrame])) {
        if ([self isPreviewTextEditingFinishing]) {
            return;
        }
        [self setPreviewTextEditingOriginalPanelFrame:[mainView frame]];
    }

    CGRect targetFrame = keyboardBottomInset > 0.5
                             ? [self previewTextEditingPanelFrameForKeyboardBottomInset:keyboardBottomInset]
                             : [self previewTextEditingOriginalPanelFrame];
    if (CGRectIsEmpty(targetFrame) || CGRectEqualToRect([mainView frame], targetFrame)) {
        return;
    }
    if (duration <= 0.01) {
        duration = 0.25;
        options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction |
                  UIViewAnimationOptionCurveEaseOut;
    }
    [mainView layoutIfNeeded];
    [UIView animateWithDuration:duration
                          delay:0
                        options:options | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                       [mainView setTransform:CGAffineTransformIdentity];
                       [mainView setFrame:targetFrame];
                       [mainView layoutIfNeeded];
                     }
                     completion:^(__unused BOOL finished) {
                       if (![self isPreviewTextEditingFinishing] || keyboardBottomInset > 0.5) {
                           return;
                       }
                       [self setPreviewTextEditingOriginalPanelFrame:CGRectZero];
                       [self setPreviewTextEditingFinishing:NO];
                     }];
}

- (void)updatePreviewTextEditingPanelForKeyboardBottomInset:(CGFloat)keyboardBottomInset {
    [self updatePreviewTextEditingPanelForKeyboardBottomInset:keyboardBottomInset
                                            animationDuration:0
                                                      options:0];
}

- (void)handlePreviewTextEditingKeyboardWillChangeFrameNotification:(NSNotification *)notification {
    if ([self isDismissingPanel] ||
        (![self isPreviewTextEditing] && ![self isPreviewTextEditingFinishing]) ||
        ![notification.userInfo[UIKeyboardIsLocalUserInfoKey] boolValue]) {
        return;
    }

    UIView *mainView = [self mainView];
    UIView *referenceView = [mainView superview] ?: mainView;
    CGRect keyboardEndFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardFrameInView = [referenceView convertRect:keyboardEndFrame fromView:nil];
    CGFloat keyboardBottomInset = 0;
    if (!CGRectIsNull(keyboardFrameInView) && !CGRectIsEmpty(keyboardFrameInView)) {
        CGFloat referenceBottom = CGRectGetMaxY([referenceView bounds]);
        CGFloat keyboardTop = CGRectGetMinY(keyboardFrameInView);
        if (keyboardTop < referenceBottom - 0.5) {
            keyboardBottomInset = MAX(referenceBottom - keyboardTop, 0);
        }
    }

    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve =
        (UIViewAnimationCurve)[notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions options = (UIViewAnimationOptions)(curve << 16) |
                                     UIViewAnimationOptionBeginFromCurrentState |
                                     UIViewAnimationOptionAllowUserInteraction;
    [self updatePreviewTextEditingPanelForKeyboardBottomInset:keyboardBottomInset
                                            animationDuration:duration
                                                      options:options];
}

- (void)handlePreviewTextEditingKeyboardWillHideNotification:(NSNotification *)notification {
    if ([self isDismissingPanel] || (![self isPreviewTextEditing] && ![self isPreviewTextEditingFinishing])) {
        return;
    }
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve =
        (UIViewAnimationCurve)[notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions options = (UIViewAnimationOptions)(curve << 16) |
                                     UIViewAnimationOptionBeginFromCurrentState |
                                     UIViewAnimationOptionAllowUserInteraction;
    [self updatePreviewTextEditingPanelForKeyboardBottomInset:0 animationDuration:duration options:options];
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == [self transientEdgeBackGestureRecognizer]) {
        return [self canBeginTransientEdgeBackGestureRecognizer:(UIScreenEdgePanGestureRecognizer *)gestureRecognizer];
    }

    return YES;
}

#pragma mark - MTPanelPresentationControllerDelegate

- (void)panelPresentationControllerDidRequestDismiss:(MTPanelPresentationController *)controller {
    [self hideRestoringFocus];
}

- (void)panelPresentationControllerDidTapGrabberArea:(MTPanelPresentationController *)controller {
    if ([[self searchController] isSearchActive]) {
        [[self searchController] cancelSearchWithCompletion:nil];
    } else {
        [[self panelPresentationController] prepareStandardDismissAnimation];
        [self hideRestoringFocus];
    }
}

- (void)panelPresentationControllerDidDoubleTapHeaderArea:(MTPanelPresentationController *)controller {
    (void)controller;
    if ([[self panelPresentationController] isAnimating] || [[self mainView] isAnimating]) {
        return;
    }

    NSLog(@"[Mt] header double-tap: scroll active content to top");
    if (![[[self previewViewController] previewView] isHidden]) {
        [[self previewViewController] scrollToTopAnimated:YES];
        return;
    }

    [[self activeListViewController] scrollToTopAnimated:YES];
}

- (BOOL)panelPresentationControllerShouldHandleFullscreenSearchPan:(MTPanelPresentationController *)controller {
    return ![self isEditingAnyContent] && [self presentationMode] != MTPanelPresentationModeCompactLandscapeFullscreen &&
           [[self searchController] isSearchActive];
}

- (BOOL)panelPresentationController:(MTPanelPresentationController *)controller
    shouldBeginExpandedPanelPanFromView:(nullable UIView *)view
                               velocity:(CGPoint)velocity {
    (void)controller;
    (void)view;
    (void)velocity;
    if ([self isHidden] || [[self panelPresentationController] isAnimating]) {
        return NO;
    }
    if ([self isPreviewTextEditing]) {
        return NO;
    }
    if ([self isNoteEditing]) {
        MTNoteEditorView *noteEditorView = [[self noteEditorViewController] noteEditorView];
        if ([view isDescendantOfView:[noteEditorView textField]] ||
            [view isDescendantOfView:[noteEditorView saveButton]] ||
            [view isDescendantOfView:[noteEditorView cancelButton]]) {
            return NO;
        }
        return [view isDescendantOfView:noteEditorView];
    }
    if ([self isShowingClearConfirmation] || [self isPreviewActive] || [self isWordSelectionActive]) {
        return NO;
    }

    UIView *activeContentView = [self activeHistoryContentView];
    return activeContentView == [[self historyListViewController] tableView] ||
           activeContentView == [[self favoritesListViewController] tableView] ||
           activeContentView == [self historyEmptyStateView] || activeContentView == [self favoritesEmptyStateView] ||
           activeContentView == [self storageErrorView];
}

- (BOOL)isFullscreenSearchActive {
    return [[self searchController] isSearchActive];
}

- (BOOL)shouldSuppressSystemMultitaskingGesture {
    return NO;
}

- (void)panelPresentationController:(MTPanelPresentationController *)controller
    handleFullscreenSearchPanGestureRecognizer:(UIPanGestureRecognizer *)recognizer
                                    headerView:(nullable MTHeaderView *)headerView {
    [[self searchController] handleFullscreenPanGestureRecognizer:recognizer headerView:headerView];
}

#pragma mark - MTHistoryControllerDelegate

- (BOOL)historyControllerIsPanelVisible:(MTHistoryController *)controller {
    return ![self isHidden];
}

- (BOOL)historyControllerShouldSuppressVisibleUpdates:(MTHistoryController *)controller {
    return [self isDismissingPanel];
}

- (void)historyControllerNeedsVisibleReload:(MTHistoryController *)controller {
    [self reload];
}

- (void)historyController:(MTHistoryController *)controller
    didUpdateActiveTableView:(MTHistoryListView *)tableView {
    [self setStorageError:nil];
    [self updateActiveTableViewState:tableView];
}

- (void)historyController:(MTHistoryController *)controller didFailLoadingHistoryWithError:(NSError *)error {
    [self showStorageError:error];
}

- (void)searchController:(MTSearchController *)searchController didFailLoadingSearchWithError:(NSError *)error {
    [self showStorageError:error];
}

- (void)handleApplicationMetadataChanged {
    [[self searchController] handleApplicationMetadataChanged];
}

#pragma mark - MTHistoryListViewControllerDelegate

- (void)historyListViewControllerDidRequestHide:(MTHistoryListViewController *)controller {
    [[self panelPresentationController] prepareStandardDismissAnimation];
    [self hideRestoringFocus];
}

- (void)historyListViewControllerDidRequestHideAfterDirectPaste:(MTHistoryListViewController *)controller {
    [[self panelPresentationController] prepareStandardDismissAnimation];
    [self hideAfterDirectPaste];
}

- (void)historyListViewController:(MTHistoryListViewController *)controller
         didRequestPreviewForItem:(MTPasteboardItem *)item {
    [self showContentForItem:item];
}

- (void)historyListViewController:(MTHistoryListViewController *)controller
        didRequestEditNoteForItem:(MTPasteboardItem *)item
                 presentationCell:(MTTableViewCell *)presentationCell
                       sourceCell:(MTTableViewCell *)sourceCell {
    [self beginNoteEditingForItem:item
               listViewController:controller
                 presentationCell:presentationCell
                       sourceCell:sourceCell];
}

- (void)historyListViewControllerDidChangeContentState:(MTHistoryListViewController *)controller {
    [self updateContentState];
    // Content mutations can change the app token sources even when no history
    // change notification is emitted (for example, removing a favorite).
    [[self searchController] handleHistoryContentChanged];
}

- (void)historyListViewController:(MTHistoryListViewController *)controller
            didMoveItemDictionary:(NSDictionary<NSString *, id> *)dictionary
               fromHistoryWithKey:(NSString *)sourceHistoryKey
                 toHistoryWithKey:(NSString *)destinationHistoryKey {
    [self handlePasteboardItemDictionary:dictionary
                     movedFromHistoryKey:sourceHistoryKey
                            toHistoryKey:destinationHistoryKey];
    // Refresh again after the source list finishes removing the moved item so
    // both token lists reflect the completed favorite toggle.
    [[self searchController] handleHistoryContentChanged];
}

#pragma mark - Content Lookup

- (MTHistoryListView *)tableViewForHistoryKey:(NSString *)historyKey {
    return [[self historyController] tableViewForHistoryKey:historyKey];
}

- (MTEmptyStateView *)emptyStateViewForHistoryKey:(NSString *)historyKey {
    return [historyKey isEqualToString:kMTHistoryKeyFavorites] ? [self favoritesEmptyStateView]
                                                                   : [self historyEmptyStateView];
}

- (UIView *)contentViewForHistoryKey:(NSString *)historyKey {

    if ([self storageError]) {
        [[self storageErrorView] updateWithStorageError:[self storageError]];
        [[self storageErrorView] setKeyboardBottomInset:[[self searchController] keyboardBottomInset]];
        return [self storageErrorView];
    }

    MTHistoryListViewController *listViewController = [self listViewControllerForHistoryKey:historyKey];
    if ([[listViewController items] count] > 0) {
        return [listViewController tableView];
    }

    MTEmptyStateView *emptyStateView = [self emptyStateViewForHistoryKey:historyKey];
    [emptyStateView setKeyboardBottomInset:[[self searchController] keyboardBottomInset]];
    return emptyStateView;
}

- (UIView *)activeHistoryContentView {
    if (![[[self historyListViewController] tableView] isHidden]) {
        return [[self historyListViewController] tableView];
    }

    if (![[[self favoritesListViewController] tableView] isHidden]) {
        return [[self favoritesListViewController] tableView];
    }

    if (![[self historyEmptyStateView] isHidden]) {
        return [self historyEmptyStateView];
    }

    if (![[self favoritesEmptyStateView] isHidden]) {
        return [self favoritesEmptyStateView];
    }

    if (![[self storageErrorView] isHidden]) {
        return [self storageErrorView];
    }

    return [self emptyStateViewForHistoryKey:[self effectiveActiveHistoryKey]];
}

- (NSString *)titleForContentView:(UIView *)view {
    if (view == [[self historyListViewController] tableView] || view == [self historyEmptyStateView]) {
        return [[MTPasteboardManager localizationBundle] localizedStringForKey:@"History" value:nil table:@"Tweak"];
    }
    if (view == [[self favoritesListViewController] tableView] || view == [self favoritesEmptyStateView]) {
        return [[MTPasteboardManager localizationBundle] localizedStringForKey:@"Favorites" value:nil table:@"Tweak"];
    }
    if (view == [self storageErrorView]) {
        return [[self storageErrorView] name] ?: @"";
    }
    if (view == [[self clearConfirmationViewController] confirmationView]) {
        return [[MTPasteboardManager localizationBundle] localizedStringForKey:@"Clear" value:nil table:@"Tweak"]
            ?: @"Clear";
    }
    if (view == [[self previewViewController] previewView]) {
        return [[[self previewViewController] previewView] name] ?: @"";
    }
    if (view == [[self wordSelectionViewController] view] ||
        view == [[self wordSelectionViewController] wordSelectionView]) {
        return [[self wordSelectionViewController] name] ?: @"";
    }
    return [[[[[self mainView] headerView] titleLabel] text] copy] ?: @"";
}


#pragma mark - History Content

- (void)prepareHistoryListForDisplayIfNeededForHistoryKey:(NSString *)historyKey contentView:(UIView *)contentView {
    MTHistoryListViewController *listViewController = [self listViewControllerForHistoryKey:historyKey];
    if (contentView != [listViewController tableView] || [[self searchController] isSearchActive] ||
        [listViewController hasActiveSearch]) {
        return;
    }

    if (![[self historyController] consumeScrollToTopBeforeNextDisplayForHistoryKey:historyKey]) {
        return;
    }

    [[listViewController tableView] scrollToFirstItemKeepingSearchHeaderHiddenWithoutAnimation];
}

- (void)setHistoryContentVisibleForKey:(NSString *)historyKey {
    [[self historyController] setActiveHistoryKey:historyKey];
    UIView *contentView = [self contentViewForHistoryKey:historyKey];
    MTHistoryListView *tableView = [[self listViewControllerForHistoryKey:historyKey] tableView];
    BOOL preparesListBeforeDisplay = [self isHidden] || [tableView isHidden];
    [[[self historyListViewController] tableView]
        setHidden:contentView != [[self historyListViewController] tableView]];
    [[[self favoritesListViewController] tableView]
        setHidden:contentView != [[self favoritesListViewController] tableView]];
    [[self historyEmptyStateView] setHidden:contentView != [self historyEmptyStateView]];
    [[self favoritesEmptyStateView] setHidden:contentView != [self favoritesEmptyStateView]];
    [[self storageErrorView] setHidden:contentView != [self storageErrorView]];
    [contentView setAlpha:1];
    [contentView setTransform:CGAffineTransformIdentity];

    [self restoreHistoryHeaderIconForHistoryKey:historyKey];
    [[[self mainView] headerView] setHistorySwitcherVisible:YES animated:NO];
    [self updateFavoritesButtonForHistoryKey:historyKey];
    [[[[self mainView] headerView] alternateTrailingButton] setHidden:YES];
    [[[[self mainView] headerView] titleTapControl] setEnabled:NO];
    [[self searchController] attachToListViewController:[self listViewControllerForHistoryKey:historyKey]
                                         hidesSearchBar:![[self searchController] isSearchActive]];
    [[self searchController] refreshForListViewController:[self activeListViewController]];
    if (preparesListBeforeDisplay) {
        [self prepareHistoryListForDisplayIfNeededForHistoryKey:historyKey contentView:contentView];
    }
    [[self mainView] setTitleText:[self titleForContentView:contentView]];
    [self updateClearButtonState];
}

- (void)markHistoryKeyLoaded:(NSString *)historyKey {
    [[self historyController] markHistoryKeyLoaded:historyKey];
}

- (void)markHistoryKeyDirty:(NSString *)historyKey {
    [[self historyController] markHistoryKeyDirty:historyKey];
}

- (void)updateActiveTableViewState:(MTHistoryListView *)tableView {
    if (tableView == [self activeTableView]) {
        MTHistoryListViewController *activeListViewController = [self activeListViewController];

        if ([self shouldDeferHistoryPresentationUpdates]) {
            [self updateClearButtonState];
            return;
        }
        if ([self cancelSearchForEmptyActiveHistoryIfNeededHidingView:[self activeHistoryContentView]
                                                            direction:MTContentTransitionDirectionForward
                                                           completion:nil]) {
            return;
        }
        if ([[self searchController] isSearchActive] || [activeListViewController hasActiveSearch]) {
            [[self searchController] refreshForListViewController:activeListViewController];
        }
        [self updateClearButtonState];
        if ([self activeHistoryContentView] != [self contentViewForHistoryKey:[self effectiveActiveHistoryKey]]) {
            [self updateContentState];
        }
    }
}

- (void)handleHistoryChanged {
    [[self historyController] handleHistoryChanged];
}

- (nullable NSString *)historyKeyForInitialViewMode {
    switch ([self initialViewMode]) {
    case kMTInitialViewModeFavorites:
        return kMTHistoryKeyFavorites;
    case kMTInitialViewModeHistory:
        return kMTHistoryKeyHistory;
    case kMTInitialViewModePreviousSelection:
        return nil;
    }
    return nil;
}

- (void)reloadTableViewForHistoryKey:(NSString *)historyKey
              animatingTopInsertions:(BOOL)animatingTopInsertions
                          completion:(void (^)(MTHistoryListView *tableView))completion {
    [[self historyController] reloadTableViewForHistoryKey:historyKey
                                    animatingTopInsertions:animatingTopInsertions
                                                completion:completion];
}

- (void)reloadTableViewForHistoryKey:(NSString *)historyKey
                          completion:(void (^)(MTHistoryListView *tableView))completion {
    [[self historyController] reloadTableViewForHistoryKey:historyKey completion:completion];
}

#pragma mark - Clear Confirmation

- (void)showClearConfirmationForHistoryKey:(NSString *)historyKey {
    [self showClearConfirmationForHistoryKey:historyKey imagesOnly:NO];
}

- (void)showClearConfirmationForHistoryKey:(NSString *)historyKey imagesOnly:(BOOL)imagesOnly {
    [[self historyController] setActiveHistoryKey:historyKey];
    [self setClearConfirmationHistoryKey:historyKey];
    [[self clearConfirmationViewController] beginWithHistoryKey:historyKey imagesOnly:imagesOnly];
    [[[self clearConfirmationViewController] confirmationView]
        setKeyboardBottomInset:[[self searchController] keyboardBottomInset]];
    [[[[self mainView] headerView] trailingButton] setHidden:YES];

    [[self mainView]
        showContentView:[[self clearConfirmationViewController] confirmationView]
        hideContentView:[self activeHistoryContentView]
                  title:[self titleForContentView:[[self clearConfirmationViewController] confirmationView]]
              direction:MTContentTransitionDirectionModalPresenting];
}

- (void)finishHidingClearConfirmationForHistoryKey:(NSString *)historyKey {
    [self setClearConfirmationHistoryKey:nil];
    [self updateClearButtonState];
    UIView *contentView = [self contentViewForHistoryKey:historyKey];
    [self prepareHistoryListForDisplayIfNeededForHistoryKey:historyKey contentView:contentView];
    [[self mainView] showContentView:contentView
                     hideContentView:[[self clearConfirmationViewController] confirmationView]
                               title:[self titleForContentView:contentView]
                           direction:MTContentTransitionDirectionModalDismissing];
}

- (void)hideClearConfirmationWithReload:(BOOL)reload {
    [[[self mainView] headerView] setHistorySwitcherVisible:YES animated:NO];
    [self updateFavoritesButtonForHistoryKey:[self effectiveActiveHistoryKey]];
    if ([[[self clearConfirmationViewController] confirmationView] isHidden] || ![self clearConfirmationHistoryKey]) {
        return;
    }

    NSString *historyKey = [self clearConfirmationHistoryKey];
    if (reload) {
        BOOL imagesOnly = [[self clearConfirmationViewController] isImagesOnly];
        if (imagesOnly) {

            [self markHistoryKeyDirty:historyKey];
        } else {
            [[self listViewControllerForHistoryKey:historyKey] clearItems];
            [self markHistoryKeyLoaded:historyKey];
        }
        if ([[self effectiveActiveHistoryKey] isEqualToString:historyKey]) {
            [self setClearConfirmationHistoryKey:nil];
            [self updateClearButtonState];
            if (!imagesOnly &&
                [self cancelSearchForEmptyActiveHistoryIfNeededHidingView:[[self clearConfirmationViewController]
                                                                              confirmationView]
                                                                direction:MTContentTransitionDirectionModalDismissing
                                                               completion:nil]) {
                return;
            }
            if (imagesOnly) {
                [self reloadTableViewForHistoryKey:historyKey
                            animatingTopInsertions:NO
                                        completion:^(MTHistoryListView *tableView) {
                                          (void)tableView;
                                        }];
            }
            [[self searchController] refreshForListViewController:[self activeListViewController]];
        }
    }
    [self finishHidingClearConfirmationForHistoryKey:historyKey];
}

- (void)resetClearConfirmationIfNeeded {
    if (![self clearConfirmationHistoryKey]) {
        return;
    }

    [[[self clearConfirmationViewController] confirmationView] setHidden:YES];
    [[[self clearConfirmationViewController] confirmationView] setAlpha:1];
    [[[self clearConfirmationViewController] confirmationView] setTransform:CGAffineTransformIdentity];
    [self setHistoryContentVisibleForKey:[self clearConfirmationHistoryKey]];
    [self setClearConfirmationHistoryKey:nil];
    [self updateClearButtonState];
}

- (BOOL)isShowingClearConfirmation {
    return [self clearConfirmationHistoryKey] && ![[[self clearConfirmationViewController] confirmationView] isHidden];
}

#pragma mark - Content State

- (void)updateClearButtonState {
    [[[[self mainView] headerView] trailingButton] setHidden:YES];
    NSUInteger itemCount = [self storageError] ? 0 : [[[self activeListViewController] items] count];
    [[self mainView] setClearButtonEnabledForItemCount:itemCount];
}

- (void)showStorageError:(NSError *)error {
    if (!error) {
        return;
    }

    [self setStorageError:error];
    [[self storageErrorView] updateWithStorageError:error];
    [[self storageErrorView] setKeyboardBottomInset:[[self searchController] keyboardBottomInset]];
    [self updateClearButtonState];

    if ([self isHidden]) {
        return;
    }

    UIView *viewToHide = [self activeHistoryContentView];
    UIView *viewToShow = [self storageErrorView];
    if (viewToHide == viewToShow) {
        [[self mainView] setTitleText:[self titleForContentView:viewToShow]];
        return;
    }
    [[self mainView] showContentView:viewToShow
                     hideContentView:viewToHide
                               title:[self titleForContentView:viewToShow]
                           direction:MTContentTransitionDirectionForward];
}

#pragma mark - Transient Content

- (BOOL)isNoteEditing {
    return [self noteEditingItem] != nil || ![[[self noteEditorViewController] noteEditorView] isHidden];
}

- (BOOL)isPreviewTextEditing {
    return [[self textEditorViewController] isEditing] || ![[[self textEditorViewController] textEditorView] isHidden];
}

- (BOOL)isEditingAnyContent {
    return [self isNoteEditing] || [self isPreviewTextEditing];
}

- (BOOL)isPreviewActive {
    return ![[[self previewViewController] previewView] isHidden] || [[self previewViewController] previewItem] != nil;
}

- (BOOL)isWordSelectionActive {
    return ![[[self wordSelectionViewController] view] isHidden] ||
           [[self wordSelectionViewController] sourceItem] != nil;
}

- (UIView *)activeTransientContentViewForEdgeBackGesture {
    MTPreviewView *previewView = [[self previewViewController] previewView];
    if (![previewView isHidden] && [[self previewViewController] previewItem]) {
        return previewView;
    }

    UIView *wordSelectionView = [[self wordSelectionViewController] view];
    if (![wordSelectionView isHidden] && [[self wordSelectionViewController] sourceItem]) {
        return wordSelectionView;
    }

    return nil;
}

- (BOOL)canBeginTransientEdgeBackGestureRecognizer:(UIScreenEdgePanGestureRecognizer *)recognizer {
    if ([self isHidden] || [self isEditingAnyContent] || [[self mainView] isAnimating] ||
        [[self panelPresentationController] isAnimating]) {
        return NO;
    }

    UIView *sourceView = [self activeSourceContentView];
    UIView *contentView = [self activeTransientContentViewForEdgeBackGesture];
    if (!sourceView || !contentView) {
        return NO;
    }

    CGPoint velocity = [recognizer velocityInView:[self mainView]];
    if (velocity.x <= 0 || fabs(velocity.x) <= fabs(velocity.y) * kMTTransientEdgeBackHorizontalDominance) {
        return NO;
    }

    if (contentView == [[self previewViewController] previewView] &&
        ![[[self previewViewController] previewView] canBeginEdgeBackGesture]) {
        return NO;
    }

    return YES;
}

- (CGFloat)progressForTransientEdgeBackGestureRecognizer:(UIScreenEdgePanGestureRecognizer *)recognizer {
    CGFloat width = MAX(CGRectGetWidth([[[self mainView] contentContainerView] bounds]), 1);
    CGFloat progress = [recognizer translationInView:[self mainView]].x / width;
    return MIN(MAX(progress, 0), 1);
}

- (NSTimeInterval)transientEdgeBackAnimationDurationWithProgress:(CGFloat)progress finishing:(BOOL)finishing {
    CGFloat remainingProgress = finishing ? 1 - progress : progress;
    NSTimeInterval duration = kMTTransientEdgeBackMaximumAnimationDuration * remainingProgress;
    return MIN(MAX(duration, kMTTransientEdgeBackMinimumAnimationDuration),
               kMTTransientEdgeBackMaximumAnimationDuration);
}

- (void)resetInteractiveTransientReturnState {
    [self setInteractiveTransientReturnSourceView:nil];
    [self setInteractiveTransientReturnContentView:nil];
    [self setInteractiveTransientReturnWasPreview:NO];
    [self setDidRestoreSearchDuringInteractiveTransientReturn:NO];
}

- (void)clearSearchAfterTransientContentState {
    [self setRestoresSearchFirstResponderAfterTransientContent:NO];
    [self setHasSearchContentOffsetBeforeTransientContent:NO];
}

- (BOOL)restoreSearchAfterTransientContentIfNeededClearingState:(BOOL)clearsState {
    BOOL didRestore = NO;
    if ([[self searchController] isSearchActive]) {
        CGPoint targetContentOffset = [[[self activeListViewController] tableView] contentOffset];
        if ([self hasSearchContentOffsetBeforeTransientContent]) {
            targetContentOffset = [self searchContentOffsetBeforeTransientContent];
        }
        [[self searchController]
            refreshAfterTransientContentForListViewController:[self activeListViewController]
                                       restoresFirstResponder:[self restoresSearchFirstResponderAfterTransientContent]
                                          targetContentOffset:targetContentOffset];
        didRestore = YES;
    }

    if (clearsState) {
        [self clearSearchAfterTransientContentState];
    }
    return didRestore;
}

- (void)beginInteractiveTransientReturnWithGestureRecognizer:(UIScreenEdgePanGestureRecognizer *)recognizer {
    UIView *sourceView = [self activeSourceContentView];
    UIView *contentView = [self activeTransientContentViewForEdgeBackGesture];
    if (!sourceView || !contentView) {
        return;
    }

    CGFloat progress = [self progressForTransientEdgeBackGestureRecognizer:recognizer];
    UIView *mainHeaderView = [[self mainView] headerView];

    [self setInteractiveTransientReturnSourceView:sourceView];
    [self setInteractiveTransientReturnContentView:contentView];
    [self setInteractiveTransientReturnWasPreview:(contentView == [[self previewViewController] previewView])];
    [[self mainView] beginInteractiveBackwardContentTransitionToView:sourceView
                                                 alongsideViewToShow:mainHeaderView
                                                     hideContentView:contentView];
    [[self mainView] updateInteractiveBackwardContentTransitionToView:sourceView
                                                  alongsideViewToShow:mainHeaderView
                                                      hideContentView:contentView
                                                             progress:progress];
    [self setDidRestoreSearchDuringInteractiveTransientReturn:
              [self restoreSearchAfterTransientContentIfNeededClearingState:NO]];
}

- (void)updateInteractiveTransientReturnWithGestureRecognizer:(UIScreenEdgePanGestureRecognizer *)recognizer {
    UIView *sourceView = [self interactiveTransientReturnSourceView];
    UIView *contentView = [self interactiveTransientReturnContentView];
    if (!sourceView || !contentView) {
        return;
    }

    CGFloat progress = [self progressForTransientEdgeBackGestureRecognizer:recognizer];
    [[self mainView] updateInteractiveBackwardContentTransitionToView:sourceView
                                                  alongsideViewToShow:[[self mainView] headerView]
                                                      hideContentView:contentView
                                                             progress:progress];
}

- (void)finishInteractiveTransientReturnWithDuration:(NSTimeInterval)duration {
    UIView *sourceView = [self interactiveTransientReturnSourceView];
    UIView *contentView = [self interactiveTransientReturnContentView];
    if (!sourceView || !contentView) {
        [self resetInteractiveTransientReturnState];
        return;
    }

    BOOL wasPreview = [self interactiveTransientReturnWasPreview];
    BOOL didRestoreSearch = [self didRestoreSearchDuringInteractiveTransientReturn];
    if (didRestoreSearch) {
        [self clearSearchAfterTransientContentState];
    }
    [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleSoft];
    UIView *mainHeaderView = [[self mainView] headerView];

    [[self mainView] finishInteractiveBackwardContentTransitionToView:sourceView
        alongsideViewToShow:mainHeaderView
        hideContentView:contentView
        duration:duration
        alongsideAnimations:^{
          if (!didRestoreSearch) {
              [self restoreSearchAfterTransientContentIfNeededClearingState:YES];
          }
        }
        completion:^{
          if (wasPreview) {
              [[self previewViewController] hidePreview];
          } else {
              [[self wordSelectionViewController] hideWordSelection];
          }
          [self setActiveSourceContentView:nil];
          [self resetInteractiveTransientReturnState];
        }];
}

- (void)cancelInteractiveTransientReturnWithDuration:(NSTimeInterval)duration {
    UIView *sourceView = [self interactiveTransientReturnSourceView];
    UIView *contentView = [self interactiveTransientReturnContentView];
    if (!sourceView || !contentView) {
        [self resetInteractiveTransientReturnState];
        return;
    }

    if ([self didRestoreSearchDuringInteractiveTransientReturn]) {
        [[self searchController] resignSearchFirstResponder];
    }

    [[self mainView] cancelInteractiveBackwardContentTransitionToView:sourceView
                                                  alongsideViewToShow:[[self mainView] headerView]
                                                      hideContentView:contentView
                                                             duration:duration
                                                           completion:^{
                                                             [self resetInteractiveTransientReturnState];
                                                           }];
}

- (void)finishOrCancelInteractiveTransientReturnWithGestureRecognizer:(UIScreenEdgePanGestureRecognizer *)recognizer {
    if ([recognizer state] == UIGestureRecognizerStateCancelled ||
        [recognizer state] == UIGestureRecognizerStateFailed) {
        CGFloat progress = [self progressForTransientEdgeBackGestureRecognizer:recognizer];
        [self cancelInteractiveTransientReturnWithDuration:[self transientEdgeBackAnimationDurationWithProgress:progress
                                                                                                      finishing:NO]];
        return;
    }

    CGFloat progress = [self progressForTransientEdgeBackGestureRecognizer:recognizer];
    CGPoint velocity = [recognizer velocityInView:[self mainView]];
    BOOL shouldFinish = progress >= kMTTransientEdgeBackCompletionProgress ||
                        velocity.x >= kMTTransientEdgeBackCompletionVelocity;
    NSTimeInterval duration = [self transientEdgeBackAnimationDurationWithProgress:progress finishing:shouldFinish];
    if (shouldFinish) {
        [self finishInteractiveTransientReturnWithDuration:duration];
    } else {
        [self cancelInteractiveTransientReturnWithDuration:duration];
    }
}

- (void)handleTransientEdgeBackGestureRecognizer:(UIScreenEdgePanGestureRecognizer *)recognizer {
    switch ([recognizer state]) {
    case UIGestureRecognizerStateBegan:
        [self beginInteractiveTransientReturnWithGestureRecognizer:recognizer];
        break;
    case UIGestureRecognizerStateChanged:
        [self updateInteractiveTransientReturnWithGestureRecognizer:recognizer];
        break;
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
        [self finishOrCancelInteractiveTransientReturnWithGestureRecognizer:recognizer];
        break;
    default:
        break;
    }
}

- (void)restoreActiveSourceContentView {
    UIView *sourceContentView = [self activeSourceContentView];
    if (!sourceContentView) {
        return;
    }

    [sourceContentView setHidden:NO];
    [sourceContentView setAlpha:1];
    [sourceContentView setTransform:CGAffineTransformIdentity];
}

- (void)refreshSearchAfterEndingTransientContentIfNeeded {
    [self restoreSearchAfterTransientContentIfNeededClearingState:YES];
}

#pragma mark - Header State

- (void)updateFavoritesButtonForHistoryKey:(NSString *)historyKey {
    BOOL showingFavorites = [historyKey isEqualToString:kMTHistoryKeyFavorites];
    MTHeaderView *headerView = [[self mainView] headerView];
    [headerView setHistorySwitcherVisible:YES animated:NO];
    [headerView setSelectedHistorySegmentIndex:showingFavorites ? 1 : 0];
    [headerView updateStyleForButton:[headerView leadingButton]
                       withImageName:@"list.bullet"
                           imageSize:kMTFavoritesButtonImageSize
                           tintColor:[UIColor labelColor]];
    [self updateFavoritesFilterMenuForHistoryKey:historyKey];
}

- (void)updateFavoritesFilterMenuForHistoryKey:(NSString *)historyKey {
    UIButton *leadingButton = [[[self mainView] headerView] leadingButton];
    [leadingButton setShowsMenuAsPrimaryAction:YES];
    if ([historyKey isEqualToString:kMTHistoryKeyFavorites]) {
        [leadingButton setMenu:[self favoritesFilterMenu]];
    } else {
        [leadingButton setMenu:[self clipboardClearMenu]];
    }
}

- (UIMenu *)favoritesFilterMenu {
    NSBundle *bundle = [MTPasteboardManager localizationBundle];
    MTSearchController *searchController = [self searchController];
    __weak typeof(self) weakSelf = self;

    UIAction *(^makeAction)(NSString *, BOOL, void (^)(MTSearchController *, BOOL)) =
        ^UIAction *(NSString *title, BOOL enabled, void (^apply)(MTSearchController *, BOOL)) {
          UIImage *image = [UIImage systemImageNamed:enabled ? @"eye" : @"eye.slash"];
          return [UIAction actionWithTitle:title
                                     image:image
                                identifier:nil
                                   handler:^(__kindof UIAction *_Nonnull unusedAction) {
                                     (void)unusedAction;
                                     __strong typeof(weakSelf) strongSelf = weakSelf;
                                     if (!strongSelf) {
                                         return;
                                     }
                                     apply([strongSelf searchController], !enabled);
                                     [strongSelf updateFavoritesFilterMenuForHistoryKey:
                                                     [strongSelf effectiveActiveHistoryKey]];
                                   }];
        };

    UIAction *categories = makeAction(
        [bundle localizedStringForKey:@"Categories" value:nil table:@"Tweak"],
        [searchController favoritesFilterShowsCategories],
        ^(MTSearchController *controller, BOOL value) { [controller setFavoritesFilterShowsCategories:value]; });
    UIAction *apps = makeAction(
        [bundle localizedStringForKey:@"Applications" value:nil table:@"Tweak"],
        [searchController favoritesFilterShowsApps],
        ^(MTSearchController *controller, BOOL value) { [controller setFavoritesFilterShowsApps:value]; });

    return [UIMenu menuWithTitle:@""
                        children:@[ [self galleryModeActionForHistoryKey:kMTHistoryKeyFavorites], categories,
                                    apps ]];
}

- (UIAction *)galleryModeActionForHistoryKey:(NSString *)historyKey {
    NSBundle *bundle = [MTPasteboardManager localizationBundle];
    BOOL isFavorites = [historyKey isEqualToString:kMTHistoryKeyFavorites];
    BOOL enabled = isFavorites ? [self isFavoritesGalleryModeEnabled] : [self isClipboardGalleryModeEnabled];
    __weak typeof(self) weakSelf = self;
    UIAction *action = [UIAction
        actionWithTitle:[bundle localizedStringForKey:@"Gallery View" value:nil table:@"Tweak"]
                  image:[UIImage systemImageNamed:enabled ? @"rectangle.grid.2x2.fill" : @"rectangle.grid.2x2"]
             identifier:nil
                handler:^(__kindof UIAction *_Nonnull unusedAction) {
                  (void)unusedAction;
                  __strong typeof(weakSelf) strongSelf = weakSelf;
                  if (!strongSelf) {
                      return;
                  }
                  NSUserDefaults *preferences =
                      [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
                  if (isFavorites) {
                      BOOL newValue = ![strongSelf isFavoritesGalleryModeEnabled];
                      [strongSelf setFavoritesGalleryModeEnabled:newValue];
                      [[strongSelf favoritesListViewController] setGalleryModeEnabled:newValue];
                      [preferences setBool:newValue forKey:kMTPreferenceKeyFavoritesGalleryModeEnabled];
                  } else {
                      BOOL newValue = ![strongSelf isClipboardGalleryModeEnabled];
                      [strongSelf setClipboardGalleryModeEnabled:newValue];
                      [[strongSelf historyListViewController] setGalleryModeEnabled:newValue];
                      [preferences setBool:newValue forKey:kMTPreferenceKeyClipboardGalleryModeEnabled];
                  }
                  [strongSelf updateFavoritesFilterMenuForHistoryKey:[strongSelf effectiveActiveHistoryKey]];
                }];
    [action setState:enabled ? UIMenuElementStateOn : UIMenuElementStateOff];
    return action;
}

- (UIMenu *)clipboardClearMenu {
    NSBundle *bundle = [MTPasteboardManager localizationBundle];
    __weak typeof(self) weakSelf = self;

    UIAction *clearClipboard =
        [UIAction actionWithTitle:[bundle localizedStringForKey:@"Clear Clipboard" value:nil table:@"Tweak"]
                            image:[UIImage systemImageNamed:@"trash"]
                       identifier:nil
                          handler:^(__kindof UIAction *_Nonnull unusedAction) {
                            (void)unusedAction;
                            [weakSelf requestClearClipboardImagesOnly:NO];
                          }];
    [clearClipboard setAttributes:UIMenuElementAttributesDestructive];

    UIAction *clearImages =
        [UIAction actionWithTitle:[bundle localizedStringForKey:@"Clear Images" value:nil table:@"Tweak"]
                            image:[UIImage systemImageNamed:@"photo"]
                       identifier:nil
                          handler:^(__kindof UIAction *_Nonnull unusedAction) {
                            (void)unusedAction;
                            [weakSelf requestClearClipboardImagesOnly:YES];
                          }];

    return [UIMenu menuWithTitle:@""
                        children:@[ [self galleryModeActionForHistoryKey:kMTHistoryKeyHistory], clearClipboard,
                                    clearImages ]];
}

- (void)requestClearClipboardImagesOnly:(BOOL)imagesOnly {
    if ([[self panelPresentationController] isAnimating] || ![[[self previewViewController] previewView] isHidden] ||
        ![[[self wordSelectionViewController] view] isHidden] || [self isShowingClearConfirmation]) {
        return;
    }
    [self showClearConfirmationForHistoryKey:kMTHistoryKeyHistory imagesOnly:imagesOnly];
    [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleMedium];
}

- (void)dismissLeadingButtonMenu {
    UIButton *leadingButton = [[[self mainView] headerView] leadingButton];
    SEL dismissMenuSelector = NSSelectorFromString(@"dismissMenu");
    if ([leadingButton respondsToSelector:dismissMenuSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [leadingButton performSelector:dismissMenuSelector];
#pragma clang diagnostic pop
    }
}


- (void)restoreHistoryHeaderIconForHistoryKey:(NSString *)historyKey {
    UIButton *favoritesButton = [[[self mainView] headerView] leadingButton];
    [favoritesButton setHidden:NO];
    [favoritesButton setEnabled:YES];
    [favoritesButton setUserInteractionEnabled:YES];
    [[[favoritesButton imageView] layer] setCornerRadius:0];
    [[favoritesButton imageView] setClipsToBounds:NO];
    [self updateFavoritesButtonForHistoryKey:historyKey];
}

#pragma mark - Content Presentation

- (void)showContentView:(UIView *)viewToShow
        hideContentView:(UIView *)viewToHide
              direction:(MTContentTransitionDirection)direction
             completion:(nullable void (^)(void))completion {
    [[self mainView] showContentView:viewToShow
                     hideContentView:viewToHide
                               title:[self titleForContentView:viewToShow]
                           direction:direction
                          completion:completion];
}

- (BOOL)cancelSearchForEmptyActiveHistoryIfNeededHidingView:(UIView *)viewToHide
                                                  direction:(MTContentTransitionDirection)direction
                                                 completion:(void (^)(void))completion {
    if (![[self searchController] isSearchActive] || [[[self activeListViewController] items] count] > 0) {
        return NO;
    }

    [self updateClearButtonState];
    UIView *viewToShow = [self contentViewForHistoryKey:[self effectiveActiveHistoryKey]];
    if (viewToShow == viewToHide) {
        [[self searchController] cancelSearchWithCompletion:completion];
        return YES;
    }

    [[self mainView] prepareContentTransitionToView:viewToShow
                                    hideContentView:viewToHide
                                              title:[self titleForContentView:viewToShow]
                                          direction:direction];
    [[self searchController]
        cancelSearchWithAnimations:^{
          [[self mainView] applyPreparedContentTransitionToView:viewToShow
                                                hideContentView:viewToHide
                                                      direction:direction];
        }
        completion:^{
          [[self mainView] completePreparedContentTransitionHidingView:viewToHide completion:completion];
        }];
    return YES;
}

- (void)updateContentState {

    if (![self shouldDeferHistoryPresentationUpdates]) {
        if ([self cancelSearchForEmptyActiveHistoryIfNeededHidingView:[self activeHistoryContentView]
                                                            direction:MTContentTransitionDirectionForward
                                                           completion:nil]) {
            return;
        }

        UIView *viewToHide = [self activeHistoryContentView];
        UIView *viewToShow = [self contentViewForHistoryKey:[self effectiveActiveHistoryKey]];

        if (viewToShow != viewToHide) {
            [self prepareHistoryListForDisplayIfNeededForHistoryKey:[self effectiveActiveHistoryKey]
                                                        contentView:viewToShow];
            [[self mainView] showContentView:viewToShow
                             hideContentView:viewToHide
                                       title:[self titleForContentView:viewToShow]
                                   direction:MTContentTransitionDirectionForward];
        } else {
            [[self mainView] setTitleText:[self titleForContentView:viewToShow]];
        }
    }

    [self updateClearButtonState];
}

- (BOOL)shouldDeferHistoryPresentationUpdates {
    return [self isEditingAnyContent] || [self isShowingClearConfirmation] || [self isPreviewActive] ||
           [self isWordSelectionActive];
}


#pragma mark - Actions

- (void)handleHistorySegmentedControlChanged:(UISegmentedControl *)sender {
    if (!sender) {
        return;
    }

    BOOL wantsFavorites = [sender selectedSegmentIndex] == 1;
    NSString *targetKey = wantsFavorites ? kMTHistoryKeyFavorites : kMTHistoryKeyHistory;
    NSString *currentKey = [self effectiveActiveHistoryKey];
    if ([currentKey isEqualToString:targetKey]) {
        [self updateFavoritesButtonForHistoryKey:currentKey];
        return;
    }

    if ([[self panelPresentationController] isAnimating]) {
        [self updateFavoritesButtonForHistoryKey:currentKey];
        return;
    }

    [self switchToHistoryKey:targetKey animated:YES];
}

- (void)switchToHistoryKey:(NSString *)targetKey animated:(BOOL)animated {
    if ([targetKey length] == 0) {
        return;
    }
    if ([[self panelPresentationController] isAnimating]) {
        [self updateFavoritesButtonForHistoryKey:[self effectiveActiveHistoryKey]];
        return;
    }
    if ([self isShowingClearConfirmation]) {
        [self resetClearConfirmationIfNeeded];
    }

    NSString *historyKey = [self effectiveActiveHistoryKey];
    if ([historyKey isEqualToString:targetKey]) {
        [self updateFavoritesButtonForHistoryKey:targetKey];
        return;
    }

    BOOL targetIsFavorites = [targetKey isEqualToString:kMTHistoryKeyFavorites];
    UIView *viewToHide = [self activeHistoryContentView];
    MTContentTransitionDirection direction =
        animated ? (targetIsFavorites ? MTContentTransitionDirectionSiblingForward
                                      : MTContentTransitionDirectionSiblingBackward)
                 : MTContentTransitionDirectionForward;

    __weak typeof(self) weakSelf = self;
    [self reloadTableViewForHistoryKey:targetKey
                            completion:^(MTHistoryListView *targetTableView) {
                              __strong typeof(weakSelf) strongSelf = weakSelf;
                              (void)targetTableView;
                              if (!strongSelf) {
                                  return;
                              }
                              if (![[strongSelf effectiveActiveHistoryKey] isEqualToString:historyKey] ||
                                  [[strongSelf panelPresentationController] isAnimating]) {
                                  [strongSelf updateFavoritesButtonForHistoryKey:[strongSelf effectiveActiveHistoryKey]];
                                  return;
                              }

                              [[strongSelf historyController] setActiveHistoryKey:targetKey];
                              [[strongSelf searchController]
                                  attachToListViewController:[strongSelf listViewControllerForHistoryKey:targetKey]
                                              hidesSearchBar:![[strongSelf searchController] isSearchActive]];
                              [[strongSelf searchController]
                                  refreshForListViewController:[strongSelf activeListViewController]];
                              [strongSelf updateClearButtonState];

                              UIView *viewToShow = [strongSelf contentViewForHistoryKey:targetKey];
                              [strongSelf prepareHistoryListForDisplayIfNeededForHistoryKey:targetKey
                                                                                contentView:viewToShow];
                              if (viewToShow != viewToHide) {
                                  [[strongSelf mainView] showContentView:viewToShow
                                                         hideContentView:viewToHide
                                                                   title:[strongSelf titleForContentView:viewToShow]
                                                               direction:direction];
                              } else {
                                  [[strongSelf mainView] setTitleText:[strongSelf titleForContentView:viewToShow]];
                              }

                              [strongSelf updateFavoritesButtonForHistoryKey:targetKey];
                              [[strongSelf panelPresentationController]
                                  triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleSoft];
                            }];
}

- (void)handleFavoritesButtonPressed {

    if ([[self panelPresentationController] isAnimating]) {
        return;
    }

    if ([self isShowingClearConfirmation]) {
        [self hideClearConfirmationWithReload:NO];
        [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleSoft];
        return;
    }

    NSString *historyKey = [self effectiveActiveHistoryKey];
    BOOL showingFavorites = [historyKey isEqualToString:kMTHistoryKeyFavorites];
    NSString *targetKey = showingFavorites ? kMTHistoryKeyHistory : kMTHistoryKeyFavorites;
    [self switchToHistoryKey:targetKey animated:YES];
}

- (void)handleTransientBackButtonPressed {
    if ([self isNoteEditing] || [[self panelPresentationController] isAnimating] || [[self mainView] isAnimating]) {
        return;
    }

    if (![[[self textEditorViewController] textEditorView] isHidden] && [[self textEditorViewController] isEditing]) {
        [self textEditorViewControllerDidRequestCancel:[self textEditorViewController]];
        return;
    }

    if (![[[self previewViewController] previewView] isHidden]) {
        [self hidePreview];
        [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleSoft];
        return;
    }

    if (![[[self wordSelectionViewController] view] isHidden]) {
        [self hideWordSelection];
        [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleSoft];
    }
}

- (void)handlePreviewActionButtonPressed {
    if (![[[self wordSelectionViewController] view] isHidden]) {
        [[self wordSelectionViewController] handleActionButtonWithAutomaticallyPaste:[self automaticallyPaste]];
        return;
    }

    if (![[[self previewViewController] previewView] isHidden]) {
        [[self previewViewController] handleActionButtonWithCompletion:^(BOOL success) {
          if (success) {
              [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleMedium];
              [[self panelPresentationController] prepareStandardDismissAnimation];
              [self hideAfterDirectPaste];
          }
        }];
    }
}

- (void)handleClearButtonPressed {
    if ([[self panelPresentationController] isAnimating] || ![[[self previewViewController] previewView] isHidden] ||
        ![[[self wordSelectionViewController] view] isHidden] || [self isShowingClearConfirmation] ||
        NO) {
        return;
    }

    [self showClearConfirmationForHistoryKey:[self effectiveActiveHistoryKey]];
    [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleMedium];
}

- (void)handleTitleTapControlPressed {
    if ([[self panelPresentationController] isAnimating] || [[self mainView] isAnimating]) {
        return;
    }

    if (![[[self wordSelectionViewController] view] isHidden]) {
        [[self wordSelectionViewController] handleTextActionButtonPressed];
        return;
    }

    if (![[[self previewViewController] previewView] isHidden]) {
        [[self previewViewController] scrollToTopAnimated:YES];
        return;
    }

    [[self activeListViewController] scrollToTopAnimated:YES];
}

#pragma mark - Item Handling

- (void)handlePasteboardItemDictionary:(NSDictionary<NSString *, id> *)dictionary
                   movedFromHistoryKey:(NSString *)sourceHistoryKey
                          toHistoryKey:(NSString *)destinationHistoryKey {
    [[self historyController] handlePasteboardItemDictionary:dictionary
                                         movedFromHistoryKey:sourceHistoryKey
                                                toHistoryKey:destinationHistoryKey];
}

#pragma mark - Note Editing

- (CGRect)noteEditingPanelFrameForKeyboardBottomInset:(CGFloat)keyboardBottomInset {
    UIView *mainView = [self mainView];
    UIView *superview = [mainView superview];
    if (!superview) {
        return [mainView frame];
    }

    CGRect bounds = [superview bounds];
    CGRect currentFrame = [mainView frame];
    CGFloat inset = kMTPanelFloatingInset;

    // Preserve floating-card width/x. Never expand note editing to full host bounds.
    CGFloat width = CGRectGetWidth(currentFrame);
    CGFloat x = CGRectGetMinX(currentFrame);
    if (width <= 0.0 || width >= CGRectGetWidth(bounds) - 1.0) {
        width = MIN(kMTPanelFloatingMaxWidth, CGRectGetWidth(bounds) - inset * 2.0);
        width = MAX(width, 280.0);
        x = CGRectGetMidX(bounds) - width * 0.5;
    }

    CGFloat contentHeight = [[[self noteEditorViewController] noteEditorView] editingContentHeight];
    CGFloat preferredHeight = contentHeight + 12.0;
    CGFloat availableBottom = CGRectGetMaxY(bounds) - MAX(keyboardBottomInset, 0.0) - inset;
    CGFloat maximumHeight = MAX(availableBottom - inset, 0.0);
    CGFloat targetHeight = MIN(preferredHeight, maximumHeight);
    CGFloat y = availableBottom - targetHeight;
    if (y < inset) {
        y = inset;
        targetHeight = MIN(preferredHeight, MAX(CGRectGetHeight(bounds) - inset * 2.0, 0.0));
    }
    return CGRectMake(x, y, width, targetHeight);
}

- (BOOL)canBeginNoteEditing {
    return ![self isNoteEditing] && ![[self mainView] isAnimating] && ![[self panelPresentationController] isAnimating];
}

- (NSUInteger)prepareNoteEditingSessionForItem:(MTPasteboardItem *)item
                            listViewController:(MTHistoryListViewController *)listViewController
                              presentationCell:(MTTableViewCell *)presentationCell
                                    cellHeight:(CGFloat)cellHeight
                           keyboardBottomInset:(CGFloat)keyboardBottomInset
                                        origin:(MTNoteEditingOrigin)origin {
    [self setNoteEditingOrigin:origin];
    [self setFinishingNoteEditing:NO];
    [self setNoteEditingItem:item];
    [self setNoteEditingHistoryKey:[listViewController historyKey]];
    [self setNoteEditingSourceListViewController:listViewController];
    NSUInteger requestIdentifier = [self noteEditingRequestIdentifier] + 1;
    [self setNoteEditingRequestIdentifier:requestIdentifier];
    [self clearExternalHideCoordinator];

    MTNoteEditorView *noteEditorView = [[self noteEditorViewController] noteEditorView];
    [noteEditorView setCompactLayout:[self presentationMode] == MTPanelPresentationModeCompactLandscapeFullscreen];
    [[self noteEditorViewController] prepareForItem:item
                                   presentationCell:presentationCell
                                         cellHeight:cellHeight
                                keyboardBottomInset:keyboardBottomInset];
    return requestIdentifier;
}

- (void)beginNoteEditingForItem:(MTPasteboardItem *)item
             listViewController:(MTHistoryListViewController *)listViewController
               presentationCell:(MTTableViewCell *)presentationCell
                     sourceCell:(MTTableViewCell *)sourceCell {
    if (!item || !listViewController || !presentationCell || ![self canBeginNoteEditing]) {
        return;
    }

    UIView *mainView = [self mainView];
    BOOL beganFromSearch = [[self searchController] isSearchActive];
    UIWindow *searchSourceWindow = beganFromSearch ? [sourceCell window] : nil;
    BOOL hasSearchSourceFrame = searchSourceWindow != nil;
    CGRect searchSourceFrameInWindow =
        hasSearchSourceFrame ? [sourceCell convertRect:[sourceCell bounds] toView:searchSourceWindow] : CGRectNull;
    CGFloat keyboardBottomInset = [[self noteEditorViewController] visibleKeyboardBottomInset];
    [listViewController setCellPresentationHidden:YES forItem:item];
    [self clearSearchAfterTransientContentState];
    [self setNoteEditingBeganFromSearch:beganFromSearch];
    if (beganFromSearch) {
        [self setNoteEditingOriginalPanelFrame:[[self searchController] resetSearchStatePreservingContainerFrame]];
        sourceCell = [listViewController scrollItemToVisible:item];
        presentationCell = [listViewController presentationCellForItem:item];
    } else {
        [self setNoteEditingOriginalPanelFrame:[mainView frame]];
    }
    [self setNoteEditingKeyboardAnimationDuration:0.25];
    [self setNoteEditingKeyboardAnimationOptions:UIViewAnimationOptionCurveEaseInOut |
                                                 UIViewAnimationOptionBeginFromCurrentState |
                                                 UIViewAnimationOptionAllowUserInteraction];

    MTHistoryListView *sourceTableView = [listViewController tableView];
    BOOL keepsSearchHeaderHidden =
        beganFromSearch || ![sourceTableView isSearchHeaderExposedAtContentOffset:[sourceTableView contentOffset]];
    [self setNoteEditingKeepsSearchHeaderHidden:keepsSearchHeaderHidden];
    [self setActiveSourceContentView:sourceTableView];

    CGFloat cellHeight = CGRectGetHeight([sourceCell bounds]);
    if (cellHeight <= 0) {
        cellHeight = [[listViewController tableView] rowHeight];
    }
    NSUInteger requestIdentifier = [self prepareNoteEditingSessionForItem:item
                                                       listViewController:listViewController
                                                         presentationCell:presentationCell
                                                               cellHeight:cellHeight
                                                      keyboardBottomInset:keyboardBottomInset
                                                                   origin:MTNoteEditingOriginList];
    MTNoteEditorView *noteEditorView = [[self noteEditorViewController] noteEditorView];

    [[self mainView] layoutIfNeeded];
    [noteEditorView setHidden:NO];
    [noteEditorView setAlpha:1];
    [noteEditorView setAutomaticallyPositionsPreviewCell:NO];
    [noteEditorView layoutIfNeeded];

    CGRect targetPanelFrame = [self noteEditingPanelFrameForKeyboardBottomInset:keyboardBottomInset];

    BOOL usesSearchSourceFrame = hasSearchSourceFrame && [noteEditorView window] == searchSourceWindow;
    BOOL hasSourceFrame = usesSearchSourceFrame || (sourceCell && [sourceCell window]);
    CGRect sourceFrame = [noteEditorView targetPreviewCellFrame];
    if (usesSearchSourceFrame) {
        sourceFrame = [noteEditorView convertRect:searchSourceFrameInWindow fromView:searchSourceWindow];
    } else if (hasSourceFrame) {
        sourceFrame = [sourceCell convertRect:[sourceCell bounds] toView:noteEditorView];
    }
    [[noteEditorView previewCell] setFrame:sourceFrame];
    [[noteEditorView previewCell] setAlpha:hasSourceFrame ? 1 : 0];
    [[noteEditorView inputRowView] setAlpha:0];

    MTHeaderView *headerView = [[self mainView] headerView];
    [[self mainView] setAnimating:YES];
    [UIView animateWithDuration:0.3
        delay:0
        usingSpringWithDamping:1
        initialSpringVelocity:0
        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
        animations:^{
          [mainView setFrame:targetPanelFrame];
          [mainView layoutIfNeeded];
          [noteEditorView layoutIfNeeded];
          [headerView setAlpha:0];
          [sourceTableView setAlpha:0];
          [[noteEditorView previewCell] setFrame:[noteEditorView targetPreviewCellFrame]];
          [[noteEditorView previewCell] setAlpha:1];
          [[noteEditorView inputRowView] setAlpha:1];
              }
        completion:^(__unused BOOL finished) {
          [listViewController setCellPresentationHidden:NO forItem:item];
          if ([self noteEditingRequestIdentifier] != requestIdentifier || ![self isNoteEditing]) {
              return;
          }
          [headerView setHidden:YES];
          [sourceTableView setHidden:YES];
          [noteEditorView setAutomaticallyPositionsPreviewCell:YES];
          [noteEditorView setNeedsLayout];
          [[self mainView] setAnimating:NO];
          [[self searchController] resignSearchFirstResponder];
          [[self noteEditorViewController] beginEditing];
          [self executePendingExternalHideRequestIfReady];
        }];
    [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleMedium];
}

- (void)resetNoteEditingState {
    MTNoteEditorView *noteEditorView = [[self noteEditorViewController] noteEditorView];
    [noteEditorView setHidden:YES];
    [[self noteEditingSourceListViewController] setCellPresentationHidden:NO forItem:[self noteEditingItem]];
    [noteEditorView setAlpha:1];
    [noteEditorView setAutomaticallyPositionsPreviewCell:YES];
    [[noteEditorView inputRowView] setAlpha:1];
    [[self noteEditorViewController] reset];
    [self setNoteEditingItem:nil];
    [self setNoteEditingHistoryKey:nil];
    [self setNoteEditingSourceListViewController:nil];
    [self setNoteEditingBeganFromSearch:NO];
    [self setNoteEditingKeepsSearchHeaderHidden:NO];
    [self setFinishingNoteEditing:NO];
    [self setNoteEditingOriginalPanelFrame:CGRectZero];
    [self setNoteEditingOrigin:MTNoteEditingOriginNone];
    [self setNoteEditingRequestIdentifier:[self noteEditingRequestIdentifier] + 1];
}

- (void)animateNoteEditingReturnWithRequestIdentifier:(NSUInteger)requestIdentifier
                                   ensuresItemVisible:(BOOL)ensuresItemVisible
                                     targetPanelFrame:(CGRect)targetPanelFrame
                                             duration:(NSTimeInterval)duration
                                              options:(UIViewAnimationOptions)options {
    if ([self noteEditingRequestIdentifier] != requestIdentifier || ![self isNoteEditing] || [self isDismissingPanel]) {
        return;
    }

    UIView *sourceView = [self activeSourceContentView];
    MTHeaderView *headerView = [[self mainView] headerView];
    MTNoteEditorView *noteEditorView = [[self noteEditorViewController] noteEditorView];
    MTMainView *mainView = [self mainView];
    [sourceView setHidden:NO];
    [sourceView setAlpha:0];
    [headerView setHidden:NO];
    [headerView setAlpha:0];
    [noteEditorView setAutomaticallyPositionsPreviewCell:NO];

    MTHistoryListViewController *listViewController = [self noteEditingSourceListViewController];
    MTPasteboardItem *item = [self noteEditingItem];
    [listViewController setCellPresentationHidden:YES forItem:item];
    MTHistoryListView *tableView = [listViewController tableView];
    [mainView setAnimating:YES];

    duration = duration > 0 ? duration : 0.3;
    options |= UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    [UIView animateWithDuration:duration
        delay:0
        options:options
        animations:^{
          [mainView setFrame:targetPanelFrame];
          [mainView layoutIfNeeded];
          [UIView performWithoutAnimation:^{
            if (ensuresItemVisible) {
                [listViewController scrollItemToVisible:item];
            }
            if ([self noteEditingKeepsSearchHeaderHidden]) {
                [tableView restoreHiddenSearchHeaderOffsetWithoutAnimation];
            } else {
                [tableView layoutIfNeeded];
            }
          }];

          [sourceView setAlpha:1];
          [headerView setAlpha:1];
          [[noteEditorView inputRowView] setAlpha:0];
                MTTableViewCell *targetCell = [listViewController visibleCellForItem:item];
          if (targetCell && [targetCell window]) {
              [[noteEditorView previewCell] setFrame:[targetCell convertRect:[targetCell bounds]
                                                                      toView:noteEditorView]];
          } else {
              [[noteEditorView previewCell] setAlpha:0];
          }
        }
        completion:^(__unused BOOL finished) {
          if ([self noteEditingRequestIdentifier] != requestIdentifier) {
              [listViewController setCellPresentationHidden:NO forItem:item];
              return;
          }
          [sourceView setAlpha:1];
          [sourceView setTransform:CGAffineTransformIdentity];
          [headerView setHidden:NO];
          [headerView setAlpha:1];
          [self setActiveSourceContentView:nil];
          [self resetNoteEditingState];
          [[self mainView] setAnimating:NO];
        }];
}

- (void)finishNoteEditingWithRequestIdentifier:(NSUInteger)requestIdentifier {
    if ([self noteEditingRequestIdentifier] != requestIdentifier || ![self isNoteEditing] || [self isDismissingPanel]) {
        return;
    }

    [self setFinishingNoteEditing:YES];
    MTNoteEditorView *noteEditorView = [[self noteEditorViewController] noteEditorView];
    [noteEditorView setAutomaticallyPositionsPreviewCell:NO];
    [[self noteEditorViewController] resignEditing];

    NSTimeInterval duration = [self noteEditingKeyboardAnimationDuration];
    UIViewAnimationOptions options = [self noteEditingKeyboardAnimationOptions];
    if ([self noteEditingOrigin] == MTNoteEditingOriginPreview ||
        [self noteEditingOrigin] == MTNoteEditingOriginWordSelection) {
        [self animateNoteEditingReturnToTransientContentWithRequestIdentifier:requestIdentifier
                                                             targetPanelFrame:[self noteEditingOriginalPanelFrame]
                                                                     duration:duration
                                                                      options:options];
        return;
    }

    [self clearSearchAfterTransientContentState];
    if ([[self searchController] isSearchActive]) {
        [[self searchController] resetSearchState];
    }
    [self animateNoteEditingReturnWithRequestIdentifier:requestIdentifier
                                     ensuresItemVisible:[self noteEditingBeganFromSearch]
                                       targetPanelFrame:[self noteEditingOriginalPanelFrame]
                                               duration:duration
                                                options:options];
}

- (void)noteEditorViewControllerDidRequestCancel:(MTNoteEditorViewController *)controller {
    if (![self isNoteEditing] || [self isDismissingPanel] || [self isFinishingNoteEditing]) {
        return;
    }

    [controller restorePreviewToSavedState];
    [self finishNoteEditingWithRequestIdentifier:[self noteEditingRequestIdentifier]];
}

- (void)noteEditorViewController:(MTNoteEditorViewController *)controller
              didRequestSaveNote:(NSString *)note {
    MTPasteboardItem *item = [self noteEditingItem];
    NSString *historyKey = [self noteEditingHistoryKey];
    MTHistoryListViewController *listViewController = [self noteEditingSourceListViewController];
    NSUInteger requestIdentifier = [self noteEditingRequestIdentifier];
    if (!item || [historyKey length] == 0 || !listViewController) {
        [controller setSaving:NO];
        return;
    }

    [[MTPasteboardManager sharedInstance]
                  setNote:note
        forPasteboardItem:item
         inHistoryWithKey:historyKey
               completion:^(BOOL success) {
                 if (!success) {
                     if ([self noteEditingRequestIdentifier] == requestIdentifier && [self isNoteEditing] &&
                         ![self isDismissingPanel]) {
                         [controller setSaving:NO];
                         [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleRigid];
                     }
                     return;
                 }

                 [item setNote:note];
                 [listViewController updateNote:note
                                        forItem:item
                                     completion:^{
                                       [self finishNoteEditingWithRequestIdentifier:requestIdentifier];
                                     }];
               }];
}

- (void)noteEditorViewController:(MTNoteEditorViewController *)controller
    didUpdateKeyboardBottomInset:(CGFloat)keyboardBottomInset
               animationDuration:(NSTimeInterval)animationDuration
                         options:(UIViewAnimationOptions)options {
    if (controller != [self noteEditorViewController] || ![self isNoteEditing]) {
        return;
    }

    if ([self isFinishingNoteEditing] || [self isDismissingPanel]) {
        return;
    }

    [self setNoteEditingKeyboardAnimationDuration:animationDuration];
    [self setNoteEditingKeyboardAnimationOptions:options];

    MTNoteEditorView *noteEditorView = [controller noteEditorView];
    UIView *mainView = [self mainView];
    UIView *superview = [mainView superview];
    BOOL adjustsPanelFrame = superview != nil;
    CGRect targetFrame =
        adjustsPanelFrame ? [self noteEditingPanelFrameForKeyboardBottomInset:keyboardBottomInset] : [mainView frame];

    void (^updates)(void) = ^{
      [noteEditorView setAnchorsEditingContentToTop:YES];
      [noteEditorView setKeyboardBottomInset:0];
      if (adjustsPanelFrame) {
          [mainView setFrame:targetFrame];
      }
      [mainView layoutIfNeeded];
    };
    if (animationDuration <= 0) {
        updates();
        return;
    }
    [mainView layoutIfNeeded];
    [UIView animateWithDuration:animationDuration delay:0 options:options animations:updates completion:nil];
}

#pragma mark - Preview Note Editing

- (void)wordSelectionViewControllerDidRequestEdit:(MTWordSelectionViewController *)controller {
    if (controller != [self wordSelectionViewController] || [[self mainView] isAnimating] ||
        [[self panelPresentationController] isAnimating] || [self isNoteEditing]) {
        [[self wordSelectionViewController] setEditButtonEnabled:YES];
        return;
    }

    MTPasteboardItem *item = [controller sourceItem];
    NSString *historyKey = [controller sourceHistoryKey];
    if (!item || [historyKey length] == 0 || [[item imageName] length] > 0) {
        [[self wordSelectionViewController] setEditButtonEnabled:YES];
        return;
    }

    [self setPreviewTextEditingBeganFromWordSelection:YES];
    NSRange replacementRange = [controller hasSelectedText] ? [controller selectedTextRangeInOriginalText]
                                                            : NSMakeRange(NSNotFound, 0);
    UIView *wordSelectionView = [controller view];
    UIView *editorView = [[self textEditorViewController] textEditorView];
    [wordSelectionView setHidden:YES];
    [editorView setHidden:NO];
    [editorView setAlpha:1];
    [[self textEditorViewController] beginEditingItem:item
                                     sourceHistoryKey:historyKey
                                     replacementRange:replacementRange];
}

- (void)previewViewControllerDidRequestEdit:(MTPreviewViewController *)controller {
    if (controller != [self previewViewController] || [[self mainView] isAnimating] ||
        [[self panelPresentationController] isAnimating] || [self isNoteEditing]) {
        [[self previewViewController] setEditButtonEnabled:YES];
        return;
    }

    MTPasteboardItem *item = [controller previewItem];
    NSString *historyKey = [controller sourceHistoryKey];
    if (!item || [historyKey length] == 0 || [[item imageName] length] > 0) {
        [[self previewViewController] setEditButtonEnabled:YES];
        return;
    }

    [self setPreviewTextEditingBeganFromWordSelection:NO];
    UIView *previewView = [controller previewView];
    UIView *editorView = [[self textEditorViewController] textEditorView];
    [previewView setHidden:YES];
    [editorView setHidden:NO];
    [editorView setAlpha:1];
    [[self textEditorViewController] beginEditingItem:item
                                     sourceHistoryKey:historyKey
                                     replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (void)textEditorViewControllerDidBeginEditing:(MTTextEditorViewController *)controller {
    (void)controller;
    if (CGRectIsEmpty([self previewTextEditingOriginalPanelFrame])) {
        [self setPreviewTextEditingOriginalPanelFrame:[[self mainView] frame]];
    }
    [self beginSearchInputExternalHideSuppression];
    [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleLight];
}

- (void)restorePreviewTextEditingPanelFrameIfNeeded {
    [[[self previewViewController] previewView] setKeyboardBottomInset:0];
    [[[self textEditorViewController] textEditorView] setKeyboardBottomInset:0];
    [[[self textEditorViewController] textEditorView] setHidden:YES];
    [self endSearchInputExternalHideSuppression];
}

- (void)finishPreviewTextEditingFromController:(MTTextEditorViewController *)controller {
    [self setPreviewTextEditingFinishing:YES];
    [controller finishEditing];
    [self restorePreviewTextEditingPanelFrameIfNeeded];
    [self restoreWordSelectionAfterPreviewTextEditingIfNeeded];
    if ([self shouldLiftPreviewTextEditingCard] && !CGRectIsEmpty([self previewTextEditingOriginalPanelFrame]) &&
        !CGRectEqualToRect([[self mainView] frame], [self previewTextEditingOriginalPanelFrame])) {
        [self updatePreviewTextEditingPanelForKeyboardBottomInset:0
                                               animationDuration:0.25
                                                         options:UIViewAnimationOptionCurveEaseInOut |
                                                                 UIViewAnimationOptionBeginFromCurrentState |
                                                                 UIViewAnimationOptionAllowUserInteraction];
    } else {
        [self setPreviewTextEditingOriginalPanelFrame:CGRectZero];
        [self setPreviewTextEditingFinishing:NO];
    }
}

- (void)restoreWordSelectionAfterPreviewTextEditingIfNeeded {
    BOOL beganFromWordSelection = [self previewTextEditingBeganFromWordSelection];
    MTPasteboardItem *item = [[self textEditorViewController] item];
    NSString *historyKey = [[self textEditorViewController] sourceHistoryKey];
    UIView *editorView = [[self textEditorViewController] textEditorView];
    UIView *wordSelectionView = [[self wordSelectionViewController] view];
    UIView *previewView = [[self previewViewController] previewView];

    [editorView setHidden:YES];
    [[self textEditorViewController] reset];
    [self setPreviewTextEditingBeganFromWordSelection:NO];

    if (!item || [historyKey length] == 0) {
        return;
    }

    if (beganFromWordSelection) {
        [[self wordSelectionViewController] showWordSelectionWithItem:item
                                                     sourceHistoryKey:historyKey
                                                   automaticallyPaste:[self automaticallyPaste]];
        [wordSelectionView setHidden:NO];
        [wordSelectionView setAlpha:1];
        [[self wordSelectionViewController] setEditButtonEnabled:YES];
        return;
    }

    [[self previewViewController] showPreviewWithItem:item sourceHistoryKey:historyKey];
    [previewView setHidden:NO];
    [previewView setAlpha:1];
    [[self previewViewController] setEditButtonEnabled:YES];
}

- (void)textEditorViewControllerDidRequestCancel:(MTTextEditorViewController *)controller {
    if (controller != [self textEditorViewController] || [self isPreviewTextEditingFinishing] || [controller isSaving]) {
        return;
    }
    [self finishPreviewTextEditingFromController:controller];
}

- (void)textEditorViewControllerDidRequestSave:(MTTextEditorViewController *)controller {
    if (controller != [self textEditorViewController] || [self isPreviewTextEditingFinishing]) {
        return;
    }

    MTPasteboardItem *item = [controller item];
    NSString *historyKey = [controller sourceHistoryKey];
    NSString *updatedText = [controller composedEditedContent];
    if (!item || [historyKey length] == 0) {
        [controller setSaving:NO];
        return;
    }

    NSString *normalizedText = [(updatedText ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if ([normalizedText length] == 0) {
        [controller setSaving:NO];
        [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleRigid];
        return;
    }

    if ([normalizedText isEqualToString:[item content]]) {
        [self finishPreviewTextEditingFromController:controller];
        return;
    }

    NSDictionary<NSString *, id> *originalDictionary = [item dictionaryRepresentation];
    MTHistoryListViewController *listViewController = [self listViewControllerForHistoryKey:historyKey];
    NSUInteger requestIdentifier = [self previewTextEditingRequestIdentifier] + 1;
    [self setPreviewTextEditingRequestIdentifier:requestIdentifier];
    [[MTPasteboardManager sharedInstance] replaceContent:normalizedText
                                          forPasteboardItem:item
                                           inHistoryWithKey:historyKey
                                                 completion:^(BOOL success) {
                                                   if ([self previewTextEditingRequestIdentifier] != requestIdentifier ||
                                                       controller != [self textEditorViewController] ||
                                                       ![controller isEditing]) {
                                                       return;
                                                   }
                                                   if (!success) {
                                                       [controller setSaving:NO];
                                                       [[self panelPresentationController]
                                                           triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleRigid];
                                                       return;
                                                   }

                                                   [listViewController replaceContent:normalizedText
                                                           forItemMatchingDictionary:originalDictionary
                                                                           completion:^{
                                                                             if ([self previewTextEditingRequestIdentifier] !=
                                                                                     requestIdentifier ||
                                                                                 controller != [self textEditorViewController] ||
                                                                                 ![controller isEditing]) {
                                                                                 return;
                                                                             }
                                                                             [item setContent:normalizedText];
                                                                             [item setHasLink:[normalizedText hasPrefix:@"http://"] ||
                                                                                              [normalizedText hasPrefix:@"https://"]];
                                                                             [self finishPreviewTextEditingFromController:controller];
                                                                             [[self panelPresentationController]
                                                                                 triggerHapticFeedbackWithStyle:
                                                                                     UIImpactFeedbackStyleMedium];
                                                                           }];
                                                 }];
}

- (void)beginNoteEditingFromPreviewController:(MTPreviewViewController *)controller {
    MTPasteboardItem *item = [controller previewItem];
    NSString *historyKey = [controller sourceHistoryKey];
    MTPreviewView *previewView = [controller previewView];
    if (!item || [historyKey length] == 0 || [previewView isHidden]) {
        [controller setEditButtonEnabled:YES];
        return;
    }

    MTHistoryListViewController *listViewController = [self listViewControllerForHistoryKey:historyKey];
    MTTableViewCell *presentationCell = [listViewController presentationCellForItem:item];
    if (!listViewController || !presentationCell) {
        [controller setEditButtonEnabled:YES];
        return;
    }

    [controller setEditButtonEnabled:NO];
    [previewView setUserInteractionEnabled:NO];

    UIView *mainView = [self mainView];
    CGFloat keyboardBottomInset = [[self noteEditorViewController] visibleKeyboardBottomInset];
    [self setNoteEditingBeganFromSearch:NO];
    [self setNoteEditingKeepsSearchHeaderHidden:NO];
    [self setNoteEditingOriginalPanelFrame:[mainView frame]];
    [self setNoteEditingKeyboardAnimationDuration:0.25];
    [self setNoteEditingKeyboardAnimationOptions:UIViewAnimationOptionCurveEaseInOut |
                                                 UIViewAnimationOptionBeginFromCurrentState |
                                                 UIViewAnimationOptionAllowUserInteraction];

    MTTableViewCell *visibleCell = [listViewController visibleCellForItem:item];
    CGFloat cellHeight = CGRectGetHeight([visibleCell bounds]);
    if (cellHeight <= 0) {
        cellHeight = [[listViewController tableView] rowHeight];
    }
    NSUInteger requestIdentifier = [self prepareNoteEditingSessionForItem:item
                                                       listViewController:listViewController
                                                         presentationCell:presentationCell
                                                               cellHeight:cellHeight
                                                      keyboardBottomInset:keyboardBottomInset
                                                                   origin:MTNoteEditingOriginPreview];

    MTNoteEditorView *noteEditorView = [[self noteEditorViewController] noteEditorView];
    [[self mainView] layoutIfNeeded];
    [noteEditorView setHidden:NO];
    [noteEditorView setAlpha:0];
    [noteEditorView setAutomaticallyPositionsPreviewCell:YES];
    [noteEditorView layoutIfNeeded];
    [[noteEditorView previewCell] setFrame:[noteEditorView targetPreviewCellFrame]];
    [[noteEditorView previewCell] setAlpha:1];
    [[noteEditorView inputRowView] setAlpha:1];

    CGRect targetPanelFrame = [self noteEditingPanelFrameForKeyboardBottomInset:keyboardBottomInset];
    [[self mainView] setAnimating:YES];
    [UIView animateWithDuration:0.25
        delay:0
        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
        animations:^{
          [mainView setFrame:targetPanelFrame];
          [mainView layoutIfNeeded];
          [noteEditorView layoutIfNeeded];
          [previewView setAlpha:0];
          [noteEditorView setAlpha:1];
        }
        completion:^(__unused BOOL finished) {
          if ([self noteEditingRequestIdentifier] != requestIdentifier || ![self isNoteEditing]) {
              [previewView setHidden:NO];
              [previewView setAlpha:1];
              [previewView setUserInteractionEnabled:YES];
              [controller setEditButtonEnabled:YES];
              return;
          }
          [previewView setHidden:YES];
          [previewView setAlpha:1];
          [noteEditorView setAutomaticallyPositionsPreviewCell:YES];
          [noteEditorView setNeedsLayout];
          [[self mainView] setAnimating:NO];
          [[self noteEditorViewController] beginEditing];
          [self executePendingExternalHideRequestIfReady];
        }];
    [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleMedium];
}

- (UIView *)transientContentViewForNoteEditingOrigin:(MTNoteEditingOrigin)origin {
    if (origin == MTNoteEditingOriginPreview) {
        return [[self previewViewController] previewView];
    }
    if (origin == MTNoteEditingOriginWordSelection) {
        return [[self wordSelectionViewController] view];
    }
    return nil;
}

- (void)restoreTransientEditButtonForOrigin:(MTNoteEditingOrigin)origin {
    if (origin == MTNoteEditingOriginPreview) {
        [[self previewViewController] setEditButtonEnabled:YES];
    } else if (origin == MTNoteEditingOriginWordSelection) {
        [[self wordSelectionViewController] setEditButtonEnabled:YES];
    }
}

- (void)beginNoteEditingFromWordSelectionController:(MTWordSelectionViewController *)controller {
    MTPasteboardItem *item = [controller sourceItem];
    NSString *historyKey = [controller sourceHistoryKey];
    UIView *contentView = [controller view];
    if (!item || [historyKey length] == 0 || [contentView isHidden]) {
        [controller setEditButtonEnabled:YES];
        return;
    }

    MTHistoryListViewController *listViewController = [self listViewControllerForHistoryKey:historyKey];
    MTTableViewCell *presentationCell = [listViewController presentationCellForItem:item];
    if (!listViewController || !presentationCell) {
        [controller setEditButtonEnabled:YES];
        return;
    }

    [controller setEditButtonEnabled:NO];
    [contentView setUserInteractionEnabled:NO];

    UIView *mainView = [self mainView];
    CGFloat keyboardBottomInset = [[self noteEditorViewController] visibleKeyboardBottomInset];
    [self setNoteEditingBeganFromSearch:NO];
    [self setNoteEditingKeepsSearchHeaderHidden:NO];
    [self setNoteEditingOriginalPanelFrame:[mainView frame]];
    [self setNoteEditingKeyboardAnimationDuration:0.25];
    [self setNoteEditingKeyboardAnimationOptions:UIViewAnimationOptionCurveEaseInOut |
                                                 UIViewAnimationOptionBeginFromCurrentState |
                                                 UIViewAnimationOptionAllowUserInteraction];

    MTTableViewCell *visibleCell = [listViewController visibleCellForItem:item];
    CGFloat cellHeight = CGRectGetHeight([visibleCell bounds]);
    if (cellHeight <= 0) {
        cellHeight = [[listViewController tableView] rowHeight];
    }
    NSUInteger requestIdentifier = [self prepareNoteEditingSessionForItem:item
                                                       listViewController:listViewController
                                                         presentationCell:presentationCell
                                                               cellHeight:cellHeight
                                                      keyboardBottomInset:keyboardBottomInset
                                                                   origin:MTNoteEditingOriginWordSelection];

    MTNoteEditorView *noteEditorView = [[self noteEditorViewController] noteEditorView];
    [[self mainView] layoutIfNeeded];
    [noteEditorView setHidden:NO];
    [noteEditorView setAlpha:0];
    [noteEditorView setAutomaticallyPositionsPreviewCell:YES];
    [noteEditorView layoutIfNeeded];
    [[noteEditorView previewCell] setFrame:[noteEditorView targetPreviewCellFrame]];
    [[noteEditorView previewCell] setAlpha:1];
    [[noteEditorView inputRowView] setAlpha:1];

    CGRect targetPanelFrame = [self noteEditingPanelFrameForKeyboardBottomInset:keyboardBottomInset];
    [[self mainView] setAnimating:YES];
    [UIView animateWithDuration:0.25
        delay:0
        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
        animations:^{
          [mainView setFrame:targetPanelFrame];
          [mainView layoutIfNeeded];
          [noteEditorView layoutIfNeeded];
          [contentView setAlpha:0];
          [noteEditorView setAlpha:1];
        }
        completion:^(__unused BOOL finished) {
          if ([self noteEditingRequestIdentifier] != requestIdentifier || ![self isNoteEditing]) {
              [contentView setHidden:NO];
              [contentView setAlpha:1];
              [contentView setUserInteractionEnabled:YES];
              [controller setEditButtonEnabled:YES];
              return;
          }
          [contentView setHidden:YES];
          [contentView setAlpha:1];
          [noteEditorView setAutomaticallyPositionsPreviewCell:YES];
          [noteEditorView setNeedsLayout];
          [[self mainView] setAnimating:NO];
          [[self noteEditorViewController] beginEditing];
          [self executePendingExternalHideRequestIfReady];
        }];
    [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleMedium];
}

- (void)animateNoteEditingReturnToTransientContentWithRequestIdentifier:(NSUInteger)requestIdentifier
                                                       targetPanelFrame:(CGRect)targetPanelFrame
                                                               duration:(NSTimeInterval)duration
                                                                options:(UIViewAnimationOptions)options {
    if ([self noteEditingRequestIdentifier] != requestIdentifier || ![self isNoteEditing] || [self isDismissingPanel]) {
        return;
    }

    MTNoteEditingOrigin origin = [self noteEditingOrigin];
    UIView *contentView = [self transientContentViewForNoteEditingOrigin:origin];
    if (!contentView) {
        return;
    }

    MTNoteEditorView *noteEditorView = [[self noteEditorViewController] noteEditorView];
    MTMainView *mainView = [self mainView];
    [contentView setHidden:NO];
    [contentView setAlpha:0];
    [contentView setUserInteractionEnabled:NO];
    [noteEditorView setAutomaticallyPositionsPreviewCell:YES];
    [[self mainView] setAnimating:YES];

    duration = duration > 0 ? duration : 0.25;
    options |= UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    [UIView animateWithDuration:duration
        delay:0
        options:options
        animations:^{
          [mainView setFrame:targetPanelFrame];
          [mainView layoutIfNeeded];
          [noteEditorView setAlpha:0];
          [contentView setAlpha:1];
        }
        completion:^(__unused BOOL finished) {
          if ([self noteEditingRequestIdentifier] != requestIdentifier) {
              [contentView setAlpha:1];
              [contentView setUserInteractionEnabled:YES];
              return;
          }
          [contentView setHidden:NO];
          [contentView setAlpha:1];
          [contentView setUserInteractionEnabled:YES];
          [self resetNoteEditingState];
          [self restoreTransientEditButtonForOrigin:origin];
          [[self mainView] setAnimating:NO];
        }];
}

#pragma mark - Transient Presentation

- (void)showContentForItem:(MTPasteboardItem *)item {
    [self showContentForItem:item forceWordSelection:NO animated:YES completion:nil];
}

- (void)showContentForItem:(MTPasteboardItem *)item completion:(nullable void (^)(void))completion {
    [self showContentForItem:item forceWordSelection:NO animated:YES completion:completion];
}

- (void)showContentForItem:(MTPasteboardItem *)item
    forceWordSelection:(BOOL)forceWordSelection
            completion:(nullable void (^)(void))completion {
    [self showContentForItem:item forceWordSelection:forceWordSelection animated:YES completion:completion];
}

- (void)showContentForItem:(MTPasteboardItem *)item
    forceWordSelection:(BOOL)forceWordSelection
               animated:(BOOL)animated
            completion:(nullable void (^)(void))completion {
    BOOL restoresSearchFirstResponder = [[self searchController] isActiveSearchFirstResponder];
    [self setRestoresSearchFirstResponderAfterTransientContent:restoresSearchFirstResponder];
    if (restoresSearchFirstResponder) {
        [self setSearchContentOffsetBeforeTransientContent:[[[self activeListViewController] tableView] contentOffset]];
        [self setHasSearchContentOffsetBeforeTransientContent:YES];
    } else {
        [self setHasSearchContentOffsetBeforeTransientContent:NO];
    }
    NSString *historyKey = [self effectiveActiveHistoryKey];
    MTHistoryListView *sourceTableView = [self tableViewForHistoryKey:historyKey];
    [self setActiveSourceContentView:sourceTableView];
    NSString *previewText =
        [([item content] ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    BOOL canUseWordSelection = (forceWordSelection || [self swipeToSelectWords]) && [[item imageName] isEqualToString:@""] &&
                               [[self wordSelectionViewController] canShowText:previewText];
    UIView *viewToShow = nil;
    UIView *transitionContentView = nil;
    if (canUseWordSelection) {
        [[self wordSelectionViewController] showWordSelectionWithItem:item
                                                     sourceHistoryKey:historyKey
                                                   automaticallyPaste:[self automaticallyPaste]];
        viewToShow = [[self wordSelectionViewController] view];
        transitionContentView = [[self wordSelectionViewController] wordSelectionView].transitionContentView;
    } else {
        [[self previewViewController] showPreviewWithItem:item sourceHistoryKey:historyKey];
        viewToShow = [[self previewViewController] previewView];
        transitionContentView = [[self previewViewController] previewView].transitionContentView;
    }

    MTHeaderView *mainHeaderView = [[self mainView] headerView];
    [mainHeaderView setHidden:YES];
    [mainHeaderView setAlpha:1.0];
    if (!animated) {
        [viewToShow setHidden:NO];
        [viewToShow setAlpha:1.0];
        [viewToShow setTransform:CGAffineTransformIdentity];
        [transitionContentView setHidden:NO];
        [transitionContentView setAlpha:1.0];
        [transitionContentView setTransform:CGAffineTransformIdentity];
        [sourceTableView setHidden:YES];
        [sourceTableView setAlpha:0.0];
        [sourceTableView setTransform:CGAffineTransformIdentity];
        [[self mainView] setAnimating:NO];
        if (restoresSearchFirstResponder) {
            [[self searchController] resignSearchFirstResponder];
        }
        if (completion) {
            completion();
        }
        return;
    }
    [[self mainView] showContentView:viewToShow
                   transitioningView:transitionContentView
                     hideContentView:sourceTableView
                   transitioningView:sourceTableView
                           direction:MTContentTransitionDirectionForward
                 alongsideAnimations:nil
                          completion:^{
                            if (restoresSearchFirstResponder) {
                                [[self searchController] resignSearchFirstResponder];
                            }
                            if (completion) {
                                completion();
                            }
                          }];
    [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleMedium];
}

- (void)hidePreview {
    [[[self mainView] headerView] setHistorySwitcherVisible:YES animated:NO];
    [self updateFavoritesButtonForHistoryKey:[self effectiveActiveHistoryKey]];
    if ([[[self previewViewController] previewView] isHidden] || [[self panelPresentationController] isAnimating]) {
        return;
    }

    UIView *sourceView = [self activeSourceContentView];
    MTPreviewView *previewView = [[self previewViewController] previewView];
    if (!sourceView) {
        [[self previewViewController] resetPreviewState];
        [[previewView headerView] setHidden:NO];
        [self setActiveSourceContentView:nil];
        [[[self mainView] headerView] setHidden:NO];
        [[[self mainView] headerView] setAlpha:1.0];
        [self refreshSearchAfterEndingTransientContentIfNeeded];
        return;
    }

    UIView *mainHeaderView = [[self mainView] headerView];
    [mainHeaderView setHidden:NO];
    [mainHeaderView setAlpha:1.0];
    [[previewView headerView] setHidden:YES];
    [[self mainView] showContentView:sourceView
        transitioningView:sourceView
        hideContentView:previewView
        transitioningView:[previewView transitionContentView]
        direction:MTContentTransitionDirectionBackward
        alongsideAnimations:^{
          [self refreshSearchAfterEndingTransientContentIfNeeded];
        }
        completion:^{
          [[self previewViewController] hidePreview];
          [[previewView headerView] setHidden:NO];
          [self setActiveSourceContentView:nil];
          [mainHeaderView setHidden:NO];
          [mainHeaderView setAlpha:1.0];
        }];
}

- (void)hideWordSelection {
    [[[self mainView] headerView] setHistorySwitcherVisible:YES animated:NO];
    [self updateFavoritesButtonForHistoryKey:[self effectiveActiveHistoryKey]];
    if ([[[self wordSelectionViewController] view] isHidden] || [[self panelPresentationController] isAnimating]) {
        return;
    }

    UIView *sourceView = [self activeSourceContentView];
    UIView *wordSelectionView = [[self wordSelectionViewController] view];
    if (!sourceView) {
        [[self wordSelectionViewController] resetWordSelectionState];
        [[[[self wordSelectionViewController] wordSelectionView] headerView] setHidden:NO];
        [self setActiveSourceContentView:nil];
        [[[self mainView] headerView] setHidden:NO];
        [[[self mainView] headerView] setAlpha:1.0];
        [self refreshSearchAfterEndingTransientContentIfNeeded];
        return;
    }

    UIView *mainHeaderView = [[self mainView] headerView];
    [mainHeaderView setHidden:NO];
    [mainHeaderView setAlpha:1.0];
    [[[[self wordSelectionViewController] wordSelectionView] headerView] setHidden:YES];
    [[self mainView] showContentView:sourceView
        transitioningView:sourceView
        hideContentView:wordSelectionView
        transitioningView:[[self wordSelectionViewController] wordSelectionView].transitionContentView
        direction:MTContentTransitionDirectionBackward
        alongsideAnimations:^{
          [self refreshSearchAfterEndingTransientContentIfNeeded];
        }
        completion:^{
          [[self wordSelectionViewController] hideWordSelection];
          [[[[self wordSelectionViewController] wordSelectionView] headerView] setHidden:NO];
          [self setActiveSourceContentView:nil];
          [mainHeaderView setHidden:NO];
          [mainHeaderView setAlpha:1.0];
        }];
}

#pragma mark - MTClearConfirmationViewControllerDelegate

- (void)clearConfirmationViewControllerDidCancel:(MTClearConfirmationViewController *)controller {
    if ([[self panelPresentationController] isAnimating]) {
        return;
    }

    [self hideClearConfirmationWithReload:NO];
    [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleSoft];
}

- (void)clearConfirmationViewControllerDidClearHistoryKey:(NSString *)historyKey {
    [self hideClearConfirmationWithReload:YES];
    [[self panelPresentationController] triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleHeavy];
}

- (void)clearConfirmationViewController:(MTClearConfirmationViewController *)controller
              didFailClearingHistoryKey:(NSString *)historyKey {
}

#pragma mark - MTWordSelectionViewControllerDelegate

- (void)wordSelectionViewController:(MTWordSelectionViewController *)controller
    didRequestHideContainerAfterDirectPaste:(BOOL)directPaste {
    [[self panelPresentationController] prepareStandardDismissAnimation];
    if (directPaste) {
        [self hideAfterDirectPaste];
    } else {
        [self hideRestoringFocus];
    }
}

- (void)wordSelectionViewController:(MTWordSelectionViewController *)controller
     triggerHapticFeedbackWithStyle:(UIImpactFeedbackStyle)style {
    [[self panelPresentationController] triggerHapticFeedbackWithStyle:style];
}


#pragma mark - Public API

- (void)reload {

    NSString *historyKey = [self effectiveActiveHistoryKey];
    [self reloadTableViewForHistoryKey:historyKey
                animatingTopInsertions:![self isHidden] && [historyKey isEqualToString:kMTHistoryKeyHistory]
                            completion:^(MTHistoryListView *tableView) {
                              if (![[self effectiveActiveHistoryKey] isEqualToString:historyKey]) {
                                  return;
                              }
                              if ([self isShowingClearConfirmation] ||
                                  ![[[self previewViewController] previewView] isHidden] ||
                                  ![[[self wordSelectionViewController] view] isHidden] || [self isNoteEditing]) {
                                  return;
                              }
                              [self setHistoryContentVisibleForKey:historyKey];
                              [[self searchController] refreshForListViewController:[self activeListViewController]];
                            }];
}

- (void)preloadHistoryIfNeeded {
    [[self historyController] preloadHistoryWithCompletion:nil];
}

- (void)show {
    [self showWithInitialContentItem:nil completion:nil];
}

- (void)showWithCompletion:(nullable void (^)(void))completion {
    [self showWithInitialContentItem:nil completion:completion];
}

- (void)showWithInitialContentItem:(nullable MTPasteboardItem *)contentItem
                        completion:(nullable void (^)(void))completion {
    if ([[self panelPresentationController] isAnimating] || [self preparingToShow]) {
        return;
    }
    if (![self isHidden]) {
        return;
    }

    [self clearExternalHideCoordinator];
    [self setDismissingPanel:NO];
    [self setPreparingToShow:YES];
    NSUInteger showRequestIdentifier = [self showRequestIdentifier] + 1;
    [self setShowRequestIdentifier:showRequestIdentifier];
    [self resetClearConfirmationIfNeeded];

    [[self historyListViewController] setAutomaticallyPaste:[self automaticallyPaste]];
    [[self favoritesListViewController] setAutomaticallyPaste:[self automaticallyPaste]];
    [[[self historyListViewController] tableView] reloadData];
    [[[self favoritesListViewController] tableView] reloadData];

    NSString *initialHistoryKey = [self historyKeyForInitialViewMode];
    if ([initialHistoryKey length] > 0) {
        [[self historyController] setActiveHistoryKey:initialHistoryKey];
    }

    NSString *historyKey = [self effectiveActiveHistoryKey];
    BOOL isQuickPreview = contentItem != nil;
    [self reloadTableViewForHistoryKey:historyKey
                animatingTopInsertions:NO
                            completion:^(MTHistoryListView *tableView) {
                              if ([self showRequestIdentifier] != showRequestIdentifier) {
                                  return;
                              }
                              [self setPreparingToShow:NO];
                              if (![[self effectiveActiveHistoryKey] isEqualToString:historyKey] || ![self isHidden] ||
                                  [[self panelPresentationController] isAnimating]) {
                                  return;
                              }

                              [self setHistoryContentVisibleForKey:historyKey];
                              [[self searchController] attachToListViewController:[self activeListViewController]
                                                                   hidesSearchBar:YES];
                              if (contentItem) {
                                  [self showContentForItem:contentItem
                                      forceWordSelection:YES
                                                 animated:NO
                                              completion:nil];
                              }
                              [[self panelPresentationController] showPanelWithCompletion:^{
                                if (isQuickPreview) {
                                    // A host app can emit a transient window/keyboard hide notification
                                    // while the quick-preview panel is being prepared. It must not close
                                    // the panel immediately after it becomes visible.
                                    [self clearExternalHideCoordinator];
                                } else {
                                    [self executePendingExternalHideRequestIfReady];
                                }
                                if (completion) {
                                    completion();
                                }
                              }];
                            }];
}

- (void)showQuickPreviewForItem:(MTPasteboardItem *)item {
    if (!item || [self isEditingAnyContent] || ![self isHidden]) {
        return;
    }

    [self showWithInitialContentItem:item completion:nil];
}

#pragma mark - Hiding

- (void)hide {
    [self hideWithCompletion:nil];
}

- (void)hideWithStandardDismissAnimation {
    [[self panelPresentationController] prepareStandardDismissAnimation];
    [self hideWithCompletion:nil];
}

- (void)hideAfterDirectPaste {
    BOOL shouldRestoreFocusAfterHide = [self isFullscreenSearchActive];
    [self hideWithCompletion:^{
      if (!shouldRestoreFocusAfterHide) {
          return;
      }
      [[self delegate] mainViewControllerDidRequestFocusRestore:self];
    }];
}

- (void)hideRestoringFocus {
    [self hideWithCompletion:^{
      [[self delegate] mainViewControllerDidRequestFocusRestore:self];
    }];
}

- (void)completeHideAfterShowingTransientContent:(BOOL)wasShowingTransientContent
                                      completion:(void (^)(void))completion {
    [self restoreActiveSourceContentView];
    [[[self mainView] headerView] setHidden:NO];
    [[[self mainView] headerView] setAlpha:1.0];
    [[self previewViewController] resetPreviewState];
    [[self wordSelectionViewController] resetWordSelectionState];
    [[self textEditorViewController] reset];
    [self setPreviewTextEditingRequestIdentifier:[self previewTextEditingRequestIdentifier] + 1];
    [self setPreviewTextEditingOriginalPanelFrame:CGRectZero];
    [self setPreviewTextEditingFinishing:NO];
    [self resetNoteEditingState];
    [self setActiveSourceContentView:nil];
    [self setDismissingPanel:NO];
    if (wasShowingTransientContent) {
        [self refreshSearchAfterEndingTransientContentIfNeeded];
    }
    if ([self alwaysScrollToTop]) {
        [[self historyController] markAllHistoryKeysForScrollToTopBeforeNextDisplay];
    }
    if (completion) {
        completion();
    }
    [[self delegate] mainViewControllerDidHide:self];
}

- (void)hideWithCompletion:(void (^)(void))completion {
    [self hideWithAnimationStyle:MTPanelHideAnimationStyleDefault completion:completion];
}

- (void)hideWithAnimationStyle:(MTPanelHideAnimationStyle)animationStyle completion:(void (^)(void))completion {
    [self setShowRequestIdentifier:[self showRequestIdentifier] + 1];
    [self setPreparingToShow:NO];

    if ([[self panelPresentationController] isAnimating]) {
        return;
    }

    [self dismissLeadingButtonMenu];

    [self clearExternalHideCoordinator];
    [self setDismissingPanel:YES];
    BOOL wasShowingTransientContent =
        [self isPreviewActive] || [self isWordSelectionActive] || [self isNoteEditing] || [self isPreviewTextEditing];
    [[self searchController] resignSearchFirstResponder];
    [[self noteEditorViewController] resignEditing];
    [[[[self textEditorViewController] textEditorView] textView] resignFirstResponder];
    [[self panelPresentationController]
        hidePanelWithAnimationStyle:animationStyle
                         completion:^{
                           [[self searchController] resetSearchState];
                           [self completeHideAfterShowingTransientContent:wasShowingTransientContent
                                                               completion:completion];
                         }];
}

- (void)hideForExternalRequestWithAnimationStyle:(MTPanelHideAnimationStyle)animationStyle
                                      completion:(nullable void (^)(void))completion {
    if ([self isHidden]) {
        return;
    }

    if ([self isEditingAnyContent]) {
        return;
    }

    if ([[self externalHideCoordinator] shouldSuppressExternalHide]) {
        return;
    }

    if ([self externalHideRequestShouldWaitForAnimations]) {
        [[self externalHideCoordinator] recordPendingExternalHideRequestWithAnimationStyle:animationStyle
                                                                                completion:completion];
        return;
    }

    [self hideWithAnimationStyle:animationStyle completion:completion];
}

- (void)hideImmediately {
    [self setShowRequestIdentifier:[self showRequestIdentifier] + 1];
    [self setPreparingToShow:NO];

    if ([self isHidden]) {
        return;
    }

    [self dismissLeadingButtonMenu];
    [self clearExternalHideCoordinator];
    [self setDismissingPanel:YES];
    BOOL wasShowingTransientContent =
        [self isPreviewActive] || [self isWordSelectionActive] || [self isNoteEditing] || [self isPreviewTextEditing];
    [[self searchController] resignSearchFirstResponder];
    [[self noteEditorViewController] resignEditing];
    [[[[self textEditorViewController] textEditorView] textView] resignFirstResponder];
    [[self panelPresentationController] hidePanelImmediatelyWithCompletion:^{
      [[self searchController] resetSearchState];
      [self completeHideAfterShowingTransientContent:wasShowingTransientContent completion:nil];
    }];
}

@end
