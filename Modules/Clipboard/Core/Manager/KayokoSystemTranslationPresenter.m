//
//  KayokoSystemTranslationPresenter.m
//  Kayoko
//

#import "KayokoSystemTranslationPresenter.h"

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>

static char const *kKayokoTranslationUIServicesPath =
    "/System/Library/PrivateFrameworks/TranslationUIServices.framework/TranslationUIServices";

typedef void (*KayokoSystemTranslationSendVoidWithObject)(id object, SEL selector, id value);
typedef void (*KayokoSystemTranslationSendVoidWithBoolean)(id object, SEL selector, BOOL value);
typedef BOOL (*KayokoSystemTranslationSendBoolean)(id object, SEL selector);

@interface KayokoSystemTranslationPresenter ()
<UIPopoverPresentationControllerDelegate>

@property(nonatomic, strong, nullable) UIViewController *presentedController;

- (BOOL)isPresentingTranslation;
- (BOOL)hasCompatibleSystemTranslationUI;

@end

@implementation KayokoSystemTranslationPresenter

- (BOOL)isAvailable {
    return [self hasCompatibleSystemTranslationUI];
}

- (BOOL)presentTranslationForText:(NSString *)text
                   fromController:(UIViewController *)controller
                       anchorView:(UIView *)anchorView {
    if (![self isAvailable] || [text length] == 0 || !controller || [self isPresentingTranslation] ||
        [controller presentedViewController] || [controller isBeingPresented] || [controller isBeingDismissed] ||
        ![[controller viewIfLoaded] window]) {
        return NO;
    }

    Class translationViewControllerClass = NSClassFromString(@"LTUITranslationViewController");
    id translationViewController = [[translationViewControllerClass alloc] init];
    SEL setText = NSSelectorFromString(@"setText:");
    SEL setTargetLocale = NSSelectorFromString(@"setTargetLocale:");
    SEL setSourceLocale = NSSelectorFromString(@"setSourceLocale:");
    SEL setIsSourceEditable = NSSelectorFromString(@"setIsSourceEditable:");
    SEL setDismissCompletionHandler = NSSelectorFromString(@"setDismissCompletionHandler:");

    if (!translationViewController || ![translationViewController respondsToSelector:setText]) {
        return NO;
    }

    ((KayokoSystemTranslationSendVoidWithObject)objc_msgSend)(translationViewController, setText,
                                                                [[NSAttributedString alloc] initWithString:text]);
    if ([translationViewController respondsToSelector:setTargetLocale]) {
        ((KayokoSystemTranslationSendVoidWithObject)objc_msgSend)(
            translationViewController, setTargetLocale, [[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"]);
    }
    if ([translationViewController respondsToSelector:setSourceLocale]) {
        ((KayokoSystemTranslationSendVoidWithObject)objc_msgSend)(translationViewController, setSourceLocale, nil);
    }
    if ([translationViewController respondsToSelector:setIsSourceEditable]) {
        ((KayokoSystemTranslationSendVoidWithBoolean)objc_msgSend)(translationViewController, setIsSourceEditable, NO);
    }
    if ([translationViewController respondsToSelector:setDismissCompletionHandler]) {
        __weak typeof(self) weakSelf = self;
        __weak UIViewController *weakTranslationViewController = translationViewController;
        void (^dismissHandler)(void) = ^{
          __strong typeof(weakSelf) strongSelf = weakSelf;
          if ([strongSelf presentedController] == weakTranslationViewController) {
              [strongSelf setPresentedController:nil];
          }
        };
        ((KayokoSystemTranslationSendVoidWithObject)objc_msgSend)(translationViewController,
                                                                    setDismissCompletionHandler, dismissHandler);
    }

    [self setPresentedController:translationViewController];

    UIView *presentationAnchor = anchorView ?: [controller viewIfLoaded];
    [translationViewController setModalPresentationStyle:UIModalPresentationPopover];
    UIPopoverPresentationController *popover = [translationViewController popoverPresentationController];
    if (popover) {
        [popover setDelegate:self];
        [popover setSourceView:presentationAnchor];
        [popover setSourceRect:[presentationAnchor bounds]];
        [popover setPermittedArrowDirections:UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown];
    }

    UIWindow *hostWindow = [presentationAnchor window] ?: [[controller viewIfLoaded] window];
    CGFloat width = MIN(CGRectGetWidth([hostWindow bounds]) - 32.0, 360.0);
    if (width <= 0) {
        width = 320.0;
    }
    [translationViewController setPreferredContentSize:CGSizeMake(width, 340.0)];

    [controller presentViewController:translationViewController animated:YES completion:nil];
    return YES;
}

#pragma mark - UIPopoverPresentationControllerDelegate

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller
                                                              traitCollection:(UITraitCollection *)traitCollection {
    return UIModalPresentationPageSheet;
}

- (void)prepareForPopoverPresentation:(UIPopoverPresentationController *)popoverPresentationController {
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet =
            [[popoverPresentationController presentedViewController] sheetPresentationController];
        if (sheet) {
            [sheet setDetents:@[
                [UISheetPresentationControllerDetent mediumDetent],
                [UISheetPresentationControllerDetent largeDetent]
            ]];
            [sheet setPrefersGrabberVisible:YES];
        }
    }
}

- (void)dismissTranslationAnimated:(BOOL)animated {
    UIViewController *presentedController = [self presentedController];
    if ([presentedController presentingViewController]) {
        [presentedController dismissViewControllerAnimated:animated completion:nil];
    }
    [self setPresentedController:nil];
}

#pragma mark - Runtime Compatibility

- (BOOL)isPresentingTranslation {
    UIViewController *presentedController = [self presentedController];
    if (!presentedController) {
        return NO;
    }
    if ([presentedController presentingViewController] || [presentedController isBeingPresented] ||
        [presentedController isBeingDismissed]) {
        return YES;
    }

    [self setPresentedController:nil];
    return NO;
}

- (BOOL)hasCompatibleSystemTranslationUI {
    static void *translationUIServicesHandle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      translationUIServicesHandle = dlopen(kKayokoTranslationUIServicesPath, RTLD_LAZY);
    });
    if (!translationUIServicesHandle) {
        return NO;
    }

    Class translationViewControllerClass = NSClassFromString(@"LTUITranslationViewController");
    SEL setText = NSSelectorFromString(@"setText:");
    SEL expandSheet = NSSelectorFromString(@"expandSheet");
    if (!translationViewControllerClass || ![translationViewControllerClass instancesRespondToSelector:setText] ||
        ![translationViewControllerClass instancesRespondToSelector:expandSheet]) {
        return NO;
    }
    return YES;
}

@end
