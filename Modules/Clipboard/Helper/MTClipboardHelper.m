//
//  MTClipboardHelper.m
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import "MTClipboardHelperConfiguration.h"
#import "MTClipboardHelperHookInstaller.h"
#import "MTClipboardHelperProcessContext.h"
#import "MTClipboardHelperRuntime.h"

__attribute((constructor)) static void initialize() {
    MTClipboardHelperConfiguration *configuration = [MTClipboardHelperConfiguration currentConfiguration];
    if (!configuration.isEnabled) {
        return;
    }

    MTClipboardHelperProcessContext *context = [MTClipboardHelperProcessContext currentContext];
    NSUInteger helperActivationMethod = configuration.activationMethod;

    BOOL systemGestureRecognizerMode = configuration.gestureRecognizerMode == kMTGestureRecognizerModeSystem;
    BOOL swipeUpEnabled = (configuration.activationMethod & kActivationMethodSwipeUp) != 0;
    BOOL spotlightProcess = [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.Spotlight"];
    if (systemGestureRecognizerMode && !spotlightProcess) {
        helperActivationMethod &= ~kActivationMethodSwipeUp;
    }

    switch (context.kind) {
    case MTClipboardHelperProcessKindKeyboardExtension:
        [MTClipboardHelperHookInstaller
            installKeyboardExtensionHooksWithActivationMethod:helperActivationMethod
                                         spotlightSwipeUpOnly:(systemGestureRecognizerMode && swipeUpEnabled)];
        return;
    case MTClipboardHelperProcessKindSpringBoard:
        [[MTClipboardHelperRuntime sharedRuntime] installSpringBoardRuntimeWithConfiguration:configuration];
        [MTClipboardHelperHookInstaller installSpringBoardActivationHooksWithActivationMethod:helperActivationMethod];
        return;
    case MTClipboardHelperProcessKindApplication:
        [MTClipboardHelperHookInstaller installApplicationHooksWithActivationMethod:helperActivationMethod];
        [[MTClipboardHelperRuntime sharedRuntime] installApplicationRuntimeWithConfiguration:configuration];
        return;
    case MTClipboardHelperProcessKindUnsupported:
        return;
    }
}
