#import "common.h"
#import "MTKeyboardUIKit.h"

extern id delegate;
extern UIKeyboardImpl *kbImpl;
extern UIColor *currentTintColor;
extern UIColor *currentBackgroundTintColor;
extern BOOL isLandscape;
extern NSMutableDictionary *prefs;
extern BOOL isDictating;
extern BOOL toggledOn;
extern UIKeyboardDockView *dockView;
//extern BOOL isSandboxed;
extern CGPoint startPosition;
extern CGPoint endPosition;
extern NSDate *prevTime;
extern BOOL singleTapDictationEnabled;
extern BOOL singleTapGlobeEnabled;
extern BOOL isTrackPadMode;
extern BOOL isSpringBoard;
extern BOOL isApplication;
extern BOOL isSafari;
//extern BOOL shouldSendScrollExecution;
extern NSString *key;
extern BOOL isDraggedGesture;
extern UIKeyboardDockView *dockV;
extern NSBundle *tweakBundle;
extern BOOL firstInit;
extern MTStudlyCapsType spongebobEntropy;

extern CGFloat heightOffset;

// 工具栏图标的默认颜色：未开启「跟随系统」时为 systemBlue，开启后取系统键盘
// 的标签色（深色模式白、浅色模式黑）。
extern UIColor *MTToolbarDefaultTintColor(NSDictionary *preferences);

#ifdef __cplusplus
extern "C" {
#endif

BOOL preferencesBool(NSString* key, BOOL fallback);
float preferencesFloat(NSString* key, float fallback);
int preferencesInt(NSString* key, int fallback);
NSString *preferencesSelectorForIdentifier(NSString* identifier, int selectorNum, int gestureType, NSString *fallback);
NSString *preferencesSelectorForIdentifierScoped(NSString* identifier, int selectorNum, int gestureType, NSString *fallback, NSString *configuration);
NSArray<NSString *> *preferencesGestureActionSelectors(NSString *identifier, int gestureType, NSString *configuration);
NSDictionary *preferencesLinkActionForSelector(NSString *selector);
BOOL preferencesIsConfiguredActionSelector(NSString *selector);

#ifdef __cplusplus
}
#endif
