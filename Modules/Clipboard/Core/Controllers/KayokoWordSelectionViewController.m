//
//  KayokoWordSelectionViewController.m
//  Kayoko
//

#import "KayokoWordSelectionViewController.h"

#import "KayokoHeaderButtonStyle.h"
#import "KayokoHeaderView.h"
#import "KayokoActivitySharePresenter.h"
#import "KayokoPasteboardItem.h"
#import "KayokoPasteboardManager.h"
#import "KayokoQuickAction.h"
#import "KayokoQuickActionPanelViewController.h"
#import "KayokoSystemTranslationPresenter.h"
#import "KayokoWordSelectionView.h"

static NSUInteger const kKayokoWordSelectionMaximumTextLength = 5000;
static NSString *kayokoWordSelectionTextByTrimmingBoundaryNewlines(NSString *text) {
    return [(text ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

NS_ASSUME_NONNULL_BEGIN

@interface KayokoWordSelectionViewController ()
#pragma mark - Views
@property(nonatomic, strong, readwrite) KayokoWordSelectionView *wordSelectionView;

#pragma mark - State

@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, nullable, readwrite) NSString *sourceHistoryKey;
@property(nonatomic, strong, nullable, readwrite) KayokoPasteboardItem *sourceItem;
@property(nonatomic, strong) KayokoSystemTranslationPresenter *systemTranslationPresenter;
@property(nonatomic, strong) KayokoActivitySharePresenter *activitySharePresenter;
@property(nonatomic, assign) BOOL usesSelectionOrderForSelectedText;
@property(nonatomic, strong, nullable) UILabel *actionFailureToastLabel;
@property(nonatomic, assign) NSUInteger actionFailureToastRequestIdentifier;
- (NSArray<NSDictionary<NSString *, id> *> *)loadTextActions;
- (void)openTextAction:(NSDictionary<NSString *, id> *)action;
- (void)showActionFailureToast;
@end

NS_ASSUME_NONNULL_END

@implementation KayokoWordSelectionViewController

#pragma mark - Lifecycle

- (instancetype)initWithName:(NSString *)name {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _name = [name copy];
        _wordSelectionView = [[KayokoWordSelectionView alloc] init];
        [[_wordSelectionView headerView] setTitleText:name];
        [_wordSelectionView setHidden:YES];
        _systemTranslationPresenter = [[KayokoSystemTranslationPresenter alloc] init];
        [[[_wordSelectionView headerView] alternateTrailingButton]
                   addTarget:self
                      action:@selector(handleSelectionOrderButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
        [[[_wordSelectionView headerView] selectionActionButton]
                   addTarget:self
                      action:@selector(handleSelectionActionButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
        [[[_wordSelectionView headerView] translationButton]
                   addTarget:self
                      action:@selector(handleTranslationButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
        [[[_wordSelectionView headerView] shareButton]
                   addTarget:self
                      action:@selector(handleShareButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
        [[[_wordSelectionView headerView] editButton]
                   addTarget:self
                      action:@selector(handleEditButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
        _activitySharePresenter = [[KayokoActivitySharePresenter alloc] init];
        [self setView:_wordSelectionView];

        __weak typeof(self) weakSelf = self;
        [_wordSelectionView setSelectionChangedHandler:^{
          [weakSelf updateActionButtonState];
          [weakSelf updateSelectionActionButtonStates];
          [weakSelf updateTranslationButtonState];
          [weakSelf updateShareButtonState];
          if ([weakSelf selectionChangedHandler]) {
              [weakSelf selectionChangedHandler]();
          }
        }];
    }
    return self;
}

#pragma mark - Public State

- (NSString *)selectedText {
    return [[self wordSelectionView] selectedText];
}

- (NSRange)selectedTextRangeInOriginalText {
    return [[self wordSelectionView] selectedTextRangeInOriginalText];
}

- (BOOL)isShowingWordSelection {
    return ![[self wordSelectionView] isHidden];
}

- (BOOL)hasSelectedText {
    return [[self wordSelectionView] hasSelectedText];
}

- (BOOL)canShowText:(NSString *)text {
    return [text length] <= kKayokoWordSelectionMaximumTextLength;
}

- (void)scrollToTopAnimated:(BOOL)animated {
    [[self wordSelectionView] scrollToTopAnimated:animated];
}

#pragma mark - Presentation

- (void)showWordSelectionWithItem:(KayokoPasteboardItem *)item
                 sourceHistoryKey:(NSString *)sourceHistoryKey
               automaticallyPaste:(BOOL)automaticallyPaste {
    [self setSourceItem:item];
    [self setSourceHistoryKey:sourceHistoryKey];

    NSString *text = kayokoWordSelectionTextByTrimmingBoundaryNewlines([item content]);
    [[self wordSelectionView] setUsesSelectionOrderForSelectedText:[self usesSelectionOrderForSelectedText]];
    [[self wordSelectionView] setText:text];
    [[self wordSelectionView] setHidden:NO];

    KayokoHeaderView *headerView = [[self wordSelectionView] headerView];
    [headerView setHidden:NO];
    [headerView setHistorySwitcherVisible:NO animated:NO];
    NSString *textActionsTitle = [[KayokoPasteboardManager localizationBundle]
        localizedStringForKey:@"Text Actions"
                        value:@"文本动作"
                        table:@"Tweak"];
    [headerView setTitleImageName:@"link.badge.plus" accessibilityLabel:textActionsTitle];
    [headerView updateStyleForButton:[headerView leadingButton]
                       withImageName:@"arrowshape.turn.up.backward"
                           imageSize:kKayokoFavoritesButtonImageSize
                           tintColor:[UIColor labelColor]];
    [headerView updateStyleForButton:[headerView trailingButton]
                       withImageName:(automaticallyPaste ? @"doc.on.clipboard" : @"doc.on.doc.fill")imageSize
                                    :kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    [[headerView alternateTrailingButton] setHidden:NO];
    [[headerView alternateTrailingButton] setEnabled:YES];
    [[headerView alternateTrailingButton] setAlpha:1.0];
    [[headerView selectionActionButton] setHidden:NO];
    NSString *translationImageName = [UIImage systemImageNamed:@"character.bubble"] ? @"character.bubble" : @"globe";
    [headerView updateStyleForButton:[headerView translationButton]
                       withImageName:translationImageName
                           imageSize:kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    [headerView updateStyleForButton:[headerView shareButton]
                       withImageName:@"square.and.arrow.up"
                           imageSize:kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    [[headerView shareButton] setHidden:NO];
    [[headerView leadingButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Back"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
    [[headerView trailingButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle]
                                  localizedStringForKey:(automaticallyPaste ? @"Paste" : @"Copy")
                                                  value:nil
                                                  table:@"Tweak"]];
    [[headerView alternateTrailingButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Selection Order"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
    [[headerView shareButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Share"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
    [self configureEditButton];
    [self updateSelectionOrderButtonState];
    [self updateActionButtonState];
    [self updateSelectionActionButtonStates];
    [self updateTranslationButtonState];
    [self updateShareButtonState];
}

#pragma mark - Dismissal

- (void)hideWordSelection {
    [self resetWordSelectionState];
}

#pragma mark - Actions

- (void)handleActionButtonWithAutomaticallyPaste:(BOOL)automaticallyPaste {
    KayokoPasteboardItem *sourceItem = [self sourceItem];
    if (!sourceItem || ![self isShowingWordSelection] || ![self hasSelectedText]) {
        return;
    }

    NSString *text = [self selectedText];
    KayokoPasteboardItem *selectedItem =
        [[KayokoPasteboardItem alloc] initWithBundleIdentifier:[sourceItem bundleIdentifier]
                                                    andContent:text
                                                withImageNamed:@""];
    NSString *historyKey = [self sourceHistoryKey] ?: kKayokoHistoryKeyHistory;
    if (automaticallyPaste) {
        [[KayokoPasteboardManager sharedInstance] writePasteboardItem:selectedItem
                                                    sourceHistoryItem:sourceItem
                                                   fromHistoryWithKey:historyKey
                                                 allowsAutomaticPaste:YES];
    } else {
        KayokoPasteboardManager *pasteboardManager = [KayokoPasteboardManager sharedInstance];
        if ([pasteboardManager copyPasteboardItemToPasteboard:selectedItem]) {
            [pasteboardManager addPasteboardItem:selectedItem toHistoryWithKey:kKayokoHistoryKeyHistory];
        }
    }

    [[self delegate] wordSelectionViewController:self didRequestHideContainerAfterDirectPaste:automaticallyPaste];
    [[self delegate] wordSelectionViewController:self triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleMedium];
}

- (void)handleSelectionOrderButtonPressed {
    [self setUsesSelectionOrderForSelectedText:![self usesSelectionOrderForSelectedText]];
    [[self delegate] wordSelectionViewController:self triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleLight];
}

- (void)handleSelectionActionButtonPressed {
    KayokoWordSelectionView *wordSelectionView = [self wordSelectionView];
    BOOL didChange = [wordSelectionView hasAllTokensSelected] ? [wordSelectionView clearSelectedTokens]
                                                               : [wordSelectionView selectAllTokens];
    if (didChange) {
        [[self delegate] wordSelectionViewController:self triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleLight];
    }
}

- (void)handleTranslationButtonPressed {
    if (![self hasSelectedText]) {
        return;
    }

    KayokoHeaderView *headerView = [[self wordSelectionView] headerView];
    if ([[self systemTranslationPresenter] presentTranslationForText:[self selectedText]
                                                      fromController:self
                                                          anchorView:[headerView translationButton]]) {
        [[self delegate] wordSelectionViewController:self triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleLight];
    }
}

- (void)handleShareButtonPressed {
    NSString *text = [self selectedText];
    if ([text length] == 0) {
        return;
    }

    KayokoHeaderView *headerView = [[self wordSelectionView] headerView];
    if ([[self activitySharePresenter] presentActivityItems:@[ text ] fromController:self anchorView:[headerView shareButton]]) {
        [[self delegate] wordSelectionViewController:self triggerHapticFeedbackWithStyle:UIImpactFeedbackStyleLight];
    }
}

#pragma mark - State

- (void)setUsesSelectionOrderForSelectedText:(BOOL)usesSelectionOrderForSelectedText {
    if (_usesSelectionOrderForSelectedText == usesSelectionOrderForSelectedText) {
        return;
    }

    _usesSelectionOrderForSelectedText = usesSelectionOrderForSelectedText;
    [[self wordSelectionView] setUsesSelectionOrderForSelectedText:usesSelectionOrderForSelectedText];
    [self updateSelectionOrderButtonState];
    [self updateTranslationButtonState];
}

- (void)resetWordSelectionState {
    [self setActionFailureToastRequestIdentifier:[self actionFailureToastRequestIdentifier] + 1];
    [[self actionFailureToastLabel] setHidden:YES];
    [[self systemTranslationPresenter] dismissTranslationAnimated:NO];
    [[self activitySharePresenter] dismissActivityAnimated:NO];
    [[[[self wordSelectionView] headerView] translationButton] setHidden:YES];
    [[[[self wordSelectionView] headerView] shareButton] setHidden:YES];
    [self setEditButtonHidden:YES];
    [[self wordSelectionView] setHidden:YES];
    [[self wordSelectionView] setUserInteractionEnabled:YES];
    [[self wordSelectionView] reset];
    [self setSourceItem:nil];
    [self setSourceHistoryKey:nil];
}

#pragma mark - Edit

- (void)configureEditButton {
    KayokoHeaderView *headerView = [[self wordSelectionView] headerView];
    [headerView updateStyleForButton:[headerView editButton]
                       withImageName:@"square.and.pencil"
                           imageSize:kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    [[headerView editButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Edit"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
    [self setEditButtonHidden:NO];
    [self setEditButtonEnabled:YES];
}

- (void)setEditButtonHidden:(BOOL)hidden {
    UIButton *editButton = [[[self wordSelectionView] headerView] editButton];
    [editButton setHidden:hidden];
    if (hidden) {
        [editButton setEnabled:NO];
        [editButton setAlpha:0];
    }
}

- (void)setEditButtonEnabled:(BOOL)enabled {
    UIButton *editButton = [[[self wordSelectionView] headerView] editButton];
    [editButton setEnabled:enabled];
    [editButton setAlpha:(enabled && ![editButton isHidden]) ? 1.0 : 0.35];
}

- (void)handleEditButtonPressed {
    if (![self isShowingWordSelection] || ![self sourceItem] || [[self sourceHistoryKey] length] == 0) {
        return;
    }

    UIButton *editButton = [[[self wordSelectionView] headerView] editButton];
    if ([editButton isHidden] || ![editButton isEnabled]) {
        return;
    }

    [self setEditButtonEnabled:NO];
    [[self delegate] wordSelectionViewControllerDidRequestEdit:self];
}

#pragma mark - Header

- (void)updateActionButtonState {
    BOOL enabled = [self hasSelectedText];
    UIButton *actionButton = [[[self wordSelectionView] headerView] trailingButton];
    [actionButton setEnabled:enabled];
    [actionButton setAlpha:enabled ? 1.0 : 0.35];
}

- (void)updateShareButtonState {
    UIButton *shareButton = [[[self wordSelectionView] headerView] shareButton];
    BOOL enabled = [self hasSelectedText];
    [shareButton setEnabled:enabled];
    [shareButton setAlpha:enabled ? 1.0 : 0.35];
}

- (void)handleTextActionButtonPressed {
    if ([self presentedViewController] || [self isBeingDismissed]) {
        return;
    }

    NSArray<NSDictionary<NSString *, id> *> *actions = [self loadTextActions];
    if ([actions count] == 0) {
        return;
    }

    if ([actions count] == 1) {
        [self openTextAction:actions.firstObject];
        return;
    }

    __weak typeof(self) weakSelf = self;
    KayokoQuickActionPanelViewController *panel = [[KayokoQuickActionPanelViewController alloc]
        initWithActions:actions
        anchoringAboveView:[[self parentViewController] view]
        placement:KayokoQuickActionPanelPlacementAboveAnchor
        selectionHandler:^(NSDictionary<NSString *, id> *action) {
          [weakSelf openTextAction:action];
        }];
    [self presentViewController:panel animated:YES completion:nil];
}

- (NSArray<NSDictionary<NSString *, id> *> *)loadTextActions {
    return [KayokoQuickAction actionsForKind:KayokoQuickActionKindText];
}

- (void)openTextAction:(NSDictionary<NSString *, id> *)action {
    NSString *selectedText = [self selectedText] ?: @"";
    __weak typeof(self) weakSelf = self;
    [KayokoQuickAction openAction:action
                            input:selectedText
                completionHandler:^(BOOL success) {
                  if (success) {
                      return;
                  }
                  [weakSelf showActionFailureToast];
                }];
}

- (void)showActionFailureToast {
    NSUInteger requestIdentifier = [self actionFailureToastRequestIdentifier] + 1;
    [self setActionFailureToastRequestIdentifier:requestIdentifier];

    UILabel *toastLabel = [self actionFailureToastLabel];
    if (!toastLabel) {
        toastLabel = [[UILabel alloc] init];
        [toastLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
        [toastLabel setTextAlignment:NSTextAlignmentCenter];
        [toastLabel setTextColor:[UIColor whiteColor]];
        [toastLabel setFont:[UIFont systemFontOfSize:14 weight:UIFontWeightMedium]];
        [toastLabel setBackgroundColor:[UIColor colorWithWhite:0 alpha:0.78]];
        [[toastLabel layer] setCornerRadius:10];
        [toastLabel setClipsToBounds:YES];
        [toastLabel setUserInteractionEnabled:NO];
        [[self view] addSubview:toastLabel];
        [NSLayoutConstraint activateConstraints:@[
            [[toastLabel centerXAnchor] constraintEqualToAnchor:[[self view] centerXAnchor]],
            [[toastLabel bottomAnchor] constraintEqualToAnchor:[[self view] safeAreaLayoutGuide].bottomAnchor constant:-24],
            [[toastLabel leadingAnchor] constraintGreaterThanOrEqualToAnchor:[[self view] leadingAnchor] constant:24],
            [[toastLabel trailingAnchor] constraintLessThanOrEqualToAnchor:[[self view] trailingAnchor] constant:-24],
            [[toastLabel heightAnchor] constraintGreaterThanOrEqualToConstant:36]
        ]];
        [self setActionFailureToastLabel:toastLabel];
    }

    [toastLabel setText:@"链接跳转失败，请检查链接!"];
    [toastLabel setAlpha:0.0];
    [toastLabel setHidden:NO];
    [[self view] bringSubviewToFront:toastLabel];
    [UIView animateWithDuration:0.12 animations:^{
      [toastLabel setAlpha:1.0];
    }];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     __strong typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf || [strongSelf actionFailureToastRequestIdentifier] != requestIdentifier) {
                         return;
                     }
                     [UIView animateWithDuration:0.12
                         animations:^{
                           [toastLabel setAlpha:0.0];
                         }
                         completion:^(__unused BOOL finished) {
                           if ([strongSelf actionFailureToastRequestIdentifier] == requestIdentifier) {
                               [toastLabel setHidden:YES];
                           }
                         }];
                   });
}

- (void)updateSelectionOrderButtonState {
    UIButton *selectionOrderButton = [[[self wordSelectionView] headerView] alternateTrailingButton];
    BOOL enabled = [self usesSelectionOrderForSelectedText];
    NSString *preferredImageName = enabled ? @"123.rectangle.fill" : @"123.rectangle";
    NSString *imageName = [UIImage systemImageNamed:preferredImageName] ? preferredImageName : @"textformat.123";
    [[[self wordSelectionView] headerView]
        updateStyleForButton:selectionOrderButton
               withImageName:imageName
                   imageSize:kKayokoBackButtonImageSize
                   tintColor:[UIColor labelColor]];
    [selectionOrderButton setSelected:enabled];
    UIAccessibilityTraits traits = [selectionOrderButton accessibilityTraits] | UIAccessibilityTraitButton;
    if (enabled) {
        traits |= UIAccessibilityTraitSelected;
    } else {
        traits &= ~UIAccessibilityTraitSelected;
    }
    [selectionOrderButton setAccessibilityTraits:traits];
}

- (void)updateSelectionActionButtonStates {
    KayokoWordSelectionView *wordSelectionView = [self wordSelectionView];
    UIButton *selectionActionButton = [[wordSelectionView headerView] selectionActionButton];
    BOOL hasAllTokensSelected = [wordSelectionView hasAllTokensSelected];
    BOOL enabled = [wordSelectionView hasTokens];
    NSString *imageName = hasAllTokensSelected ? @"xmark.circle" : @"checkmark.circle";
    NSString *accessibilityKey = hasAllTokensSelected ? @"Clear Selection" : @"Select All";

    [[wordSelectionView headerView] updateStyleForButton:selectionActionButton
                                             withImageName:imageName
                                                 imageSize:kKayokoBackButtonImageSize
                                                 tintColor:[UIColor labelColor]];
    [selectionActionButton setEnabled:enabled];
    [selectionActionButton setAlpha:enabled ? 1.0 : 0.35];
    [selectionActionButton
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:accessibilityKey
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
}

- (void)updateTranslationButtonState {
    UIButton *translationButton = [[[self wordSelectionView] headerView] translationButton];
    BOOL available = [[self systemTranslationPresenter] isAvailable];
    [translationButton setHidden:!available];
    if (!available) {
        return;
    }

    BOOL enabled = [self hasSelectedText];
    [translationButton setEnabled:enabled];
    [translationButton setAlpha:enabled ? 1.0 : 0.35];
    [translationButton
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Translate"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
}

@end
