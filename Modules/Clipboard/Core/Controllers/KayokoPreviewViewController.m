//
//  KayokoPreviewViewController.m
//  Kayoko
//

#import "KayokoPreviewViewController.h"

#import "KayokoHeaderButtonStyle.h"
#import "KayokoHeaderView.h"
#import "KayokoActivitySharePresenter.h"
#import "KayokoHistoryItemActionHandler.h"
#import "KayokoPasteboardItem.h"
#import "KayokoPasteboardManager.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoPreviewView.h"
#import "KayokoQuickAction.h"
#import "KayokoQuickActionPanelViewController.h"

static NSString *kayokoPreviewTextByTrimmingBoundaryNewlines(NSString *text) {
    return [(text ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

NS_ASSUME_NONNULL_BEGIN

@interface KayokoPreviewViewController ()
#pragma mark - Views

@property(nonatomic, strong, readwrite) KayokoPreviewView *previewView;

#pragma mark - State

@property(nonatomic, copy, nullable, readwrite) NSString *sourceHistoryKey;
@property(nonatomic, strong, nullable, readwrite) KayokoPasteboardItem *previewItem;
@property(nonatomic, strong) KayokoHistoryItemActionHandler *actionHandler;
@property(nonatomic, strong) KayokoActivitySharePresenter *activitySharePresenter;
@property(nonatomic, strong, nullable) UILabel *actionFailureToastLabel;
@property(nonatomic, assign) NSUInteger actionFailureToastRequestIdentifier;

- (NSString *)actionImageNameForItem:(KayokoPasteboardItem *)item;
- (NSString *)actionAccessibilityLabelKeyForItem:(KayokoPasteboardItem *)item;
- (nullable id)activityItemForPreviewItem:(KayokoPasteboardItem *)item;
- (void)updateShareButtonState;
- (void)configureEditButton;
- (void)setEditButtonHidden:(BOOL)hidden;
- (void)handleEditButtonPressed;
- (void)handleImageActionButtonPressed;
- (void)handleImageDoubleTapGesture:(UITapGestureRecognizer *)gestureRecognizer;
- (NSArray<NSDictionary<NSString *, id> *> *)loadImageActions;
- (void)openImageAction:(NSDictionary<NSString *, id> *)action;
- (void)showActionFailureToast;
@end

NS_ASSUME_NONNULL_END

@implementation KayokoPreviewViewController

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _previewView = [[KayokoPreviewView alloc]
            initWithName:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Preview"
                                                                                       value:nil
                                                                                       table:@"Tweak"]];
        _actionHandler = [[KayokoHistoryItemActionHandler alloc] init];
        _activitySharePresenter = [[KayokoActivitySharePresenter alloc] init];
        [[[_previewView headerView] shareButton]
                   addTarget:self
                      action:@selector(handleShareButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
        [[[_previewView headerView] editButton]
                   addTarget:self
                      action:@selector(handleEditButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
        [[[_previewView headerView] alternateTrailingButton]
                   addTarget:self
                      action:@selector(handleImageActionButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
        UIImageView *imageView = [_previewView imageView];
        [imageView setUserInteractionEnabled:YES];
        UITapGestureRecognizer *doubleTapGestureRecognizer =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleImageDoubleTapGesture:)];
        [doubleTapGestureRecognizer setNumberOfTapsRequired:2];
        [doubleTapGestureRecognizer setCancelsTouchesInView:NO];
        [imageView addGestureRecognizer:doubleTapGestureRecognizer];
        [self setView:_previewView];
    }
    return self;
}

#pragma mark - Presentation

- (void)showPreviewWithItem:(KayokoPasteboardItem *)item sourceHistoryKey:(NSString *)sourceHistoryKey {
    [self setPreviewItem:item];
    [self setSourceHistoryKey:sourceHistoryKey];
    [[self previewView] setUserInteractionEnabled:YES];

    if (![[item imageName] isEqualToString:@""]) {
        NSData *imageData = [[NSFileManager defaultManager]
            contentsAtPath:[NSString stringWithFormat:@"%@/%@", [KayokoPasteboardManager historyImagesPath],
                                                      [item imageName]]];
        [[self previewView] reset];
        [[self previewView] showImage:[UIImage imageWithData:imageData]];
    } else {
        NSString *previewText = kayokoPreviewTextByTrimmingBoundaryNewlines([item content]);
        [[self previewView] showText:previewText];
    }
    KayokoHeaderView *headerView = [[self previewView] headerView];
    [headerView setHidden:NO];
    [headerView setHistorySwitcherVisible:NO animated:NO];
    [headerView setTitleText:[[self previewView] name]];
    [headerView updateStyleForButton:[headerView leadingButton]
                       withImageName:@"arrowshape.turn.up.backward"
                           imageSize:kKayokoFavoritesButtonImageSize
                           tintColor:[UIColor labelColor]];
    [headerView updateStyleForButton:[headerView trailingButton]
                       withImageName:[self actionImageNameForItem:item]
                           imageSize:kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    [headerView updateStyleForButton:[headerView shareButton]
                       withImageName:@"square.and.arrow.up"
                           imageSize:kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    [headerView updateStyleForButton:[headerView alternateTrailingButton]
                       withImageName:@"link.badge.plus"
                           imageSize:kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    BOOL isImageItem = [[item imageName] length] > 0;
    [[headerView alternateTrailingButton] setHidden:!isImageItem];
    [[headerView alternateTrailingButton] setEnabled:isImageItem];
    [[headerView alternateTrailingButton] setAlpha:isImageItem ? 1.0 : 0.0];
    [[headerView shareButton] setHidden:NO];
    [[headerView leadingButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Back"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
    NSString *actionAccessibilityLabelKey = [self actionAccessibilityLabelKeyForItem:item];
    [[headerView trailingButton] setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle]
                                                           localizedStringForKey:actionAccessibilityLabelKey
                                                                           value:nil
                                                                           table:@"Tweak"]];
    [[headerView trailingButton] setEnabled:YES];
    [[headerView trailingButton] setAlpha:1.0];
    [[headerView shareButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Share"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
    [[headerView alternateTrailingButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Open in url"
                                                                                            value:@"打开跳转链接"
                                                                                            table:@"Tweak"]];
    [self configureEditButton];
    [self updateShareButtonState];
}

#pragma mark - Actions

- (NSString *)actionImageNameForItem:(KayokoPasteboardItem *)item {
    if ([[item imageName] length] > 0) {
        return @"square.and.arrow.down";
    }
    if ([item hasLink]) {
        return @"arrow.up";
    }
    return @"doc.on.doc.fill";
}

- (NSString *)actionAccessibilityLabelKeyForItem:(KayokoPasteboardItem *)item {
    if ([[item imageName] length] > 0) {
        return @"Save to Photos";
    }
    if ([item hasLink]) {
        return @"Open";
    }
    return @"Copy";
}

- (id)activityItemForPreviewItem:(KayokoPasteboardItem *)item {
    if ([[item imageName] length] > 0) {
        return [[self previewView] imageView].image;
    }

    if ([item hasLink]) {
        NSURL *URL = [NSURL URLWithString:[item content] ?: @""];
        if (URL) {
            return URL;
        }
    }

    NSString *text = kayokoPreviewTextByTrimmingBoundaryNewlines([item content]);
    return [text length] > 0 ? text : nil;
}

- (void)updateShareButtonState {
    UIButton *shareButton = [[[self previewView] headerView] shareButton];
    BOOL enabled = [self activityItemForPreviewItem:[self previewItem]] != nil;
    [shareButton setEnabled:enabled];
    [shareButton setAlpha:enabled ? 1.0 : 0.35];
}

- (void)configureEditButton {
    if (![self canEditPreviewText]) {
        [self setEditButtonHidden:YES];
        return;
    }

    KayokoHeaderView *headerView = [[self previewView] headerView];
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
    UIButton *editButton = [[[self previewView] headerView] editButton];
    [editButton setHidden:hidden];
    if (hidden) {
        [editButton setEnabled:NO];
        [editButton setAlpha:0];
    }
}

- (void)setEditButtonEnabled:(BOOL)enabled {
    UIButton *editButton = [[[self previewView] headerView] editButton];
    [editButton setEnabled:enabled];
    [editButton setAlpha:(enabled && ![editButton isHidden]) ? 1.0 : 0.35];
}

- (BOOL)canEditPreviewText {
    KayokoPasteboardItem *item = [self previewItem];
    return item && [[item imageName] length] == 0 && [[self sourceHistoryKey] length] > 0;
}

- (void)handleEditButtonPressed {
    if (![self canEditPreviewText]) {
        return;
    }

    UIButton *editButton = [[[self previewView] headerView] editButton];
    if ([editButton isHidden] || ![editButton isEnabled]) {
        return;
    }

    [self setEditButtonEnabled:NO];
    [[self delegate] previewViewControllerDidRequestEdit:self];
}

- (void)handleImageActionButtonPressed {
    KayokoPasteboardItem *item = [self previewItem];
    if (!item || [[self previewView] isHidden] || [[item imageName] length] == 0) {
        return;
    }

    NSArray<NSDictionary<NSString *, id> *> *actions = [self loadImageActions];
    if ([actions count] == 0) {
        return;
    }

    if ([actions count] == 1) {
        [self openImageAction:actions.firstObject];
        return;
    }

    if ([self presentedViewController] || [self isBeingDismissed]) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    KayokoQuickActionPanelViewController *panel = [[KayokoQuickActionPanelViewController alloc]
        initWithActions:actions
        anchoringAboveView:[[self parentViewController] view]
        placement:KayokoQuickActionPanelPlacementAboveAnchor
        selectionHandler:^(NSDictionary<NSString *, id> *action) {
          [weakSelf openImageAction:action];
        }];
    [self presentViewController:panel animated:YES completion:nil];
}

- (void)handleImageDoubleTapGesture:(UITapGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer state] != UIGestureRecognizerStateEnded || [[self previewView] isHidden]) {
        return;
    }

    KayokoPasteboardItem *item = [self previewItem];
    if (!item || [[item imageName] length] == 0) {
        return;
    }

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    NSString *link = [[defaults stringForKey:kKayokoPreferenceKeyImageDoubleTapActionURL]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([link length] == 0) {
        return;
    }

    if (![[KayokoPasteboardManager sharedInstance] copyPasteboardItemToPasteboard:item]) {
        [self showActionFailureToast];
        return;
    }

    NSURL *URL = [NSURL URLWithString:link];
    if (!URL) {
        [self showActionFailureToast];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[UIApplication sharedApplication] openURL:URL
                                       options:@{}
                             completionHandler:^(BOOL success) {
                               if (success) {
                                   return;
                               }
                               dispatch_async(dispatch_get_main_queue(), ^{
                                 [weakSelf showActionFailureToast];
                               });
                             }];
}

- (NSArray<NSDictionary<NSString *, id> *> *)loadImageActions {
    return [KayokoQuickAction actionsForKind:KayokoQuickActionKindImage];
}

- (void)openImageAction:(NSDictionary<NSString *, id> *)action {
    KayokoPasteboardItem *item = [self previewItem];
    if (!item || [[item imageName] length] == 0 ||
        ![[KayokoPasteboardManager sharedInstance] copyPasteboardItemToPasteboard:item]) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    [KayokoQuickAction openAction:action
                            input:@""
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

- (void)handleShareButtonPressed {
    id activityItem = [self activityItemForPreviewItem:[self previewItem]];
    if (!activityItem || [[self previewView] isHidden]) {
        return;
    }

    KayokoHeaderView *headerView = [[self previewView] headerView];
    if ([[self activitySharePresenter] presentActivityItems:@[ activityItem ]
                                             fromController:self
                                                 anchorView:[headerView shareButton]]) {
        if ([self hapticFeedbackHandler]) {
            [self hapticFeedbackHandler](UIImpactFeedbackStyleLight);
        }
    }
}

- (void)handleActionButtonWithCompletion:(void (^)(BOOL success))completion {
    KayokoPasteboardItem *item = [self previewItem];
    if (!item || [[self previewView] isHidden]) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    if ([[item imageName] length] > 0) {
        [[self actionHandler] saveImageForItem:item completion:completion];
        return;
    }
    if ([item hasLink]) {
        [[self actionHandler] openLinkForItem:item completion:completion];
        return;
    }

    [[self actionHandler] copyItem:item completion:completion];
}

#pragma mark - Dismissal

- (void)hidePreview {
    [self setActionFailureToastRequestIdentifier:[self actionFailureToastRequestIdentifier] + 1];
    [[self actionFailureToastLabel] setHidden:YES];
    [[self activitySharePresenter] dismissActivityAnimated:NO];
    [[[[self previewView] headerView] shareButton] setHidden:YES];
    [[[[self previewView] headerView] alternateTrailingButton] setHidden:YES];
    [self setEditButtonHidden:YES];
    [[self previewView] setUserInteractionEnabled:YES];
    [self setPreviewItem:nil];

    [[self previewView] reset];
    [self setSourceHistoryKey:nil];
}

- (void)resetPreviewState {
    [self setActionFailureToastRequestIdentifier:[self actionFailureToastRequestIdentifier] + 1];
    [[self actionFailureToastLabel] setHidden:YES];
    [[self activitySharePresenter] dismissActivityAnimated:NO];
    [[self previewView] reset];
    [[self previewView] setHidden:YES];
    [[self previewView] setUserInteractionEnabled:YES];
    [[[[self previewView] headerView] shareButton] setHidden:YES];
    [[[[self previewView] headerView] alternateTrailingButton] setHidden:YES];
    [self setEditButtonHidden:YES];
    [self setPreviewItem:nil];
    [self setSourceHistoryKey:nil];
}

- (void)scrollToTopAnimated:(BOOL)animated {
    [[self previewView] scrollToTopAnimated:animated];
}

@end
