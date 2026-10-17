//
//  MTClipboardHelperRuntime.h
//  Mt
//

#import "MTClipboardHelperConfiguration.h"

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTClipboardHelperRuntime : NSObject

+ (instancetype)sharedRuntime;

- (void)installApplicationRuntimeWithConfiguration:(MTClipboardHelperConfiguration *)configuration;
- (void)installSpringBoardRuntimeWithConfiguration:(MTClipboardHelperConfiguration *)configuration;

- (BOOL)activateMt;
- (BOOL)activateMtAfterCapturingCurrentFocus;
- (BOOL)activateMtFromResponder:(UIResponder *)responder;
- (void)showMt;
- (void)showMtAfterCapturingCurrentFocus;
- (void)hideMt;
- (void)toggleMt;
- (void)captureCurrentFirstResponder;
- (void)restoreCapturedFirstResponder;
- (void)paste;
- (void)pasteFromPredictionBar;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
