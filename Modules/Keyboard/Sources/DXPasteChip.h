#import <UIKit/UIKit.h>

// Clipboard image & text quick paste: while the keyboard is visible, watch
// the general pasteboard for a newly added image (or text) and float a small
// WeChat-style chip pinned to the screen's right edge, level with the input
// caret and above the keyboard, for 3 seconds -- a thumbnail for images, a
// few lines of preview text for text. Tapping it dispatches paste: to the
// first responder, exactly like the system callout menu's Paste.
@interface DXPasteChipController : NSObject
+ (instancetype)sharedController;
// Master switch + per-app allowlist (pasteimagechipapps, bundleID -> @YES,
// default all off). Also gates the paste-permission auto-answer hook.
+ (BOOL)isAllowedInCurrentApp;
- (void)keyboardDidShow:(NSNotification *)notification;
- (void)keyboardFrameWillChange:(NSNotification *)notification;
- (void)keyboardWillHide:(NSNotification *)notification;
@end
